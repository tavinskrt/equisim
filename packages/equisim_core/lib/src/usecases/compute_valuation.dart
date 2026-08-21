import 'dart:math' as math;

import '../entities/dividend_event.dart';
import '../entities/fundamentals.dart';
import '../entities/valuation.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
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

  const ValuationInputs({
    required this.ticker,
    required this.asOf,
    required this.fundamentals,
    required this.dividends,
    required this.marketPrice,
    required this.capm,
    this.marginOfSafety = 0.0,
    this.projectionYears = 5,
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
    if (inputs.marketPrice <= 0) {
      return const Err(InvalidInput('Preço de mercado indisponível.'));
    }

    final view = PointInTimeView(inputs.asOf);
    final published = view.published(inputs.fundamentals);

    if (published.isEmpty) {
      return Err(InsufficientData(
        'Nenhum exercício de ${inputs.ticker.value} havia sido divulgado em '
        '${_fmt(inputs.asOf)} (defasagem de ${view.publicationLag.inDays} dias).',
        subject: inputs.ticker.value,
      ));
    }

    final latest = published.last;
    final warnings = <String>[];

    if (latest.fiscalPeriodEnd.year < inputs.asOf.year - 2) {
      warnings.add(
        'O exercício mais recente já divulgado é de ${latest.fiscalPeriodEnd.year}; '
        'a avaliação pode estar desatualizada.',
      );
    }

    for (final attempt in [
      () => _tryFcff(inputs, published, latest, warnings, scenarioBuilder,
          monteCarloSamples, seed),
      () => _tryEarnings(inputs, published, latest, warnings, scenarioBuilder,
          monteCarloSamples, seed),
      () => _tryGordon(inputs, published, warnings),
      () => _tryMultiples(inputs, latest, warnings),
    ]) {
      final result = attempt();
      if (result != null) return Ok(result);
    }

    return Err(InsufficientData(
      'Nenhum modelo de avaliação é aplicável a ${inputs.ticker.value} com os '
      'dados disponíveis.',
      subject: inputs.ticker.value,
    ));
  }

  // ------------------------------------------------------------- 1. FCFF --

  static ValuationResult? _tryFcff(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    List<String> warnings,
    AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    int samples,
    int seed,
  ) {
    final baseFcf = latest.freeCashFlow ?? latest.operatingCashFlow;
    final shares = latest.sharesOutstanding;
    if (baseFcf == null || baseFcf <= 0 || shares == null || shares <= 0) {
      return null;
    }

    final local = [...warnings];
    if (latest.freeCashFlow == null) {
      local.add(
        'Fluxo de caixa livre ausente; usado o fluxo operacional como base.',
      );
    }

    final growth = GrowthEstimator.fromHistory(
      published,
      (s) => s.freeCashFlow ?? s.operatingCashFlow,
      metricName: 'fluxo de caixa livre',
    );
    if (growth.clamped) local.add(growth.basis);

    final wacc = _wacc(inputs, latest, local);
    final perpetual = GrowthEstimator.perpetual(explicitGrowth: growth.rate);

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
  ) {
    final eps = latest.earningsPerShare;
    if (eps == null || eps <= 0) return null;

    final local = [
      ...warnings,
      'Fluxo de caixa insuficiente para o modelo por FCFF; aplicado DCF '
          'simplificado sobre o lucro por ação.',
    ];

    final growth = GrowthEstimator.fromHistory(
      published,
      (s) => s.earningsPerShare,
      metricName: 'lucro por ação',
    );
    if (growth.clamped) local.add(growth.basis);

    final assumptions = DcfAssumptions(
      projectionYears: inputs.projectionYears,
      growthRate: growth.rate,
      perpetualGrowth: GrowthEstimator.perpetual(explicitGrowth: growth.rate),
      // Sem estrutura de capital confiável, desconta-se ao custo do equity —
      // que é o par correto de um fluxo já atribuível ao acionista.
      discountRate: inputs.capm.costOfEquity,
      marginOfSafety: inputs.marginOfSafety,
    );

    Result<double> valuate(DcfAssumptions a) =>
        DcfCalculator.earningsPerShare(baseEps: eps, assumptions: a)
            .map((o) => o.fairValuePerShare);

    final base = valuate(assumptions);
    if (base.isErr || base.unwrap() <= 0) return null;

    return _withScenarios(
      inputs: inputs,
      model: ValuationModel.dcfEarnings,
      assumptions: assumptions,
      baseValue: base.unwrap(),
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
  ) {
    final ttm = _trailingDividends(inputs.dividends, inputs.asOf);
    if (ttm <= 0) return null;

    final growth = GrowthEstimator.fromHistory(
      published,
      (s) => s.earningsPerShare,
      metricName: 'lucro por ação',
    );
    final perpetual =
        GrowthEstimator.perpetual(explicitGrowth: growth.rate);

    final result = DcfCalculator.gordonGrowth(
      lastDividendPerShare: ttm,
      costOfEquity: inputs.capm.costOfEquity,
      growthRate: perpetual,
    );
    if (result.isErr || result.unwrap() <= 0) return null;

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
  ) {
    final ebitda = latest.ebitda;
    final multiple = latest.enterpriseToEbitda;
    final shares = latest.sharesOutstanding;

    if (ebitda != null && ebitda > 0 && multiple != null && multiple > 0 &&
        shares != null && shares > 0) {
      final equity = ebitda * multiple - latest.netDebt;
      final perShare = equity / shares;
      if (perShare > 0) {
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

    final book = latest.bookValuePerShare;
    if (book != null && book > 0) {
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

  /// Monta o WACC com o que houver; sem estrutura de capital, degenera no Ke.
  static double _wacc(
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    List<String> warnings,
  ) {
    final debt = latest.totalDebt;
    final equity = latest.marketCap ??
        (latest.sharesOutstanding != null
            ? latest.sharesOutstanding! * inputs.marketPrice
            : null);
    final kd = latest.costOfDebt;
    final tax = latest.effectiveTaxRate;

    if (debt <= 0 || equity == null || equity <= 0 || kd == null) {
      warnings.add(
        'Estrutura de capital indisponível; desconto feito ao custo do capital '
        'próprio em vez do WACC.',
      );
      return inputs.capm.costOfEquity;
    }

    if (tax == null) {
      warnings.add(
        'Alíquota efetiva indisponível; WACC calculado sem benefício fiscal '
        'da dívida, o que o torna conservador.',
      );
    }

    return CostOfCapital(
      capm: inputs.capm,
      costOfDebt: kd,
      taxRate: tax ?? 0.0,
      equityValue: equity,
      debtValue: debt,
    ).wacc;
  }

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
}
