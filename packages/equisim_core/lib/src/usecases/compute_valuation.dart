import 'dart:math' as math;

import '../audit/audit_recorder.dart';
import '../entities/dividend_event.dart';
import '../entities/fundamentals.dart';
import '../entities/valuation.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
import '../services/valuation/base_flow.dart';
import '../services/valuation/cost_of_capital.dart';
import '../services/valuation/dcf.dart';
import '../services/valuation/growth_estimator.dart';
import '../services/valuation/scenario_engine.dart';
import '../time/point_in_time_view.dart';
import '../value_objects/money.dart';
import '../value_objects/ticker.dart';

/// Insumos já resolvidos para uma avaliação.
///
/// Reunir tudo aqui mantém a cascata **pura e síncrona**: ela decide qual
/// modelo aplicar sem tocar em rede, o que permite testá-la exaustivamente e
/// executá-la dentro de uma isolate.
class ValuationInputs {
  final Ticker ticker;
  final DateTime asOf;
  final List<FundamentalsSnapshot> fundamentals;
  final List<DividendEvent> dividends;
  final double marketPrice;
  final CapmInputs capm;

  /// Margem de segurança aplicada ao preço justo, em fração.
  final double marginOfSafety;

  /// Anos de projeção explícita.
  final int projectionYears;

  /// Teto **nominal** do crescimento na perpetuidade, em fração.
  ///
  /// Precisa estar na mesma unidade do desconto, que é nominal por vir do CDI.
  /// O padrão repete o crescimento real de longo prazo apenas para não quebrar
  /// quem constrói os insumos à mão; a aplicação passa
  /// `MarketAnchors.nominalEconomyGrowth`, derivado do IPCA observado.
  final double perpetualGrowthCap;

  const ValuationInputs({
    required this.ticker,
    required this.asOf,
    required this.fundamentals,
    required this.dividends,
    required this.marketPrice,
    required this.capm,
    this.marginOfSafety = 0.0,
    this.projectionYears = 5,
    this.perpetualGrowthCap = GrowthEstimator.realEconomyGrowth,
  });
}

/// Escolhe e aplica o modelo de avaliação viável com os dados disponíveis.
///
/// A ordem é de maior para menor exigência de dados:
///
/// 1. **DCF por FCFF**, descontado ao WACC — exige fluxo de caixa, dívida e
///    ações em circulação;
/// 2. **DCF sobre LPA**, descontado ao Ke — exige apenas lucro por ação;
/// 3. **Gordon** sobre dividendos — exige apenas histórico de proventos;
/// 4. **Múltiplos** — último recurso.
///
/// O modelo aplicado **vai no resultado**, junto dos avisos. Cair
/// silenciosamente para um modelo inferior e rotular o número como "preço
/// justo" esconderia do usuário a qualidade real da estimativa.
abstract final class ValuationCascade {
  /// Avalia usando o melhor modelo possível.
  static Result<ValuationResult> evaluate(
    ValuationInputs inputs, {
    AssumptionSource Function(DcfAssumptions base)? scenarioBuilder,
    int monteCarloSamples = 10000,
    int seed = 42,
  }) {
    // A transação é aberta antes de qualquer validação: um ativo recusado por
    // falta de dado é tão auditável quanto um avaliado, e a banca pergunta
    // justamente pelos recusados.
    final audit = AuditRecorder.begin(
      '/core/valuation/${inputs.ticker.value}',
      inputPayload: _inputPayload(inputs),
    );

    if (inputs.marketPrice <= 0) {
      audit?.abort('Preço de mercado indisponível.');
      return const Err(InvalidInput('Preço de mercado indisponível.'));
    }

    final view = PointInTimeView(inputs.asOf);
    final published = view.published(inputs.fundamentals);

    if (published.isEmpty) {
      final message =
          'Nenhum exercício de ${inputs.ticker.value} havia sido divulgado em '
          '${_fmt(inputs.asOf)} (defasagem de ${view.publicationLag.inDays} dias).';
      audit?.abort(message, extra: {
        'exerciciosRecebidos': inputs.fundamentals.length,
        'exerciciosPublicados': 0,
      });
      return Err(InsufficientData(message, subject: inputs.ticker.value));
    }

    final latest = published.last;
    final warnings = <String>[];

    if (latest.fiscalPeriodEnd.year < inputs.asOf.year - 2) {
      warnings.add(
        'O exercício mais recente já divulgado é de ${latest.fiscalPeriodEnd.year}; '
        'a avaliação pode estar desatualizada.',
      );
    }

    final sharesPerQuote = quotedUnitRatio(
      sharesOutstanding: latest.sharesOutstanding,
      marketCap: latest.marketCap,
      marketPrice: inputs.marketPrice,
    );
    _auditUnitRatio(audit, inputs, latest, sharesPerQuote);
    _auditCapm(audit, inputs.capm);

    if (sharesPerQuote > 1) {
      warnings.add(
        '${inputs.ticker.value} é negociada em unit de '
        '${sharesPerQuote.toStringAsFixed(0)} ações. Os demonstrativos vêm por '
        'ação e a cotação é por unit: o valor justo é convertido para a unit '
        'antes de ser comparado ao preço.',
      );
    }

    for (final attempt in [
      () => _tryFcff(inputs, published, latest, warnings, scenarioBuilder,
          monteCarloSamples, seed, sharesPerQuote, audit),
      () => _tryEarnings(inputs, published, latest, warnings, scenarioBuilder,
          monteCarloSamples, seed, sharesPerQuote, audit),
      () => _tryGordon(inputs, published, warnings, audit),
      () => _tryMultiples(inputs, latest, warnings, sharesPerQuote, audit),
    ]) {
      final result = attempt();
      if (result != null) {
        _auditVerdict(audit, result);
        audit?.complete(_outputPayload(result));
        return Ok(result);
      }
    }

    final message =
        'Nenhum modelo de avaliação é aplicável a ${inputs.ticker.value} com os '
        'dados disponíveis.';
    audit?.abort(message, extra: {
      'modelosTentados': [
        'DCF por FCFF',
        'DCF simplificado (LPA)',
        'Gordon (dividendos)',
        'Múltiplos',
      ],
    });
    return Err(InsufficientData(message, subject: inputs.ticker.value));
  }

  // ------------------------------------------------ Unidade de negociação --

  /// Quantas ações compõem a **unit** negociada, ou 1 para a ação comum.
  ///
  /// Existe porque a fonte mistura duas convenções no mesmo ativo: as
  /// demonstrações e o `sharesOutstanding` vêm por **ação**, enquanto a
  /// cotação, o `marketCap` e os proventos vêm por **unit**. Dividir um valor
  /// de firma pelo número de ações produz preço justo por ação, que era então
  /// comparado ao preço da unit — erro de 5× em SAPR11 e KLBN11 e de 3× em
  /// BPAC11 (medido em 21/08/2026).
  ///
  /// A razão é **medida, não tabelada**: `ações × preço ÷ valor de mercado`
  /// devolve 1,00 para ação comum e o número de ações da unit para as demais,
  /// sem depender de uma lista que envelhece a cada reorganização societária.
  /// Fora da faixa plausível ou longe de um inteiro, adota-se 1 — preferível
  /// a aplicar um fator inventado.
  static double quotedUnitRatio({
    required double? sharesOutstanding,
    required double? marketCap,
    required double marketPrice,
  }) {
    if (sharesOutstanding == null || sharesOutstanding <= 0) return 1.0;
    if (marketCap == null || marketCap <= 0) return 1.0;
    if (marketPrice <= 0) return 1.0;

    final raw = sharesOutstanding * marketPrice / marketCap;
    if (!raw.isFinite) return 1.0;

    final rounded = raw.roundToDouble();
    if (rounded < 1 || rounded > maxSharesPerUnit) return 1.0;
    // A tolerância absorve a diferença de data entre o preço e o valor de
    // mercado publicado, que é de fechamento.
    if ((raw - rounded).abs() > 0.12) return 1.0;
    return rounded;
  }

  /// Teto de ações por unit. As units da B3 vão até 5 (1 ON + 4 PN).
  static const double maxSharesPerUnit = 10;

  // ------------------------------------------------------------- 1. FCFF --

  static ValuationResult? _tryFcff(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    List<String> warnings,
    AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    int samples,
    int seed,
    double sharesPerQuote,
    AuditTransaction? audit,
  ) {
    double? flowOf(FundamentalsSnapshot s) =>
        s.freeCashFlow ?? s.operatingCashFlow;

    final observedFcf = flowOf(latest);
    final rawShares = latest.sharesOutstanding;
    // A aplicabilidade do modelo é decidida sobre o exercício **observado**: a
    // normalização adiante ajusta magnitude, não ressuscita modelo.
    if (observedFcf == null ||
        observedFcf <= 0 ||
        rawShares == null ||
        rawShares <= 0) {
      return null;
    }
    // O denominador é a quantidade de **units negociadas**, para que o valor
    // por papel saia na mesma unidade do preço de tela.
    final shares = rawShares / sharesPerQuote;

    final local = [...warnings];
    if (latest.freeCashFlow == null) {
      local.add(
        'Fluxo de caixa livre ausente; usado o fluxo operacional como base.',
      );
    }

    final baseline = BaseFlowNormalizer.normalize(
      [for (final s in published) if (flowOf(s) != null) flowOf(s)!],
    );
    final baseFcf = baseline.value;
    _describeBase(baseline, 'fluxo de caixa livre', local);
    _auditBaseFlow(audit, baseline, 'fluxo de caixa livre');

    final growth = GrowthEstimator.fromHistory(
      published,
      flowOf,
      metricName: 'fluxo de caixa livre',
    );
    if (growth.clamped) local.add(growth.basis);
    _auditGrowth(audit, growth, 'fluxo de caixa livre');

    final wacc = _wacc(inputs, latest, local, sharesPerQuote, audit);
    final perpetual = GrowthEstimator.perpetual(
      explicitGrowth: growth.rate,
      economyGrowth: inputs.perpetualGrowthCap,
    );
    _auditPerpetualGrowth(audit, growth.rate, inputs.perpetualGrowthCap,
        perpetual);

    final assumptions = DcfAssumptions(
      projectionYears: inputs.projectionYears,
      growthRate: growth.rate,
      perpetualGrowth: perpetual,
      discountRate: wacc,
      marginOfSafety: inputs.marginOfSafety,
    );

    Result<double> valuate(DcfAssumptions a) => DcfCalculator.fcff(
          baseFreeCashFlow: baseFcf,
          assumptions: a,
          netDebt: latest.netDebt,
          sharesOutstanding: shares,
          terminalEbitda: latest.ebitda,
        ).map((o) => o.fairValuePerShare);

    final base = DcfCalculator.fcff(
      baseFreeCashFlow: baseFcf,
      assumptions: assumptions,
      netDebt: latest.netDebt,
      sharesOutstanding: shares,
      terminalEbitda: latest.ebitda,
    );
    if (base.isErr) return null;

    final outcome = base.unwrap();
    if (outcome.fairValuePerShare <= 0) return null;

    _auditDcf(
      audit,
      outcome: outcome,
      assumptions: assumptions,
      baseFlow: baseFcf,
      flowSymbol: 'FCFF',
      discountSymbol: 'WACC',
    );
    _auditEquityBridge(
      audit,
      enterpriseValue: outcome.enterpriseValue,
      netDebt: latest.netDebt,
      shares: shares,
      perShare: outcome.fairValuePerShare,
    );

    if (outcome.terminalShare > 0.80) {
      local.add(
        '${(outcome.terminalShare * 100).toStringAsFixed(0)}% do valor vem da '
        'perpetuidade: o resultado depende mais da premissa de longo prazo do '
        'que da projeção explícita.',
      );
    }

    return _withScenarios(
      inputs: inputs,
      model: ValuationModel.dcfFcff,
      assumptions: assumptions,
      baseValue: outcome.fairValuePerShare,
      valuate: valuate,
      scenarioBuilder: scenarioBuilder,
      samples: samples,
      seed: seed,
      warnings: local,
    );
  }

  // -------------------------------------------------------------- 2. LPA --

  static ValuationResult? _tryEarnings(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    List<String> warnings,
    AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    int samples,
    int seed,
    double sharesPerQuote,
    AuditTransaction? audit,
  ) {
    final observedEps = _earningsPerQuotedUnit(latest, sharesPerQuote);
    if (observedEps == null || observedEps <= 0) return null;

    final local = [
      ...warnings,
      'Fluxo de caixa insuficiente para o modelo por FCFF; aplicado DCF '
          'simplificado sobre o lucro por ação.',
    ];

    // O lucro também sustenta uma perpetuidade, e sofre do mesmo problema:
    // um exercício com resultado extraordinário contamina o valor inteiro.
    final baseline = BaseFlowNormalizer.normalize([
      for (final s in published)
        if (_earningsPerQuotedUnit(s, sharesPerQuote) != null)
          _earningsPerQuotedUnit(s, sharesPerQuote)!,
    ]);
    final eps = baseline.value;
    _describeBase(baseline, 'lucro por papel', local);
    _auditBaseFlow(audit, baseline, 'lucro por papel');

    final growth = GrowthEstimator.fromHistory(
      published,
      (s) => _earningsPerQuotedUnit(s, sharesPerQuote),
      metricName: 'lucro por ação',
    );
    if (growth.clamped) local.add(growth.basis);
    _auditGrowth(audit, growth, 'lucro por ação');
    _auditPerpetualGrowth(
      audit,
      growth.rate,
      inputs.perpetualGrowthCap,
      GrowthEstimator.perpetual(
        explicitGrowth: growth.rate,
        economyGrowth: inputs.perpetualGrowthCap,
      ),
    );

    final assumptions = DcfAssumptions(
      projectionYears: inputs.projectionYears,
      growthRate: growth.rate,
      perpetualGrowth: GrowthEstimator.perpetual(
        explicitGrowth: growth.rate,
        economyGrowth: inputs.perpetualGrowthCap,
      ),
      // Sem estrutura de capital confiável, desconta-se ao custo do equity —
      // que é o par correto de um fluxo já atribuível ao acionista.
      discountRate: inputs.capm.costOfEquity,
      marginOfSafety: inputs.marginOfSafety,
    );

    Result<double> valuate(DcfAssumptions a) =>
        DcfCalculator.earningsPerShare(baseEps: eps, assumptions: a)
            .map((o) => o.fairValuePerShare);

    // O cenário base sai do resultado **completo**, não do atalho `valuate`:
    // a auditoria precisa dos fluxos projetados e do valor terminal, e obtê-los
    // com uma segunda chamada rodaria o mesmo DCF duas vezes.
    final base = DcfCalculator.earningsPerShare(
      baseEps: eps,
      assumptions: assumptions,
    );
    if (base.isErr || base.unwrap().fairValuePerShare <= 0) return null;

    final outcome = base.unwrap();
    _auditDcf(
      audit,
      outcome: outcome,
      assumptions: assumptions,
      baseFlow: eps,
      flowSymbol: 'LPA',
      discountSymbol: 'K_e',
      perShareAlready: true,
    );

    return _withScenarios(
      inputs: inputs,
      model: ValuationModel.dcfEarnings,
      assumptions: assumptions,
      baseValue: outcome.fairValuePerShare,
      valuate: valuate,
      scenarioBuilder: scenarioBuilder,
      samples: samples,
      seed: seed,
      warnings: local,
    );
  }

  // ----------------------------------------------------------- 3. Gordon --

  static ValuationResult? _tryGordon(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    List<String> warnings,
    AuditTransaction? audit,
  ) {
    final ttm = _trailingDividends(inputs.dividends, inputs.asOf);
    if (ttm <= 0) return null;

    final growth = GrowthEstimator.fromHistory(
      published,
      (s) => s.earningsPerShare,
      metricName: 'lucro por ação',
    );
    final perpetual = GrowthEstimator.perpetual(
      explicitGrowth: growth.rate,
      economyGrowth: inputs.perpetualGrowthCap,
    );
    _auditGrowth(audit, growth, 'lucro por ação');
    _auditPerpetualGrowth(
        audit, growth.rate, inputs.perpetualGrowthCap, perpetual);

    final result = DcfCalculator.gordonGrowth(
      lastDividendPerShare: ttm,
      costOfEquity: inputs.capm.costOfEquity,
      growthRate: perpetual,
    );
    if (result.isErr || result.unwrap() <= 0) return null;

    final ke = inputs.capm.costOfEquity;
    final projected = ttm * (1 + perpetual);
    audit?.step(
      formulaName: 'Modelo de Gordon sobre dividendos',
      latex: r'P_0 = \frac{D_0 \cdot (1 + g_\infty)}{K_e - g_\infty}',
      variables: {
        'D_0 (R\$)': _r(ttm),
        'g_∞ (% a.a.)': _r(perpetual * 100),
        'K_e (% a.a.)': _r(ke * 100),
      },
      steps: [
        'Passo 1: dividendo dos últimos 12 meses projetado um período → '
            'R\$ ${_r(ttm)} × (1 + ${_r(perpetual, 4)}) = R\$ ${_r(projected)}',
        'Passo 2: spread entre custo do capital próprio e crescimento '
            'perpétuo → ${_pct(ke)} − ${_pct(perpetual)} = ${_pct(ke - perpetual)}',
        'Passo 3: divisão do dividendo projetado pelo spread → '
            'R\$ ${_r(projected)} ÷ ${_r(ke - perpetual, 4)} = '
            'R\$ ${_r(result.unwrap())}',
      ],
      result: result.unwrap(),
      unit: r'R$ por papel',
    );

    return ValuationResult(
      ticker: inputs.ticker,
      asOf: inputs.asOf,
      model: ValuationModel.gordonGrowth,
      fairValue: Money.fromReais(result.unwrap()),
      marketPrice: Money.fromReais(inputs.marketPrice),
      discountRate: inputs.capm.costOfEquity,
      marginOfSafety: inputs.marginOfSafety,
      mode: ScenarioMode.discrete,
      warnings: [
        ...warnings,
        'Sem fluxo de caixa nem lucro por ação utilizáveis; aplicado o modelo '
            'de Gordon sobre dividendos, que ignora crescimento não distribuído.',
      ],
    );
  }

  // -------------------------------------------------------- 4. Múltiplos --

  static ValuationResult? _tryMultiples(
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    List<String> warnings,
    double sharesPerQuote,
    AuditTransaction? audit,
  ) {
    final ebitda = latest.ebitda;
    final multiple = latest.enterpriseToEbitda;
    final rawShares = latest.sharesOutstanding;
    final shares = rawShares == null ? null : rawShares / sharesPerQuote;

    if (ebitda != null && ebitda > 0 && multiple != null && multiple > 0 &&
        shares != null && shares > 0) {
      final equity = ebitda * multiple - latest.netDebt;
      final perShare = equity / shares;
      if (perShare > 0) {
        audit?.step(
          formulaName: 'Múltiplo EV/EBITDA',
          latex: r'P_0 = \frac{EBITDA \cdot m - D_{liq}}{N}',
          variables: {
            'EBITDA (R\$)': _r(ebitda),
            'm (×)': _r(multiple),
            'D_liq (R\$)': _r(latest.netDebt),
            'N (papéis)': _r(shares, 0),
          },
          steps: [
            'Passo 1: valor da firma pelo múltiplo → R\$ ${_r(ebitda)} × '
                '${_r(multiple)} = R\$ ${_r(ebitda * multiple)}',
            'Passo 2: desconto da dívida líquida → R\$ ${_r(ebitda * multiple)} '
                '− R\$ ${_r(latest.netDebt)} = R\$ ${_r(equity)}',
            'Passo 3: divisão pelo número de papéis → R\$ ${_r(equity)} ÷ '
                '${_r(shares, 0)} = R\$ ${_r(perShare)}',
          ],
          result: perShare,
          unit: r'R$ por papel',
        );
        return ValuationResult(
          ticker: inputs.ticker,
          asOf: inputs.asOf,
          model: ValuationModel.multiples,
          fairValue: Money.fromReais(perShare),
          marketPrice: Money.fromReais(inputs.marketPrice),
          discountRate: inputs.capm.costOfEquity,
          marginOfSafety: inputs.marginOfSafety,
          warnings: [
            ...warnings,
            'Nenhum modelo de fluxo descontado foi aplicável; usado múltiplo '
                'EV/EBITDA de ${multiple.toStringAsFixed(1)}× . Trate o valor '
                'como referência grosseira, não como valor intrínseco.',
          ],
        );
      }
    }

    // O valor patrimonial publicado é por ação; a comparação é com o preço da
    // unit, então ele sobe pelo mesmo fator.
    final book = latest.bookValuePerShare == null
        ? null
        : latest.bookValuePerShare! * sharesPerQuote;
    if (book != null && book > 0) {
      audit?.step(
        formulaName: 'Valor patrimonial por papel',
        latex: r'P_0 = VPA \cdot u',
        variables: {
          'VPA (R\$)': _r(latest.bookValuePerShare ?? 0),
          'u (ações/unit)': _r(sharesPerQuote, 0),
        },
        steps: [
          'Passo único: valor patrimonial por ação convertido para a unidade '
              'negociada → R\$ ${_r(latest.bookValuePerShare ?? 0)} × '
              '${_r(sharesPerQuote, 0)} = R\$ ${_r(book)}',
        ],
        result: book,
        unit: r'R$ por papel',
      );
      return ValuationResult(
        ticker: inputs.ticker,
        asOf: inputs.asOf,
        model: ValuationModel.multiples,
        fairValue: Money.fromReais(book),
        marketPrice: Money.fromReais(inputs.marketPrice),
        discountRate: inputs.capm.costOfEquity,
        marginOfSafety: inputs.marginOfSafety,
        warnings: [
          ...warnings,
          'Dados insuficientes para qualquer modelo de fluxo; adotado o valor '
              'patrimonial por ação como piso contábil. Não é valor intrínseco.',
        ],
      );
    }

    return null;
  }

  // ------------------------------------------------------------ Auxiliares --

  /// Registra o que aconteceu com o exercício-base, quando houve o que contar.
  ///
  /// O usuário precisa saber que o número que sustenta a perpetuidade não é o
  /// do último balanço — e por quanto ele destoava.
  static void _describeBase(
    BaseFlow baseline,
    String metricName,
    List<String> warnings,
  ) {
    if (baseline.winsorized) {
      final factor = baseline.deviationFactor;
      warnings.add(
        'O $metricName do último exercício destoava da mediana de '
        '${baseline.periodsUsed} exercícios'
        '${factor == null ? '' : ' (${factor.toStringAsFixed(1)}× a mediana)'}'
        '; a base da perpetuidade foi aparada para a borda da banda de '
        'normalização. Sem isso, um exercício atípico multiplicaria o valor '
        'inteiro da empresa.',
      );
      return;
    }
    final median = baseline.median;
    if (median != null && median <= 0) {
      warnings.add(
        'A mediana de $metricName dos últimos ${baseline.periodsUsed} exercícios é '
        'não positiva: o exercício-base é exceção na amostra, e a perpetuidade '
        'construída sobre ele é frágil.',
      );
    }
  }

  /// Lucro por **unit negociada**.
  ///
  /// Derivado do lucro líquido, que é total e portanto livre da ambiguidade
  /// por-ação/por-unit da fonte; o campo publicado só entra quando o lucro
  /// total falta, e aí convertido pela razão da unit. Como efeito colateral,
  /// ativos cujo `earningsPerShare` vem zerado — KLBN11 e BBSE3, medidos em
  /// 21/08/2026 — passam a ter o modelo por lucro disponível.
  static double? _earningsPerQuotedUnit(
    FundamentalsSnapshot snapshot,
    double sharesPerQuote,
  ) {
    final netIncome = snapshot.netIncome;
    final shares = snapshot.sharesOutstanding;
    if (netIncome != null && shares != null && shares > 0) {
      return netIncome / (shares / sharesPerQuote);
    }
    final published = snapshot.earningsPerShare;
    return published == null ? null : published * sharesPerQuote;
  }

  /// Monta o WACC com o que houver; sem estrutura de capital, degenera no Ke.
  static double _wacc(
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    List<String> warnings,
    double sharesPerQuote,
    AuditTransaction? audit,
  ) {
    final debt = latest.totalDebt;
    final shares = latest.sharesOutstanding;
    final equity = latest.marketCap ??
        (shares != null ? shares / sharesPerQuote * inputs.marketPrice : null);
    final kd = latest.costOfDebt;
    final tax = latest.effectiveTaxRate;

    if (debt <= 0 || equity == null || equity <= 0 || kd == null) {
      warnings.add(
        'Estrutura de capital indisponível; desconto feito ao custo do capital '
        'próprio em vez do WACC.',
      );
      audit?.step(
        formulaName: 'Taxa de desconto — degeneração para o Ke',
        latex: r'r = K_e \quad (\text{sem estrutura de capital observável})',
        variables: {
          'D (R\$)': _r(debt),
          'E (R\$)': equity == null ? null : _r(equity),
          'K_d (% a.a.)': kd == null ? null : _r(kd * 100),
        },
        steps: const [
          'Passo único: dívida, valor de mercado ou custo da dívida ausentes; '
              'o WACC não é montável e o desconto adota o custo do capital '
              'próprio.',
        ],
        result: inputs.capm.costOfEquity * 100,
        unit: '% a.a.',
      );
      return inputs.capm.costOfEquity;
    }

    if (tax == null) {
      warnings.add(
        'Alíquota efetiva indisponível; WACC calculado sem benefício fiscal '
        'da dívida, o que o torna conservador.',
      );
    }

    final coc = CostOfCapital(
      capm: inputs.capm,
      costOfDebt: kd,
      taxRate: tax ?? 0.0,
      equityValue: equity,
      debtValue: debt,
    );

    if (coc.costOfDebtWasClamped) {
      warnings.add(
        'O custo da dívida implícito nos demonstrativos deu '
        '${_pct(kd)} a.a., fora da faixa defensável; usado '
        '${_pct(coc.effectiveCostOfDebt)} a.a., limitado entre a taxa livre '
        'de risco e ela mais ${_pct(CostOfCapital.maxCreditSpread)}.',
      );
    }
    if (coc.waccWasFloored) {
      warnings.add(
        'O WACC calculado (${_pct(coc.rawWacc)} a.a.) ficou abaixo da taxa '
        'livre de risco; adotada a própria taxa livre de risco '
        '(${_pct(inputs.capm.riskFreeRate)} a.a.) como piso do desconto.',
      );
    }

    _auditWacc(audit, coc);
    return coc.wacc;
  }

  static String _pct(double fraction) =>
      '${(fraction * 100).toStringAsFixed(1)}%';

  static double _trailingDividends(
    List<DividendEvent> events,
    DateTime asOf,
  ) {
    final floor = DateTime(asOf.year - 1, asOf.month, asOf.day);
    var total = 0.0;
    for (final event in events) {
      if (event.exDate.isAfter(floor) && !event.exDate.isAfter(asOf)) {
        total += event.amountPerShare;
      }
    }
    return total;
  }

  static ValuationResult _withScenarios({
    required ValuationInputs inputs,
    required ValuationModel model,
    required DcfAssumptions assumptions,
    required double baseValue,
    required Result<double> Function(DcfAssumptions) valuate,
    required AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    required int samples,
    required int seed,
    required List<String> warnings,
  }) {
    final source = (scenarioBuilder ?? DiscreteScenarios.around)(assumptions);
    final outcome = ScenarioEngine.run(
      source: source,
      valuate: valuate,
      samples: samples,
      seed: seed,
    );

    if (outcome.isErr) {
      return ValuationResult(
        ticker: inputs.ticker,
        asOf: inputs.asOf,
        model: model,
        fairValue: Money.fromReais(baseValue),
        marketPrice: Money.fromReais(inputs.marketPrice),
        discountRate: assumptions.discountRate,
        marginOfSafety: inputs.marginOfSafety,
        warnings: [
          ...warnings,
          'Cenários não puderam ser gerados; apresentado apenas o cenário base.',
        ],
      );
    }

    final scenarios = outcome.unwrap();
    final local = [...warnings];
    if (scenarios.discarded > 0 && scenarios.mode == ScenarioMode.monteCarlo) {
      final pct = scenarios.discarded / math.max(1, samples) * 100;
      if (pct > 5) {
        local.add(
          '${pct.toStringAsFixed(0)}% dos sorteios foram descartados por '
          'produzirem valor inválido; estreite as faixas de premissas.',
        );
      }
    }

    return ValuationResult(
      ticker: inputs.ticker,
      asOf: inputs.asOf,
      model: model,
      fairValue: Money.fromReais(baseValue),
      marketPrice: Money.fromReais(inputs.marketPrice),
      discountRate: assumptions.discountRate,
      marginOfSafety: inputs.marginOfSafety,
      mode: scenarios.mode,
      discreteScenarios: scenarios.discrete?.map(
        (band, value) => MapEntry(band, Money.fromReais(value)),
      ),
      distribution: scenarios.distribution,
      warnings: local,
    );
  }

  static String _fmt(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  // ------------------------------------------------------------ Auditoria --
  //
  // Tudo daqui para baixo é rastro, não cálculo: cada função recebe valores
  // **já computados** pelo caminho normal e apenas os descreve. Nenhuma linha
  // aqui recalcula nada, e é isso que garante que o que a auditoria mostra é o
  // que o resultado usa — uma segunda implementação da mesma fórmula, escrita
  // para exibição, divergiria da primeira no dia em que alguém mexesse em uma
  // e esquecesse a outra.
  //
  // Todas saem cedo quando não há transação aberta, de modo que o custo com a
  // auditoria desligada é uma comparação com `null`.

  /// Arredonda para o JSON: `num` em vez de `String` para o valor continuar
  /// sendo número no payload exportado.
  static num _r(double value, [int decimals = 2]) {
    if (!value.isFinite) return 0;
    if (decimals <= 0) return value.round();
    final factor = math.pow(10, decimals);
    return (value * factor).round() / factor;
  }

  static Map<String, dynamic> _inputPayload(ValuationInputs inputs) {
    // Os exercícios entram resumidos e limitados aos mais recentes: o payload
    // atravessa a fronteira entre abas do navegador, e dezesseis exercícios
    // com vinte campos cada só encheriam a tela sem informar mais.
    final recent = inputs.fundamentals.length <= 6
        ? inputs.fundamentals
        : inputs.fundamentals.sublist(inputs.fundamentals.length - 6);

    return {
      'ticker': inputs.ticker.value,
      'asOf': inputs.asOf.toIso8601String(),
      'marketPrice': _r(inputs.marketPrice),
      'capm': {
        'riskFreeRate': _r(inputs.capm.riskFreeRate, 6),
        'beta': _r(inputs.capm.beta, 4),
        'marketPremium': _r(inputs.capm.marketPremium, 6),
        'betaSource': inputs.capm.betaSource.name,
        'premiumSource': inputs.capm.premiumSource.name,
      },
      'marginOfSafety': _r(inputs.marginOfSafety, 4),
      'projectionYears': inputs.projectionYears,
      'perpetualGrowthCap': _r(inputs.perpetualGrowthCap, 6),
      'dividendEvents': inputs.dividends.length,
      'fundamentalsPeriods': inputs.fundamentals.length,
      'fundamentals': [
        for (final f in recent)
          {
            'fiscalPeriodEnd': f.fiscalPeriodEnd.toIso8601String(),
            'netIncome': f.netIncome == null ? null : _r(f.netIncome!),
            'ebitda': f.ebitda == null ? null : _r(f.ebitda!),
            'operatingCashFlow':
                f.operatingCashFlow == null ? null : _r(f.operatingCashFlow!),
            'freeCashFlow':
                f.freeCashFlow == null ? null : _r(f.freeCashFlow!),
            'sharesOutstanding':
                f.sharesOutstanding == null ? null : _r(f.sharesOutstanding!, 0),
            'marketCap': f.marketCap == null ? null : _r(f.marketCap!),
            'totalDebt': _r(f.totalDebt),
            'netDebt': _r(f.netDebt),
            'effectiveTaxRate': f.effectiveTaxRate == null
                ? null
                : _r(f.effectiveTaxRate!, 4),
            'enterpriseToEbitda': f.enterpriseToEbitda == null
                ? null
                : _r(f.enterpriseToEbitda!, 4),
            'bookValuePerShare': f.bookValuePerShare == null
                ? null
                : _r(f.bookValuePerShare!),
          },
      ],
    };
  }

  static Map<String, dynamic> _outputPayload(ValuationResult result) => {
        'status': 'ok',
        'ticker': result.ticker.value,
        'model': result.model.label,
        'fairValue': _r(result.fairValue.reais),
        'safetyPrice': _r(result.safetyPrice.reais),
        'marketPrice': _r(result.marketPrice.reais),
        'upside': _r(result.upside, 6),
        'discountRate': _r(result.discountRate, 6),
        'marginOfSafety': _r(result.marginOfSafety, 4),
        'isUndervalued': result.isUndervalued,
        'scenarioMode': result.mode.name,
        if (result.discreteScenarios != null)
          'discreteScenarios': {
            for (final e in result.discreteScenarios!.entries)
              e.key.name: _r(e.value.reais),
          },
        if (result.distribution != null && !result.distribution!.isEmpty)
          'distribution': {
            'samples': result.distribution!.sortedValues.length,
            'p5': _r(result.distribution!.p5),
            'median': _r(result.distribution!.median),
            'p95': _r(result.distribution!.p95),
            'mean': _r(result.distribution!.mean),
            'probabilityAboveMarket': _r(
              result.distribution!
                  .probabilityAbove(result.marketPrice.reais),
              4,
            ),
          },
        'warnings': result.warnings,
      };

  static void _auditUnitRatio(
    AuditTransaction? audit,
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    double sharesPerQuote,
  ) {
    if (audit == null) return;
    final shares = latest.sharesOutstanding;
    final cap = latest.marketCap;
    final raw = (shares != null && cap != null && cap > 0)
        ? shares * inputs.marketPrice / cap
        : null;

    audit.step(
      formulaName: 'Razão da unidade negociada',
      latex: r'u = \mathrm{round}\!\left(\frac{N_{ações} \cdot P_{mkt}}{VM}\right)',
      variables: {
        'N_ações': shares == null ? null : _r(shares, 0),
        'P_mkt (R\$)': _r(inputs.marketPrice),
        'VM (R\$)': cap == null ? null : _r(cap),
      },
      steps: [
        if (raw == null)
          'Passo único: quantidade de ações ou valor de mercado ausentes; '
              'adotada a convenção de ação comum (u = 1).'
        else ...[
          'Passo 1: razão medida → ${_r(shares!, 0)} × '
              '${_r(inputs.marketPrice)} ÷ ${_r(cap!)} = ${_r(raw, 4)}',
          'Passo 2: arredondamento e teste de plausibilidade (1 ≤ u ≤ '
              '${_r(maxSharesPerUnit, 0)}, desvio ≤ 0,12) → u = '
              '${_r(sharesPerQuote, 0)}',
        ],
      ],
      result: sharesPerQuote,
      unit: 'ações por papel negociado',
    );
  }

  static void _auditCapm(AuditTransaction? audit, CapmInputs capm) {
    if (audit == null) return;
    final risk = capm.beta * capm.marketPremium;
    audit.step(
      formulaName: 'Custo do capital próprio (CAPM)',
      latex: r'K_e = R_f + \beta \cdot (R_m - R_f)',
      variables: {
        'R_f (% a.a.)': _r(capm.riskFreeRate * 100),
        'beta': _r(capm.beta, 4),
        'R_m - R_f (% a.a.)': _r(capm.marketPremium * 100),
        'origem do beta': capm.betaSource.name,
      },
      steps: [
        'Passo 1: prêmio ajustado ao risco sistemático → ${_r(capm.beta, 4)} × '
            '${_pct(capm.marketPremium)} = ${_pct(risk)}',
        'Passo 2: soma à taxa livre de risco → ${_pct(capm.riskFreeRate)} + '
            '${_pct(risk)} = ${_pct(capm.costOfEquity)}',
      ],
      result: _r(capm.costOfEquity * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditWacc(AuditTransaction? audit, CostOfCapital coc) {
    if (audit == null) return;
    final kd = coc.effectiveCostOfDebt;
    final afterTax = kd * (1 - coc.taxRate);
    final equityLeg = coc.equityShare * coc.costOfEquity;
    final debtLeg = coc.debtShare * afterTax;

    audit.step(
      formulaName: 'Custo médio ponderado de capital (WACC)',
      latex: r'WACC = \frac{E}{E+D}\,K_e + \frac{D}{E+D}\,K_d\,(1 - t)',
      variables: {
        'E (R\$)': _r(coc.equityValue),
        'D (R\$)': _r(coc.debtValue),
        'K_e (% a.a.)': _r(coc.costOfEquity * 100),
        'K_d (% a.a.)': _r(kd * 100),
        't (%)': _r(coc.taxRate * 100),
      },
      steps: [
        'Passo 1: participação do capital próprio → ${_r(coc.equityValue)} ÷ '
            '${_r(coc.totalCapital)} = ${_r(coc.equityShare, 4)}',
        'Passo 2: participação do capital de terceiros → ${_r(coc.debtValue)} ÷ '
            '${_r(coc.totalCapital)} = ${_r(coc.debtShare, 4)}',
        if (coc.costOfDebtWasClamped)
          'Passo 3: custo da dívida observado (${_pct(coc.costOfDebt)}) fora da '
              'banda defensável; limitado a ${_pct(kd)}'
        else
          'Passo 3: custo da dívida observado dentro da banda → ${_pct(kd)}',
        'Passo 4: benefício fiscal da dívida → ${_pct(kd)} × (1 − '
            '${_r(coc.taxRate, 4)}) = ${_pct(afterTax)}',
        'Passo 5: soma ponderada → ${_r(coc.equityShare, 4)} × '
            '${_pct(coc.costOfEquity)} + ${_r(coc.debtShare, 4)} × '
            '${_pct(afterTax)} = ${_pct(equityLeg)} + ${_pct(debtLeg)} = '
            '${_pct(coc.rawWacc)}',
        if (coc.waccWasFloored)
          'Passo 6: WACC abaixo da taxa livre de risco; adotado o piso de '
              '${_pct(coc.capm.riskFreeRate)}'
        else
          'Passo 6: WACC acima da taxa livre de risco; nenhum piso aplicado',
      ],
      result: _r(coc.wacc * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditBaseFlow(
    AuditTransaction? audit,
    BaseFlow baseline,
    String metricName,
  ) {
    if (audit == null) return;
    final median = baseline.median;

    audit.step(
      formulaName: 'Normalização do fluxo-base ($metricName)',
      latex: r'F_0 = \min\big(\max(F_{obs},\, m(1-\tau)),\, m(1+\tau)\big)',
      variables: {
        'F_obs': _r(baseline.observed),
        'm (mediana)': median == null ? null : _r(median),
        'tau': BaseFlowNormalizer.defaultTolerance,
        'exercícios na amostra': baseline.periodsUsed,
      },
      steps: [
        if (median == null)
          'Passo único: amostra com ${baseline.periodsUsed} exercício(s), '
              'insuficiente para sustentar mediana; adotado o exercício '
              'observado sem tratamento.'
        else if (median <= 0)
          'Passo único: mediana não positiva (${_r(median)}); a winsorização '
              'não se aplica e o exercício observado é adotado como base.'
        else ...[
          'Passo 1: banda em torno da mediana → [${_r(median * (1 - BaseFlowNormalizer.defaultTolerance))}, '
              '${_r(median * (1 + BaseFlowNormalizer.defaultTolerance))}]',
          'Passo 2: exercício observado → ${_r(baseline.observed)}'
              '${baseline.deviationFactor == null ? '' : ' (${_r(baseline.deviationFactor!)}× a mediana)'}',
          baseline.winsorized
              ? 'Passo 3: fora da banda; aparado para ${_r(baseline.value)}'
              : 'Passo 3: dentro da banda; mantido em ${_r(baseline.value)}',
        ],
      ],
      result: baseline.value,
      unit: r'R$',
    );
  }

  static void _auditGrowth(
    AuditTransaction? audit,
    GrowthEstimate growth,
    String metricName,
  ) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Crescimento explícito por regressão log-linear ($metricName)',
      latex: r'\ln(v_t) = a + b\,t \;\Rightarrow\; g = e^{b} - 1',
      variables: {
        'exercícios (n)': growth.periodsUsed,
        'b (inclinação)': growth.slope == null ? null : _r(growth.slope!, 6),
        'g bruto (% a.a.)': growth.rawRate == null ? null : _r(growth.rawRate! * 100),
        'piso (% a.a.)': _r(GrowthEstimator.floorRate * 100),
        'teto (% a.a.)': _r(GrowthEstimator.ceilingRate * 100),
      },
      steps: [
        if (growth.slope == null)
          'Passo único: ${growth.basis}.'
        else ...[
          'Passo 1: regressão de ln($metricName) contra o ano sobre '
              '${growth.periodsUsed} exercícios → b = ${_r(growth.slope!, 6)}',
          'Passo 2: conversão da inclinação em taxa anual → e^'
              '${_r(growth.slope!, 6)} − 1 = ${_pct(growth.rawRate ?? growth.rate)}',
          growth.clamped
              ? 'Passo 3: fora da banda de sanidade '
                  '[${_pct(GrowthEstimator.floorRate)}, ${_pct(GrowthEstimator.ceilingRate)}]; '
                  'limitado a ${_pct(growth.rate)}'
              : 'Passo 3: dentro da banda de sanidade; mantido em '
                  '${_pct(growth.rate)}',
        ],
      ],
      result: _r(growth.rate * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditPerpetualGrowth(
    AuditTransaction? audit,
    double explicitGrowth,
    double economyGrowth,
    double perpetual,
  ) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Crescimento na perpetuidade',
      latex: r'g_\infty = \mathrm{clamp}\big(\min(g,\, g_{eco}),\, 0,\, g_{eco}\big)',
      variables: {
        'g (% a.a.)': _r(explicitGrowth * 100),
        'g_eco (% a.a.)': _r(economyGrowth * 100),
      },
      steps: [
        'Passo 1: menor entre o crescimento explícito e o da economia → '
            'min(${_pct(explicitGrowth)}, ${_pct(economyGrowth)}) = '
            '${_pct(explicitGrowth < economyGrowth ? explicitGrowth : economyGrowth)}',
        'Passo 2: confinado a [0, ${_pct(economyGrowth)}] — uma empresa não '
            'cresce acima do PIB para sempre → ${_pct(perpetual)}',
      ],
      result: _r(perpetual * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditDcf(
    AuditTransaction? audit, {
    required DcfOutcome outcome,
    required DcfAssumptions assumptions,
    required double baseFlow,
    required String flowSymbol,
    required String discountSymbol,
    bool perShareAlready = false,
  }) {
    if (audit == null) return;
    final r = assumptions.discountRate;
    final g = assumptions.growthRate;
    final n = outcome.projectedFlows.length;
    final sumPv = outcome.enterpriseValue - outcome.discountedTerminalValue;

    audit.step(
      formulaName: 'Projeção e desconto do período explícito ($flowSymbol)',
      latex: r'VP_{explícito} = \sum_{t=1}^{N} \frac{F_0\,(1+g)^{t}}{(1+r)^{t}}',
      variables: {
        'F_0': _r(baseFlow),
        'g (% a.a.)': _r(g * 100),
        'r = $discountSymbol (% a.a.)': _r(r * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps: [
        for (var t = 1; t <= n; t++)
          'Passo $t: ano $t → fluxo ${_r(outcome.projectedFlows[t - 1])} '
              '(= ${_r(baseFlow)} × ${_r(math.pow(1 + g, t).toDouble(), 6)}); '
              'descontado por (1 + ${_r(r, 4)})^$t = '
              '${_r(math.pow(1 + r, t).toDouble(), 6)} → valor presente '
              '${_r(outcome.discountedFlows[t - 1])}',
        'Passo ${n + 1}: soma dos valores presentes do período explícito → '
            '${_r(sumPv)}',
      ],
      result: sumPv,
      unit: perShareAlready ? r'R$ por papel' : r'R$',
    );

    audit.step(
      formulaName: 'Valor terminal (perpetuidade de Gordon)',
      latex: r'VT = \frac{F_N\,(1 + g_\infty)}{r - g_\infty}'
          r'\quad;\quad VP(VT) = \frac{VT}{(1+r)^{N}}',
      variables: {
        'F_N': n == 0 ? null : _r(outcome.projectedFlows[n - 1]),
        'g_∞ (% a.a.)': _r(assumptions.perpetualGrowth * 100),
        'r (% a.a.)': _r(r * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps: [
        'Passo 1: spread da perpetuidade → ${_pct(r)} − '
            '${_pct(assumptions.perpetualGrowth)} = '
            '${_pct(r - assumptions.perpetualGrowth)}'
            '${(r - assumptions.perpetualGrowth) < DcfCalculator.minimumSpread ? ' (abaixo do mínimo de ${_pct(DcfCalculator.minimumSpread)}; adotado o mínimo)' : ''}',
        'Passo 2: valor terminal → ${_r(outcome.terminalValue)}',
        'Passo 3: trazido a valor presente por (1 + ${_r(r, 4)})^'
            '${assumptions.projectionYears} → '
            '${_r(outcome.discountedTerminalValue)}',
        'Passo 4: participação do valor terminal no total → '
            '${_pct(outcome.terminalShare)}',
      ],
      result: outcome.discountedTerminalValue,
      unit: perShareAlready ? r'R$ por papel' : r'R$',
    );

    if (perShareAlready) {
      audit.step(
        formulaName: 'Preço justo por papel (DCF sobre o lucro)',
        latex: r'P_0 = VP_{explícito} + VP(VT)',
        variables: {
          'VP_explícito (R\$)': _r(sumPv),
          'VP(VT) (R\$)': _r(outcome.discountedTerminalValue),
        },
        steps: [
          'Passo único: soma das duas parcelas → ${_r(sumPv)} + '
              '${_r(outcome.discountedTerminalValue)} = '
              '${_r(outcome.fairValuePerShare)}',
        ],
        result: outcome.fairValuePerShare,
        unit: r'R$ por papel',
      );
    }
  }

  static void _auditEquityBridge(
    AuditTransaction? audit, {
    required double enterpriseValue,
    required double netDebt,
    required double shares,
    required double perShare,
  }) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Ponte do valor da firma ao preço justo por papel',
      latex: r'P_0 = \frac{EV - D_{liq}}{N_{papéis}}',
      variables: {
        'EV (R\$)': _r(enterpriseValue),
        'D_liq (R\$)': _r(netDebt),
        'N_papéis': _r(shares, 0),
      },
      steps: [
        'Passo 1: valor da firma → ${_r(enterpriseValue)}',
        'Passo 2: desconto da dívida líquida → ${_r(enterpriseValue)} − '
            '${_r(netDebt)} = ${_r(enterpriseValue - netDebt)}',
        'Passo 3: divisão pelo número de papéis negociados → '
            '${_r(enterpriseValue - netDebt)} ÷ ${_r(shares, 0)} = '
            '${_r(perShare)}',
      ],
      result: perShare,
      unit: r'R$ por papel',
    );
  }

  static void _auditVerdict(AuditTransaction? audit, ValuationResult result) {
    if (audit == null) return;
    final fair = result.fairValue.reais;
    final market = result.marketPrice.reais;

    audit.step(
      formulaName: 'Margem de segurança e potencial de valorização',
      latex: r'P_{seg} = P_0\,(1 - s) \quad;\quad '
          r'upside = \frac{P_0 - P_{mkt}}{P_{mkt}}',
      variables: {
        'P_0 (R\$)': _r(fair),
        's (%)': _r(result.marginOfSafety * 100),
        'P_mkt (R\$)': _r(market),
      },
      steps: [
        'Passo 1: preço justo com margem de segurança → ${_r(fair)} × (1 − '
            '${_r(result.marginOfSafety, 4)}) = ${_r(result.safetyPrice.reais)}',
        'Passo 2: potencial de valorização total → (${_r(fair)} − '
            '${_r(market)}) ÷ ${_r(market)} = ${_pct(result.upside)}',
        'Passo 3: veredito → o preço de mercado '
            '${result.isUndervalued ? 'está abaixo' : 'não está abaixo'} do '
            'preço com margem de segurança',
      ],
      result: _r(result.upside * 100).toDouble(),
      unit: '% (total, sem prazo)',
    );
  }
}
