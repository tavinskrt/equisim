import 'dart:math' as math;

import '../audit/audit_recorder.dart';
import '../audit/calculation_trace.dart';
import '../entities/fundamentals.dart';
import '../entities/price_series.dart';
import '../entities/valuation.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
import '../services/valuation/capital_base.dart';
import '../services/valuation/cost_of_capital.dart';
import '../services/valuation/cyclical_sectors.dart';
import '../services/valuation/dcf.dart';
import '../services/valuation/eligibility.dart';
import '../services/valuation/growth_estimator.dart';
import '../services/valuation/growth_guards.dart';
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
  /// Ativo a avaliar.
  final Ticker ticker;

  /// Data de referência. Define o corte *point-in-time* dos fundamentos.
  final DateTime asOf;

  /// Série completa de exercícios, **sem** filtro de publicação — o filtro é
  /// aplicado internamente por `PointInTimeView`.
  final List<FundamentalsSnapshot> fundamentals;

  /// Cotação na data de referência, em reais **por unidade negociada**.
  final double marketPrice;

  /// Insumos do CAPM já resolvidos, incluindo a origem do beta.
  final CapmInputs capm;

  /// Margem de segurança aplicada ao preço justo, em fração.
  final double marginOfSafety;

  /// Anos de projeção explícita.
  final int projectionYears;

  /// Chave do setor na taxonomia da fonte, em minúsculas.
  ///
  /// Entra na Porta 1, que exige `"finance"` **e** dívida bruta nula. `null`
  /// quando o perfil não pôde ser carregado, caso em que a Porta 1 não dispara e
  /// o roteamento cai na Porta 3 — degradação segura, porque o teste de fluxo
  /// sozinho já barra instituição financeira: BBAS3 e BPAC11 não têm NOPAT em
  /// exercício nenhum.
  final String? sectorKey;

  /// Subsetor na taxonomia da fonte, como publicado — com acento e pontuação.
  ///
  /// Entra na precedência da Guarda 3 sobre a Guarda 1, e existe porque a chave
  /// setorial sozinha não separa o que precisa ser separado: `energia` reúne
  /// exploração de petróleo, que é commodity pura, e 28 elétricas, que são
  /// concessão regulada. Ver [CyclicalSectors].
  ///
  /// `null` quando o perfil não pôde ser carregado, caso em que a precedência
  /// recai apenas sobre a chave setorial.
  final String? industry;

  /// Série de cotações da janela, para o corte de liquidez da Porta 0.
  ///
  /// Opcional: sem ela — ou sem volume nela — o teste de liquidez é **omitido**,
  /// não reprovado. Recusar por dado ausente confundiria falta de informação com
  /// falta de liquidez.
  final PriceSeries? prices;

  /// `true` quando o ativo consta da lista externa de recuperação judicial.
  ///
  /// Vem de fora porque a fonte não publica a informação: `isActive` marca
  /// negociabilidade, não continuidade, e os 786 tickers do universo vêm todos
  /// com ele verdadeiro.
  final bool isDistressed;

  /// Inflação anual observada, em fração.
  ///
  /// É a âncora *top-down* da Saída 2, adotada quando o crescimento fundamental
  /// não é identificável e a retenção observada a financia.
  final double inflation;

  /// Taxa livre de risco **estrutural**, em fração — o destino do decaimento.
  ///
  /// O CAPM usa a taxa corrente, que é o custo de oportunidade de hoje. Mas o
  /// modelo não tem curva de juros, e descontar dez anos e uma perpetuidade por
  /// um indexador de um dia casa duração infinita com duração zero: no topo do
  /// ciclo monetário isso esmaga todo valor terminal, e no vale o infla.
  ///
  /// Esta é a média decenal do CDI, medida — não chumbada. Omiti-la faz cair
  /// para a taxa corrente, que reproduz o comportamento anterior.
  final double? declaredTerminalRiskFreeRate;

  /// Taxa livre de risco estrutural, com o padrão já resolvido.
  double get terminalRiskFreeRate =>
      declaredTerminalRiskFreeRate ?? capm.riskFreeRate;

  /// Teto **nominal** do crescimento na perpetuidade, em fração.
  ///
  /// Precisa estar na mesma unidade do desconto, que é nominal por vir do CDI.
  /// O padrão repete o crescimento real de longo prazo apenas para não quebrar
  /// quem constrói os insumos à mão; a aplicação passa
  /// `MarketAnchors.nominalEconomyGrowth`, derivado do IPCA observado.
  final double perpetualGrowthCap;

  /// Agrupa os insumos. Não busca nada — quem busca é
  /// [PrepareValuationInputs], e a separação é o que mantém a cascata pura.
  const ValuationInputs({
    required this.ticker,
    required this.asOf,
    required this.fundamentals,
    required this.marketPrice,
    required this.capm,
    this.marginOfSafety = 0.0,
    this.projectionYears = 10,
    this.perpetualGrowthCap = 0.0652,
    this.sectorKey,
    this.industry,
    this.inflation = 0.05,
    this.declaredTerminalRiskFreeRate,
    this.prices,
    this.isDistressed = false,
  });
}

/// De onde veio a contagem de papéis da ponte.
enum QuotedSharesSource {
  /// Implícita no valor de mercado: `VM ÷ preço`. É a que forma a cotação, e é
  /// a adotada sempre que as duas contagens publicadas concordam.
  market('implícita no valor de mercado'),

  /// Conciliada pelas demonstrações, adotada quando é a **maior** das duas e as
  /// duas divergem além de uma ação societária plausível.
  reconciled('conciliada pelas demonstrações'),

  /// Única disponível: o valor de mercado não pôde ser usado.
  onlyAvailable('única contagem disponível');

  final String label;
  const QuotedSharesSource(this.label);
}

/// Contagem de papéis da ponte, com a origem e as duas candidatas.
class QuotedShares {
  /// Papéis na unidade negociada. Sempre positiva.
  final double count;

  /// De onde ela veio.
  final QuotedSharesSource source;

  /// Contagem implícita no valor de mercado, na unidade negociada. `null`
  /// quando o valor de mercado não está publicado.
  final double? fromMarketCap;

  /// Contagem conciliada pelas demonstrações, na unidade negociada. `null`
  /// quando nenhuma das duas contagens societárias é utilizável.
  final double? fromStatements;

  /// Razão de unidade medida, para o aviso de *unit*.
  final double sharesPerQuote;

  const QuotedShares({
    required this.count,
    required this.source,
    required this.fromMarketCap,
    required this.fromStatements,
    required this.sharesPerQuote,
  });

  /// `true` quando as duas candidatas divergem além da banda de conciliação.
  bool get diverge {
    final a = fromMarketCap, b = fromStatements;
    if (a == null || b == null) return false;
    final d = a >= b ? a / b : b / a;
    return d > FundamentalsSnapshot.reconciliationBand;
  }

  /// Razão entre a maior e a menor candidata, sempre `>= 1`. `null` quando só
  /// uma existe.
  double? get divergence {
    final a = fromMarketCap, b = fromStatements;
    if (a == null || b == null) return null;
    return a >= b ? a / b : b / a;
  }
}

/// Roteia o ativo por portas e aplica a via correspondente.
///
/// A arquitetura é a da decisão 25, e substituiu a cascata de três degraus que
/// caía de modelo em modelo por falta de dado:
///
/// - **Porta 0** — elegibilidade: liquidez, histórico e continuidade. Ativo que
///   não passa não é avaliado, e a recusa é declarada.
/// - **Porta 1** — instituição financeira sai da via da firma, porque depósito e
///   captação são insumo do negócio, não financiamento.
/// - **Porta 3** — o lucro operacional recorrente decide se o fluxo da firma
///   sustenta uma perpetuidade.
/// - **Porta 2** — duas saídas independentes: uma normaliza a base pela
///   convergência ao ciclo, outra decide de onde vem a taxa de crescimento.
///
/// Depois do desconto há ainda uma **pós-condição**: quando a dívida líquida
/// quase consome o valor da firma, o preço por papel é resíduo de subtração, e a
/// avaliação migra para a via do acionista — declarando a migração.
///
/// A via aplicada **vai no resultado**, junto dos avisos. Cair silenciosamente
/// para um modelo inferior e rotular o número como "preço justo" esconderia do
/// usuário a qualidade real da estimativa.
abstract final class ValuationCascade {
  /// Avalia usando o melhor modelo possível.
  ///
  /// - [inputs]: insumos já resolvidos.
  /// - [scenarioBuilder]: constrói a fonte de cenários a partir das premissas
  ///   centrais. Sem ele, os modelos de fluxo usam três cenários discretos.
  /// - [monteCarloSamples]: sorteios quando a fonte é estocástica. Padrão
  ///   `10000`.
  /// - [seed]: semente do gerador. Padrão `42`, fixo por reprodutibilidade.
  ///
  /// Devolve [InvalidInput] sem preço de mercado; [InsufficientData] quando
  /// nenhum exercício havia sido publicado na data de referência, ou quando
  /// **nenhum** dos três modelos se aplica.
  ///
  /// **Síncrono e puro:** não toca rede nem relógio, e a mesma entrada produz
  /// sempre a mesma saída. É o que permite executá-la dentro de uma isolate e
  /// testar a decisão de modelo sem dependência externa.
  ///
  /// A instrumentação de auditoria abre transação **antes** da primeira
  /// validação: um ativo recusado é tão auditável quanto um avaliado.
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

    // Porta 0 — elegibilidade. Vem antes de qualquer decisão de modelo: um
    // ativo ilíquido, de histórico curto ou sem continuidade não é caso de
    // escolher via, é caso de não avaliar.
    final elegibilidade = EligibilityGate.assess(
      snapshots: published,
      prices: inputs.prices,
      isDistressed: inputs.isDistressed,
    );
    if (!elegibilidade.isEligible) {
      final message = elegibilidade.message!;
      audit?.abort(message, extra: {
        'motivos': [for (final r in elegibilidade.reasons) r.name],
        'exerciciosPublicados': elegibilidade.publishedPeriods,
        if (elegibilidade.averageDailyTradedValue != null)
          'volumeFinanceiroMediano':
              _r(elegibilidade.averageDailyTradedValue!, 0),
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

    final divisor = quotedShares(
      latest: latest,
      marketPrice: inputs.marketPrice,
      sharesPerQuote: sharesPerQuote,
      published: published,
    );
    if (divisor == null) {
      const message = 'Nenhuma contagem de papéis utilizável: a ponte por papel '
          'não pode ser feita.';
      audit?.abort(message);
      return const Err(InsufficientData(message));
    }
    _auditQuotedShares(audit, latest, inputs.marketPrice, divisor);

    if (!shareBaseIsConsistent(published, latest)) {
      warnings.add(
        'A contagem de ações do exercício de ${latest.fiscalPeriodEnd.year} '
        '(${_r(latest.sharesOutstandingAsOf ?? 0, 0)}) destoa por mais de '
        '${CapitalSeries.neighbourFactor.toStringAsFixed(0)}x da dos exercícios '
        'vizinhos, o que é falha de escala da fonte e não ação societária. Ela '
        'foi descartada do divisor da ponte por papel, que passou a usar a '
        'contagem implícita no valor de mercado. As bases contábeis não são '
        'afetadas: nelas o erro se cancela contra o valor por ação publicado na '
        'mesma escala.',
      );
    }

    if (divisor.diverge) {
      warnings.add(
        'As contagens de papéis da fonte divergem por '
        '${divisor.divergence!.toStringAsFixed(2)}x: '
        '${_r(divisor.fromMarketCap!, 0)} implícitas no valor de mercado '
        'contra ${_r(divisor.fromStatements!, 0)} conciliadas pelas '
        'demonstrações. Nada no dado arbitra qual descreve a base societária '
        'de hoje, e foi adotada a **maior** — ${divisor.source.label} —, '
        'porque divisor pequeno demais infla o preço justo e produz sinal '
        'falso de desconto. O preço justo é, nesta medida, conservador.',
      );
    } else if (latest.sharesDisagree) {
      warnings.add(
        'As duas contagens de ações publicadas pela fonte discordam: '
        '${_r(latest.sharesOutstanding ?? 0, 0)} correntes contra '
        '${_r(latest.sharesOutstandingAsOf ?? 0, 0)} do exercício. As bases '
        'contábeis usam a do exercício, que reconstrói o patrimônio publicado; '
        'a ponte por papel usa a implícita no valor de mercado, que é a que '
        'forma o preço comparado.',
      );
    }

    final lane = _route(inputs, published, latest, warnings, audit);
    final refusals = <String>[];
    final result = _evaluateLane(inputs, published, latest, lane, warnings,
        scenarioBuilder, monteCarloSamples, seed, divisor, audit,
        refusals: refusals);
    if (result != null) {
      _auditVerdict(audit, result);
      audit?.complete(_outputPayload(result));
      return Ok(result);
    }

    final message = refusals.isNotEmpty
        ? refusals.first
        : 'Os dados de ${inputs.ticker.value} não sustentam nenhuma das duas '
            'vias de avaliação.';
    audit?.abort(message, extra: {
      'viaTentada': lane.label,
      'exerciciosPublicados': published.length,
    });
    return Err(InsufficientData(message, subject: inputs.ticker.value));
  }

  // ------------------------------------------------ Unidade de negociação --

  /// Quantas ações compõem a **unit** negociada, ou 1 para a ação comum.
  ///
  /// Existe porque a fonte mistura duas convenções no mesmo ativo: as
  /// demonstrações e o `sharesOutstanding` vêm por **ação**, enquanto a
  /// cotação e o `marketCap` vêm por **unit**. Dividir um valor
  /// de firma pelo número de ações produz preço justo por ação, que era então
  /// comparado ao preço da unit — erro de 5× em SAPR11 e KLBN11 e de 3× em
  /// BPAC11 (medido em 21/08/2026).
  ///
  /// A razão é **medida, não tabelada**: `ações × preço ÷ valor de mercado`
  /// devolve 1,00 para ação comum e o número de ações da unit para as demais,
  /// sem depender de uma lista que envelhece a cada reorganização societária.
  /// Fora da faixa plausível ou longe de um inteiro, adota-se 1 — preferível
  /// a aplicar um fator inventado.
  ///
  /// - [sharesOutstanding]: papéis em circulação, por ação.
  /// - [marketCap]: valor de mercado publicado.
  /// - [marketPrice]: cotação da unidade negociada.
  ///
  /// Retorna a razão arredondada, sempre em `[1, maxSharesPerUnit]`. Devolve
  /// `1.0` — nunca `null`, nunca zero — para qualquer entrada ausente, não
  /// positiva, não finita, fora da faixa, ou a mais de 0,12 de um inteiro.
  /// O valor é seguro como divisor.
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

  /// A contagem de ações do exercício mais recente é coerente com a série?
  ///
  /// **Por que a pergunta existe.** A fonte publica a contagem do exercício e as
  /// métricas por ação na mesma base, de modo que um erro de escala nas duas se
  /// cancela em `VPA × N` e passa despercebido no patrimônio. Ele **não** se
  /// cancela no divisor da ponte por papel, que usa `N` sozinho.
  ///
  /// O caso medido é a EQTL3, cujo exercício de 2024 vem com **246.152** ações
  /// contra 1,50 bilhão em 2023 e 1,26 bilhão em 2025 — um fator de cinco mil.
  /// O VPA acompanha, em R$ 121.419,23, e o patrimônio sai correto em R$ 29,9
  /// bilhões; o lucro por ação sai em R$ 11.422,52. Hoje isso não muda número
  /// nenhum, porque o exercício de 2025 já é público. Numa análise datada entre
  /// as duas divulgações — e é o que a validação *point-in-time* faz —, aquele
  /// exercício seria o mais recente, e o preço justo por papel sairia cinco mil
  /// vezes errado.
  ///
  /// **O teste é de vizinhança, e o fator é o mesmo de [CapitalSeries].** Lá o
  /// raciocínio já está escrito: falha de fonte é de ordem de grandeza, salto
  /// societário real fica entre duas e nove vezes e **precisa passar**. A VIVT3
  /// dobrou a base em 2024 — 1,65 para 3,26 bilhões, com o VPA caindo de R$
  /// 42,13 para R$ 21,40 — e passa, que é o certo: foi ação societária, não
  /// erro.
  ///
  /// - [published]: exercícios publicados, em ordem cronológica. Lista vazia
  ///   **aprova**: sem série não há vizinhança contra a qual julgar, e ausência
  ///   de dado não é evidência de defeito.
  /// - [latest]: exercício cuja contagem se quer julgar.
  static bool shareBaseIsConsistent(
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
  ) {
    final alvo = latest.sharesOutstandingAsOf;
    if (alvo == null || alvo <= 0) return true;

    final vizinhos = <double>[];
    for (final s in published) {
      if (identical(s, latest)) continue;
      final n = s.sharesOutstandingAsOf;
      if (n != null && n > 0) vizinhos.add(n);
    }
    if (vizinhos.length < 2) return true;

    final recentes = vizinhos.length <= CapitalSeries.neighbourRadius
        ? vizinhos
        : vizinhos.sublist(vizinhos.length - CapitalSeries.neighbourRadius);
    recentes.sort();
    final m = recentes.length ~/ 2;
    final referencia = recentes.length.isOdd
        ? recentes[m]
        : (recentes[m - 1] + recentes[m]) / 2;
    if (referencia <= 0) return true;

    final razao = alvo >= referencia ? alvo / referencia : referencia / alvo;
    return razao <= CapitalSeries.neighbourFactor;
  }

  /// Teto de ações por unit. As units da B3 vão até 5 (1 ON + 4 PN).
  static const double maxSharesPerUnit = 10;

  /// Papéis na **unidade negociada** para a ponte por papel.
  ///
  /// **A ponte compara duas coisas que precisam estar na mesma escala:** o
  /// valor do capital próprio que o modelo apura, em reais absolutos, e a
  /// cotação de uma unidade negociada. O divisor correto é, por definição, a
  /// contagem de unidades que forma essa cotação — `VM ÷ P_mkt`. Adotá-la faz o
  /// potencial virar `E ÷ VM − 1`, e nenhuma contagem de ação sobra na conta:
  /// desdobramento, grupamento, *unit* e registro corrompido saem por
  /// construção.
  ///
  /// **A contagem do exercício continua certa onde sempre esteve.** Ela
  /// reconstrói o patrimônio publicado — `VPA × N_exercício = PL` em 4.461 de
  /// 4.462 exercícios do cache — e é ela que [CapitalSeries] usa para medir
  /// ROIC, Φ e crescimento. O que ela não descreve é a escala do preço de hoje:
  /// medido em 07/09/2026, o divisor saía errado por mais de 5% em **30 dos
  /// 120 avaliados**, com 2,65x na MOVI3 e 1,49x na B3SA3.
  ///
  /// **Quando as duas contagens divergem, a fonte não tem árbitro, e a escolha
  /// é por consequência.** Isso foi medido, não suposto:
  ///
  /// - `N = lucro ÷ LPA` é **tautológico** para esta pergunta. Os dois campos
  ///   vêm das mesmas demonstrações, então ele só pode confirmar a contagem do
  ///   exercício — e confirma, em todos os divergentes.
  /// - O valor de mercado da fonte é, quase sempre, `contagem corrente ×
  ///   preço`, e herda o defeito dessa contagem: o MILS3 chega com R$ 760 mil
  ///   de capitalização contra R$ 9,6 milhões de volume mediano por pregão.
  /// - O `enterpriseToEbitda` publicado seria independente, mas erra por mais
  ///   de 2x em 12% dos ativos cujas duas contagens **concordam** — o piso de
  ///   ruído dele — e chega a discordar entre classes da mesma empresa: SAPR4
  ///   acusa 3,01 e SAPR11, 1,47.
  /// - A série de preços não denuncia desdobramento: o `close` da fonte já vem
  ///   ajustado por ação societária, e não há salto nenhum em dez anos.
  ///
  /// Sem árbitro, decide o sentido do erro. **Divisor pequeno demais infla o
  /// preço justo** e produz sinal falso de "barato", que é o pior sentido
  /// possível — o mesmo argumento que a Porta 0 usa para o corte de liquidez.
  /// Divisor grande demais deprime o preço justo, e o erro que sobra é o
  /// conservador. Por isso, na divergência, **adota-se a maior das duas**, e a
  /// divergência é declarada no resultado.
  ///
  /// Dentro da banda de conciliação as duas concordam e vale a do mercado, que
  /// é a que zera a contagem da comparação.
  ///
  /// - [latest]: exercício mais recente publicado.
  /// - [marketPrice]: cotação da unidade negociada.
  /// - [sharesPerQuote]: razão de unidade, de [quotedUnitRatio]. Converte a
  ///   contagem por ação das demonstrações para a unidade negociada.
  ///
  /// Devolve `null` quando nenhuma das duas contagens é utilizável.
  static QuotedShares? quotedShares({
    required FundamentalsSnapshot latest,
    required double marketPrice,
    required double sharesPerQuote,
    List<FundamentalsSnapshot> published = const [],
  }) {
    final pelaFonte = latest.sharesFromMarketCap(marketPrice);
    final conciliada =
        shareBaseIsConsistent(published, latest) ? latest.reconciledShares : null;
    final peloBalanco = (conciliada != null && conciliada > 0)
        ? conciliada / sharesPerQuote
        : null;

    if (pelaFonte == null && peloBalanco == null) return null;
    if (pelaFonte == null) {
      return QuotedShares(
        count: peloBalanco!,
        source: QuotedSharesSource.onlyAvailable,
        fromMarketCap: null,
        fromStatements: peloBalanco,
        sharesPerQuote: sharesPerQuote,
      );
    }
    if (peloBalanco == null) {
      return QuotedShares(
        count: pelaFonte,
        source: QuotedSharesSource.onlyAvailable,
        fromMarketCap: pelaFonte,
        fromStatements: null,
        sharesPerQuote: sharesPerQuote,
      );
    }

    final candidata = QuotedShares(
      count: pelaFonte,
      source: QuotedSharesSource.market,
      fromMarketCap: pelaFonte,
      fromStatements: peloBalanco,
      sharesPerQuote: sharesPerQuote,
    );
    if (!candidata.diverge || pelaFonte >= peloBalanco) return candidata;

    return QuotedShares(
      count: peloBalanco,
      source: QuotedSharesSource.reconciled,
      fromMarketCap: pelaFonte,
      fromStatements: peloBalanco,
      sharesPerQuote: sharesPerQuote,
    );
  }

  // -------------------------------------------- Porta 1 e Porta 3: a via --

  /// Chave do setor financeiro na taxonomia do **perfil** da fonte.
  ///
  /// A fonte mantém duas taxonomias que não coincidem: o perfil devolve
  /// `servicos-financeiros`, em português, enquanto a listagem de tickers
  /// devolve `Finance`, em inglês. Comparar contra a errada faz a Porta 1 nunca
  /// disparar — defeito que a validação fora da amostra expôs, com o Banco ABC
  /// chegando à porta com `servicos-financeiros` e passando reto.
  static const String _financeSectorKey = 'servicos-financeiros';

  /// Decide de quem é o fluxo.
  ///
  /// **Porta 1** — instituição financeira sai da via da firma, **pelo setor**.
  ///
  /// A exigência de dívida bruta nula que acompanhava o setor foi removida em
  /// 07/09/2026, e o motivo é que a justificativa dela não valia na taxonomia
  /// que o código compara. Ela citava a RENT3 chegando classificada como
  /// `Finance` — mas isso é a taxonomia da **listagem**, e a porta compara
  /// contra a do **perfil**, onde a RENT3 e a MOVI3 vêm como `consumo-ciclico`.
  /// Conferido por execução sobre o cache de produção: os 28 ativos com
  /// `servicos-financeiros` no perfil são bancos, seguradoras, resseguradora,
  /// corretora, bolsa e serviços financeiros diversos — não há locadora nem
  /// nada de outra natureza a barrar.
  ///
  /// O que a exigência fazia, na prática, era barrar quem tem passivo oneroso —
  /// isto é, **a própria definição do negócio bancário**. Cinco dos 28 caíam
  /// por ela para a via da firma, e a B3SA3 é o caso de maior efeito: as
  /// debêntures viravam dívida líquida subtraída do valor da firma, o que não
  /// tem sentido econômico numa bolsa, onde captação e tesouraria são
  /// engrenagem operacional.
  ///
  /// **Porta 3** — o fluxo da firma precisa se sustentar. Mede sobre NOPAT, que
  /// é o fluxo de manutenção sob a aproximação `CapEx_manutenção ≈ D&A`, e não
  /// sobre o fluxo livre publicado: este reprova quem está em ciclo de
  /// investimento. A EGIE3 caía para a via do acionista por um exercício
  /// negativo depois de onze positivos em dezesseis.
  static ValuationLane _route(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    List<String> warnings,
    AuditTransaction? audit,
  ) {
    final porta1 = inputs.sectorKey == _financeSectorKey;

    final fluxoSustentado =
        porta1 ? false : GrowthGuards.firmFlowIsSustained(published);
    final lane = (porta1 || !fluxoSustentado)
        ? ValuationLane.shareholder
        : ValuationLane.firm;

    if (porta1) {
      warnings.add(
        'Instituição financeira: depósito, captação e passivo oneroso são '
        'insumo do negócio, não financiamento. A avaliação é do fluxo do '
        'acionista, descontada ao custo do capital próprio e sem ponte de '
        'dívida líquida — subtrair a captação do valor da firma trataria a '
        'matéria-prima do negócio como estrutura de capital.',
      );
    } else if (!fluxoSustentado) {
      warnings.add(
        'O lucro operacional não se sustenta na maioria dos exercícios; a '
        'avaliação passa para o fluxo do acionista.',
      );
    }

    audit?.step(
      formulaName: 'Roteamento por porta',
      latex: r'\text{via} = f(\text{setor},\, D_{bruta},\, \Pr[NOPAT > 0])',
      variables: {
        'setor': inputs.sectorKey ?? 'não informado',
        'dívida bruta (R\$)': _r(latest.totalDebt),
        'Porta 1 (financeira)': porta1 ? 'sim' : 'não',
        'Porta 3 (fluxo sustentado)': fluxoSustentado ? 'sim' : 'não',
      },
      steps: [
        'Porta 1: setor financeiro → '
            '${porta1 ? "via do acionista" : "segue para a Porta 3"}',
        if (!porta1)
          'Porta 3: NOPAT positivo em ao menos '
              '${_pct(ValuationParameters.minPositiveFlow)} dos exercícios → '
              '${fluxoSustentado ? "via da firma" : "via do acionista"}',
      ],
      result: lane == ValuationLane.firm ? 1 : 2,
      unit: lane == ValuationLane.firm ? 'via da firma' : 'via do acionista',
    );
    return lane;
  }

  // ------------------------------------------------ Porta 2 e a avaliação --

  /// Aplica a Porta 2 e desconta, na via informada.
  ///
  /// Devolve `null` quando a via não é aplicável com os dados disponíveis, o que
  /// o chamador converte em recusa declarada.
  static ValuationResult? _evaluateLane(
    ValuationInputs inputs,
    List<FundamentalsSnapshot> published,
    FundamentalsSnapshot latest,
    ValuationLane lane,
    List<String> warnings,
    AssumptionSource Function(DcfAssumptions)? scenarioBuilder,
    int samples,
    int seed,
    QuotedShares divisor,
    AuditTransaction? audit, {
    bool allowLaneMigration = true,
    List<String>? refusals,
  }) {
    final series = CapitalSeries.build(published, lane);
    if (series.isTooShort) return null;

    final local = [...warnings];

    // --- Saída 1: a base ---------------------------------------------------
    final retornoAtual = series.latestReturn;
    final retornoCiclo =
        series.cycleReturn(window: ValuationParameters.cycleWindow);
    // A deriva da tendência é medida na janela do ciclo, e **não** no horizonte
    // de projeção: um veredito estatístico sobre a série não pode mudar porque
    // o usuário trocou a projeção de 5 para 10 anos. Ver
    // [ValuationParameters.trendDriftWindow].
    final tendencia = GrowthGuards.trend(series);
    final phi = GrowthGuards.externalCapitalRatio(series);
    final destoa = GrowthGuards.deviatesFromCycle(series);

    final comparavel =
        phi == null || phi <= ValuationParameters.maxExternalCapital;

    // **A comparabilidade não trava a normalização.** Φ mede quanto da expansão
    // da base veio de fora, e é uma grandeza de *tamanho*; o que se normaliza
    // aqui é o **retorno percentual**, que é intensivo. Que a base tenha mudado
    // de escala por evento societário não torna o ROIC de um exercício de pico
    // um patamar perene: a rentabilidade percentual reverte à mediana do ciclo
    // independentemente do tamanho que a empresa passou a ter.
    //
    // Sob a precedência anterior, Φ > 1,0 impedia a normalização e o pico virava
    // base perene. A guarda passa a **declarar** a base inorgânica em vez de
    // barrar a correção do nível, e o fator continua sendo aplicado sobre a base
    // de capital corrente — a da empresa de hoje, já incorporada.
    //
    // **Em commodity, a Guarda 3 tem precedência sobre a Guarda 1.** A perna de
    // alta do ciclo tem exatamente a forma de uma tendência, e o teste a lê como
    // estrutural: a SUZB3 travou 41,5% de retorno corrente contra 18,4% de ciclo
    // e saiu a +259,1%. Em setor de commodity o preço reverte à média por
    // definição do produto, e nenhuma sequência de anos de alta muda isso — ver
    // [CyclicalSectors].
    final precedenciaDoCiclo = CyclicalSectors.hasCyclePrecedence(
      sectorKey: inputs.sectorKey,
      industry: inputs.industry,
    );
    final tendenciaTrava = tendencia?.dominates == true && !precedenciaDoCiclo;

    final normaliza = !tendenciaTrava &&
        destoa == true &&
        retornoAtual != null &&
        retornoCiclo != null &&
        retornoAtual > 0;

    // **Saúde operacional trava a normalização para cima.** A mesma medida que
    // barra o *moat*: empresa que perdeu mais da metade do resultado no triênio
    // mudou de patamar, e puxar a base dela de volta à mediana de oito anos
    // produz um retorno que ela não vai repetir. A QUAL3 perdeu a vantagem
    // residual na quarta rodada e continuou a +477,3% justamente por aqui — o
    // número não vinha da perpetuidade, vinha da base normalizada por 2,1x.
    //
    // Só o teto cai; o piso continua valendo. Quem deteriorou e ainda assim teve
    // um exercício acima do ciclo é normalizado para baixo normalmente, que é a
    // direção conservadora.
    final queda = GrowthGuards.recentOperationalDecline(published);
    final saudeReprovada =
        queda != null && queda > ValuationParameters.maxOperationalDecline;

    // **Setor cíclico é isento da trava, aqui e só aqui.** Em commodity a queda
    // de resultado entre pico e vale é oscilação do preço do insumo, e a trava
    // desfazia no vale exatamente a precedência que a decisão 28 estabeleceu:
    // VALE3 e GGBR4 acusavam quedas de 87% e iam a −70,3% e −92,7% de potencial.
    // O que limita a normalização em commodity é a saturação, que vale igual.
    //
    // A isenção **não alcança o *moat***: lá a pergunta é sobre o futuro do
    // retorno excedente, e um vale de ciclo não o sustenta melhor que uma
    // deterioração estrutural. `moatVeredito` recebe a queda sem filtro.
    final travaDeSaude = saudeReprovada && !precedenciaDoCiclo;
    final teto = travaDeSaude ? 1.0 : ValuationParameters.baseFactorCeiling;

    // O fator é saturado em razão, `1/3` a `3`. Sem teto ele explode quando o
    // exercício corrente tem retorno próximo de zero, e o DCF é homogêneo de
    // grau 1 no fluxo-base: a MBRF3 recebeu 21,4x e saiu a +406,1%.
    final fatorBruto = normaliza ? retornoCiclo / retornoAtual : 1.0;
    final fatorBase =
        normaliza ? fatorBruto.clamp(ValuationParameters.baseFactorFloor, teto) : 1.0;

    // Os dois confinamentos são reportados em separado: um é a banda de
    // política, o outro é a trava de saúde, e atribuir um ao outro faria a
    // calibragem seguinte olhar para o parâmetro errado.
    final travadoPelaSaude = normaliza && travaDeSaude && fatorBruto > 1.0;
    final saturou = normaliza &&
        (fatorBruto > ValuationParameters.baseFactorCeiling ||
            fatorBruto < ValuationParameters.baseFactorFloor);

    _auditBaseGuards(audit, retornoAtual, retornoCiclo, tendencia, phi,
        destoa == true, normaliza, fatorBase, series,
        precedenciaDoCiclo: precedenciaDoCiclo,
        rawFactor: fatorBruto,
        saturated: saturou,
        operationalDecline: queda,
        healthCapped: travadoPelaSaude,
        healthExempt: saudeReprovada && precedenciaDoCiclo);

    if (normaliza) {
      local.add(
        'O retorno sobre o capital do exercício mais recente '
        '(${_pct(retornoAtual)}) destoa da mediana de '
        '${ValuationParameters.cycleWindow} exercícios (${_pct(retornoCiclo)}); '
        'a base converge para o ciclo ao longo da projeção, fator de '
        '${fatorBase.toStringAsFixed(2)}x.',
      );
      if (precedenciaDoCiclo && tendencia?.dominates == true) {
        local.add(
          'A tendência do retorno é significante e domina a reversão à média, '
          'mas o ativo é de setor de commodity ou cíclico pesado: ali a perna '
          'de alta do ciclo tem a forma de uma tendência, e lê-la como patamar '
          'estrutural é o erro que se quer evitar. A reversão ao ciclo tem '
          'precedência, e a base foi normalizada.',
        );
      }
      if (saudeReprovada && precedenciaDoCiclo && fatorBruto > 1.0) {
        local.add(
          'O lucro ou o EBITDA recuou ${_pct(queda)} no triênio, acima do '
          'máximo de ${_pct(ValuationParameters.maxOperationalDecline)}, mas o '
          'ativo é de setor de commodity: ali a queda entre pico e vale é '
          'oscilação do preço do insumo, não quebra de modelo de negócio. A '
          'trava de saúde não se aplica à base, e a convergência ao ciclo opera '
          'nos dois sentidos. A vantagem competitiva residual segue barrada por '
          'ela, sem isenção.',
        );
      }
      if (travadoPelaSaude) {
        local.add(
          'O lucro ou o EBITDA recuou ${_pct(queda)} no triênio recente, acima '
          'do máximo de ${_pct(ValuationParameters.maxOperationalDecline)}. A '
          'base **não foi normalizada para cima**: o fator seria de '
          '${fatorBruto.toStringAsFixed(2)}x e ficou em 1,00x. Uma empresa que '
          'perdeu mais da metade do resultado mudou de patamar, e trazer a base '
          'de volta à mediana de ${ValuationParameters.cycleWindow} exercícios '
          'atribuiria a ela um retorno que não vai se repetir.',
        );
      }
      if (saturou && !travadoPelaSaude) {
        local.add(
          'O fator bruto de normalização seria de '
          '${fatorBruto.toStringAsFixed(2)}x e foi saturado em '
          '${fatorBase.toStringAsFixed(2)}x. O limite é de política, não de '
          'estatística: o preço justo é proporcional ao fluxo-base, e acima de '
          '${ValuationParameters.baseFactorCeiling.toStringAsFixed(2)}x a '
          'normalização deixaria de corrigir um exercício para inventar uma '
          'empresa. O preço justo abaixo é, nesta medida, conservador.',
        );
      }
      if (!comparavel) {
        local.add(
          'A base de capital cresceu ${_r(phi, 2)}x além do que o lucro '
          'retido financiaria, o que indica evento societário ou aquisição. '
          'A normalização foi aplicada mesmo assim: o retorno percentual é '
          'grandeza intensiva, e reverte à mediana do ciclo qualquer que tenha '
          'sido a mudança de tamanho. O que a série não sustenta é comparar '
          '**níveis absolutos** de lucro entre as pontas da janela.',
        );
      }
    }

    // --- Saída 2: a taxa ---------------------------------------------------
    final dispersao = GrowthGuards.dispersion(series);
    if (dispersao == null) return null;

    final retencao = series.medianRetention;
    final GrowthOrigin origem;
    final double g;
    if (dispersao.isIdentified) {
      origem = GrowthOrigin.fundamental;
      g = dispersao.medianGrowth;
    } else if (GrowthGuards.anchorIsFundable(
      inflation: inputs.inflation,
      cycleReturn: retornoCiclo,
      observedRetention: retencao,
    )) {
      origem = GrowthOrigin.inflationAnchor;
      g = inputs.inflation;
      local.add(
        'Crescimento fundamental não identificável: ${dispersao.failure}. '
        'Adotada a inflação de ${_pct(inputs.inflation)}, que a retenção '
        'observada de ${_pct(retencao ?? 0)} financia.',
      );
    } else {
      origem = GrowthOrigin.earningsPower;
      g = 0.0;
      local.add(
        'Crescimento não identificável nem financiável pela retenção observada; '
        'a avaliação é do valor da capacidade de gerar lucro, sem crescimento. '
        'É estimativa deliberadamente conservadora.',
      );
    }
    _auditGrowthOutcome(
        audit, dispersao, origem, g, retencao, retornoCiclo, inputs.inflation);

    // --- Premissas ---------------------------------------------------------
    final custoCorrente = lane == ValuationLane.firm
        ? _wacc(inputs, latest, local, divisor, audit)
        : (rate: inputs.capm.costOfEquity, costOfDebtEstimated: false);
    final desconto = custoCorrente.rate;

    // Custo de capital de **equilíbrio**: o mesmo beta, o mesmo prêmio e a mesma
    // estrutura de capital, sobre a taxa livre de risco estrutural em vez da
    // corrente. É o destino do decaimento e a taxa da perpetuidade. Os avisos e
    // a auditoria saem só da montagem corrente — esta repetiria os mesmos.
    final capmTerminal = inputs.capm.withRiskFree(inputs.terminalRiskFreeRate);
    final descontoTerminal = lane == ValuationLane.firm
        ? _wacc(inputs, latest, <String>[], divisor, null,
                capmOverride: capmTerminal)
            .rate
        : capmTerminal.costOfEquity;

    final perpetuo = GrowthEstimator.perpetual(
      explicitGrowth: g,
      economyGrowth: inputs.perpetualGrowthCap,
    );
    _auditPerpetualGrowth(audit, g, inputs.perpetualGrowthCap, perpetuo);

    // Vantagem competitiva residual: três condições cumulativas e restritivas.
    // O veredito carrega o motivo da recusa, não só o número — sem isso, um
    // universo em que quase ninguém passa é indistinguível de um universo em
    // que quase ninguém merece passar.
    final moatVeredito = GrowthGuards.residualMoat(
      cycleReturn: retornoCiclo,
      terminalDiscountRate: descontoTerminal,
      externalCapitalRatio: phi,
      periods: series.length,
      operationalDecline: queda,
    );
    final moat = moatVeredito.terminalReturn;

    _auditDiscountTerm(audit, inputs, desconto, descontoTerminal);
    _auditMoat(audit, moatVeredito);

    // Tolerância, e não igualdade estrita: os dois vêm de `_wacc` sobre os
    // mesmos insumos com taxas livres de risco diferentes, e quando as duas
    // coincidem o resultado é bit a bit idêntico — mas depender disso é depender
    // de determinismo de ponto flutuante para decidir se um aviso aparece. A
    // banda de 1e-7 é muito menor que qualquer diferença de taxa que valha ser
    // declarada (0,00001 p.p.) e maior que qualquer ruído de IEEE-754.
    if ((desconto - descontoTerminal).abs() > 1e-7) {
      local.add(
        'O desconto parte de ${_pct(desconto)} a.a. no primeiro ano e converge '
        'linearmente para ${_pct(descontoTerminal)} a.a. no ano '
        '${inputs.projectionYears}, que é a taxa da perpetuidade. A taxa livre '
        'de risco vai de ${_pct(inputs.capm.riskFreeRate)} para '
        '${_pct(inputs.terminalRiskFreeRate)}: o modelo não tem curva de juros, '
        'e descontar perpetuidade pelo CDI de um dia casaria durações '
        'incompatíveis.',
      );
    }

    if (moat != null) {
      local.add(
        'Vantagem competitiva comprovada: retorno do ciclo de '
        '${_pct(retornoCiclo!)} contra custo de capital de equilíbrio de '
        '${_pct(descontoTerminal)}, crescimento orgânico e '
        '${series.length} exercícios. A perpetuidade preserva '
        '${_pct(ValuationParameters.moatRetainedSpread)} do excedente, com '
        'retorno terminal de ${_pct(moat)} em vez do estado estacionário. '
        'O valor terminal volta a depender do crescimento perpétuo.',
      );
    }

    // O retorno que converte crescimento em retenção, ano a ano — `b_t = g_t /
    // ROIC_t` —, precisa ser o retorno **do fluxo-base que se está
    // descontando**, e não o do ciclo por princípio.
    //
    // Como o fluxo-base é `NOPAT_atual × fator` sobre a mesma base de capital,
    // o retorno implícito nele é `retorno_atual × fator`. A identidade fecha os
    // três casos de uma vez: normalizado sem saturar, dá exatamente o retorno do
    // ciclo; normalizado com saturação, dá o retorno que a saturação de fato
    // impôs; não normalizado, dá o retorno corrente.
    //
    // Usar o ciclo quando a base **não** foi normalizada misturava o fluxo de um
    // ano com o retorno de outro, e sempre na direção de exigir menos
    // reinvestimento do que a empresa precisa: medido na AZZA3, um retorno de
    // ciclo de 19,55% sobre um fluxo-base de retorno corrente de 7,82% inflava
    // o valor da firma em 17%.
    //
    // Sem retorno corrente utilizável — série curta, exercício de prejuízo ou
    // buraco na ponta —, o do ciclo continua sendo a melhor estimativa
    // disponível e é o que entra. Zerar ali **desligaria** o freio, que é a
    // direção agressiva: o fluxo cresceria sem nada retido para financiá-lo.
    final retornoDaBase = (retornoAtual != null && retornoAtual > 0)
        ? retornoAtual * fatorBase
        : (retornoCiclo ?? 0.0);

    final assumptions = DcfAssumptions(
      projectionYears: inputs.projectionYears,
      growthRate: g,
      perpetualGrowth: perpetuo,
      discountRate: desconto,
      terminalDiscountRate: descontoTerminal,
      returnOnCapital: retornoDaBase,
      terminalReturnOnCapital: moat,
      marginOfSafety: inputs.marginOfSafety,
    );

    // --- Fluxo-base --------------------------------------------------------
    final base = _baseProfitFor(lane, latest, divisor, fatorBase);
    if (base == null || base <= 0) return null;

    // O divisor é a contagem de unidades que forma a cotação — ver
    // [ValuationCascade.quotedShares]. Com ela, o potencial é `E ÷ VM − 1` e
    // nenhuma contagem de ação sobra na comparação com o preço de tela.
    final shares = divisor.count;
    Result<double> valuate(DcfAssumptions a) => lane == ValuationLane.firm
        ? DcfCalculator.firm(
            baseProfit: base,
            assumptions: a,
            netDebt: latest.netDebt,
            sharesOutstanding: shares,
          ).map((o) => o.fairValuePerShare)
        : DcfCalculator.shareholder(baseProfit: base, assumptions: a)
            .map((o) => o.fairValuePerShare);

    final primeiro = lane == ValuationLane.firm
        ? DcfCalculator.firm(
            baseProfit: base,
            assumptions: assumptions,
            netDebt: latest.netDebt,
            sharesOutstanding: shares,
          )
        : DcfCalculator.shareholder(baseProfit: base, assumptions: assumptions);
    if (primeiro.isErr) return null;

    final outcome = primeiro.unwrap();

    // --- Pós-condição: a ponte de equity -----------------------------------
    //
    // Não pode ser pré-filtro: depende do valor da firma, que só existe depois
    // do desconto. Medido, a RENT3 tem participação de equity de 54% pelo
    // mercado e ainda assim saía com preço justo de R$ 0,12, porque o valor da
    // firma do modelo era metade do de mercado. A migração agora é declarada,
    // e não silenciosa como no antigo `fairValuePerShare <= 0`.
    if (lane == ValuationLane.firm &&
        allowLaneMigration &&
        outcome.equityShare < ValuationParameters.minEquityShare) {
      _auditEquityBridgeFailure(audit, outcome.equityShare);
      final migrada = _evaluateLane(
        inputs,
        published,
        latest,
        ValuationLane.shareholder,
        [
          ...warnings,
          'O capital próprio responde por apenas ${_pct(outcome.equityShare)} '
              'do valor da firma: o preço por papel seria resíduo de uma '
              'subtração entre números próximos. A avaliação migra para o fluxo '
              'do acionista.',
        ],
        scenarioBuilder,
        samples,
        seed,
        divisor,
        audit,
        allowLaneMigration: false,
        refusals: refusals,
      );
      if (migrada != null) return migrada;
      // **Migração impossível vira recusa nomeada, não número sem conteúdo.**
      // A própria pós-condição afirma que, com a dívida líquida consumindo o
      // valor da firma, o que sobra é resíduo de subtração e não avaliação —
      // publicar esse resíduo contradiria a afirmação que o motivou. O erro
      // relativo do valor da firma chega ao preço por papel amplificado por
      // `1/participação`, e num ativo de 3% de participação isso é trinta
      // vezes: a AMER3 saía a R$ 0,20 em dez anos e R$ 1,47 em cinco, um fator
      // de 7,35 vindo só da forma da curva de desconto.
      //
      // O efeito colateral é aceito: um ativo deixa de ser avaliado num
      // horizonte e continua sendo em outro, conforme a pós-condição dispare ou
      // não. Entre um número sem conteúdo e uma recusa que diz por quê, a
      // recusa é a saída que a decisão 25 exige.
      //
      // A recusa é **nomeada**, que é o que a decisão 25 exige de toda saída.
      //
      // A participação **não** é positiva por construção: com a dívida líquida
      // maior que o valor da firma ela fica negativa, e foi medida em −142,6%
      // na CSNA3 e −558,3% na MRVE3. A amplificação `1/participação` só tem
      // sentido no ramo positivo, e nem `Infinity` nem número negativo passam
      // por `toStringAsFixed`.
      final share = outcome.equityShare;
      final amplificacao = share > 0
          ? 'com o erro do valor da firma amplificado '
              '${(1 / share).toStringAsFixed(0)} vezes'
          : 'e a dívida líquida supera o próprio valor da firma, de modo que '
              'não sobra capital próprio a repartir';
      refusals?.add(
        'O capital próprio responde por apenas ${_pct(share)} do valor da '
        'firma de ${inputs.ticker.value}, e a via do acionista não se aplica: '
        'o preço por papel seria resíduo de uma subtração entre números '
        'próximos, $amplificacao. O ativo não é avaliável por fluxo descontado '
        'nesta estrutura de capital.',
      );
      return null;
    }

    if (outcome.fairValuePerShare <= 0) return null;

    _auditDcf(
      audit,
      outcome: outcome,
      assumptions: assumptions,
      baseFlow: base,
      flowSymbol: lane == ValuationLane.firm ? 'NOPAT' : 'LPA',
      discountSymbol: lane == ValuationLane.firm ? 'WACC' : 'K_e',
      perShareAlready: lane == ValuationLane.shareholder,
    );
    if (lane == ValuationLane.firm) {
      _auditEquityBridge(
        audit,
        enterpriseValue: outcome.enterpriseValue,
        netDebt: latest.netDebt,
        shares: shares,
        perShare: outcome.fairValuePerShare,
      );
    }

    return _withScenarios(
      inputs: inputs,
      model: lane == ValuationLane.firm
          ? ValuationModel.dcfFcff
          : ValuationModel.dcfEarnings,
      assumptions: assumptions,
      baseValue: outcome.fairValuePerShare,
      valuate: valuate,
      scenarioBuilder: scenarioBuilder,
      samples: samples,
      seed: seed,
      warnings: local,
      diagnostics: _diagnose(
        outcome: outcome,
        divisor: divisor,
        baseFactor: fatorBase,
        growthOrigin: origem,
        moatApplied: moat != null,
        migrated: !allowLaneMigration,
      ),
    );
  }

  /// Reúne os fatos que qualificam o preço justo.
  ///
  /// **Não julga nada de novo.** Cada ressalva corresponde a uma decisão que a
  /// cascata já tomou e já declarou em texto; o que muda é que sai também em
  /// forma estruturada, para que a carteira possa ponderar por firmeza em vez
  /// de tratar todo preço justo como igualmente apoiado.
  ///
  /// - [migrated]: `true` no passe que veio de migração de via, que é
  ///   justamente quando `allowLaneMigration` chega desligado.
  static ValuationDiagnostics _diagnose({
    required DcfOutcome outcome,
    required QuotedShares divisor,
    required double baseFactor,
    required GrowthOrigin growthOrigin,
    required bool moatApplied,
    required bool migrated,
  }) {
    final caveats = <ValuationCaveat>[];
    if (outcome.terminalShare > ValuationDiagnostics.terminalShareLimit) {
      caveats.add(ValuationCaveat.terminalPesado);
    }
    if (growthOrigin != GrowthOrigin.fundamental) {
      caveats.add(ValuationCaveat.crescimentoNaoIdentificado);
    }
    if (divisor.diverge) caveats.add(ValuationCaveat.escalaIncerta);
    if (baseFactor > ValuationDiagnostics.baseFactorLimit ||
        baseFactor < 1 / ValuationDiagnostics.baseFactorLimit) {
      caveats.add(ValuationCaveat.baseNormalizadaForte);
    }
    if (migrated) caveats.add(ValuationCaveat.viaMigrada);
    if (outcome.equityShare < ValuationDiagnostics.fragileEquityShare) {
      caveats.add(ValuationCaveat.ponteFragil);
    }
    return ValuationDiagnostics(
      terminalShare: outcome.terminalShare,
      equityShare: outcome.equityShare,
      baseFactor: baseFactor,
      growthIdentified: growthOrigin == GrowthOrigin.fundamental,
      moatApplied: moatApplied,
      caveats: List.unmodifiable(caveats),
    );
  }

  /// Lucro-base da via, já normalizado pelo fator do ciclo.
  ///
  /// Na via da firma é o NOPAT; na do acionista, o lucro por papel na unidade
  /// negociada. Multiplicar o lucro observado pelo fator equivale a partir do
  /// retorno do ciclo aplicado à base de capital corrente, e mantém a escala da
  /// empresa de hoje — que é o que a winsorização contra a mediana absoluta
  /// perdia ao misturar ciclo com crescimento de tamanho.
  static double? _baseProfitFor(
    ValuationLane lane,
    FundamentalsSnapshot latest,
    QuotedShares divisor,
    double fatorBase,
  ) {
    if (lane == ValuationLane.firm) {
      final n = latest.nopatOrDerived;
      return n == null ? null : n * fatorBase;
    }
    final lpa = _earningsPerQuotedUnit(latest, divisor);
    return lpa == null ? null : lpa * fatorBase;
  }

  /// Lucro por **unidade negociada**, na mesma escala do preço de tela.
  ///
  /// Divide o lucro agregado pela contagem que forma a cotação, e não pela do
  /// exercício: o resultado é comparado com o preço de hoje, e um LPA na escala
  /// societária de outro momento não o é. O recuo para o LPA publicado só age
  /// quando o lucro agregado falta, e converte pela razão de unidade.
  static double? _earningsPerQuotedUnit(
    FundamentalsSnapshot snapshot,
    QuotedShares divisor,
  ) {
    final netIncome = snapshot.netIncome;
    if (netIncome != null && divisor.count > 0) {
      return netIncome / divisor.count;
    }
    final published = snapshot.earningsPerShare;
    return published == null ? null : published * divisor.sharesPerQuote;
  }
  /// Monta o WACC, ou o Ke quando a estrutura de capital não é observável.
  ///
  /// - [capmOverride]: substitui o CAPM dos insumos. Serve para montar o custo
  ///   de capital **de equilíbrio**, com a taxa livre de risco estrutural no
  ///   lugar da corrente, sem duplicar esta função.
  /// Devolve a taxa **e** se o custo da dívida usado foi estimado.
  ///
  /// O segundo campo não é detalhe de log: ele entra nos diagnósticos do
  /// resultado, e recalculá-lo fora daqui duplicaria a regra de
  /// `CostOfCapital`.
  static ({double rate, bool costOfDebtEstimated}) _wacc(
    ValuationInputs inputs,
    FundamentalsSnapshot latest,
    List<String> warnings,
    QuotedShares divisor,
    AuditTransaction? audit, {
    CapmInputs? capmOverride,
  }) {
    final capm = capmOverride ?? inputs.capm;
    final debt = latest.totalDebt;
    final equity = latest.marketCap ?? (divisor.count * inputs.marketPrice);
    // O observado entra apenas como **conferência**: desde a decisão 31 o Kd
    // aplicado é `Rf + spread(cobertura)`, e como `capm` aqui pode ser o de
    // equilíbrio, o custo da dívida do terminal decai junto com a taxa livre de
    // risco, preservando o prêmio de crédito. Medido numa empresa de cobertura
    // 3,7x: 16,49% no corrente contra 11,80% no terminal, com os mesmos 2,40
    // p.p. de spread. Ver `CostOfCapital.effectiveCostOfDebt`.
    final kd = latest.costOfDebt;
    // O escudo fiscal usa a alíquota **marginal estatutária**, não a efetiva do
    // exercício: o benefício do endividamento é o valor presente dos escudos
    // futuros, que se realizam à alíquota legal. A efetiva continua sendo
    // medida e declarada quando destoa — ver
    // [ValuationParameters.statutoryTaxRate].
    const tax = ValuationParameters.statutoryTaxRate;
    final efetiva = latest.effectiveTaxRate;

    if (debt <= 0 || equity <= 0 || kd == null) {
      warnings.add(
        'Estrutura de capital indisponível; desconto feito ao custo do capital '
        'próprio em vez do WACC.',
      );
      audit?.step(
        formulaName: 'Taxa de desconto — degeneração para o Ke',
        latex: r'r = K_e \quad (\text{sem estrutura de capital observável})',
        variables: {
          'D (R\$)': _r(debt),
          'E (R\$)': _r(equity),
          'K_d (% a.a.)': kd == null ? null : _r(kd * 100),
        },
        steps: const [
          'Passo único: dívida, valor de mercado ou custo da dívida ausentes; '
              'o WACC não é montável e o desconto adota o custo do capital '
              'próprio.',
        ],
        result: capm.costOfEquity * 100,
        unit: '% a.a.',
      );
      return (rate: capm.costOfEquity, costOfDebtEstimated: false);
    }

    if (efetiva != null && (efetiva - tax).abs() > 0.10) {
      warnings.add(
        'A alíquota efetiva do exercício foi de ${_pct(efetiva)}, distante da '
        'alíquota marginal estatutária de ${_pct(tax)} usada no escudo fiscal '
        'do WACC. O escudo desconta despesa financeira **futura**, que se '
        'realiza à alíquota legal; a efetiva de um exercício carrega '
        'incentivo, JCP, prejuízo compensado e diferimento.',
      );
    }

    final coc = CostOfCapital(
      capm: capm,
      costOfDebt: kd,
      taxRate: tax,
      equityValue: equity,
      debtValue: debt,
      interestCoverage: latest.interestCoverage,
      netDebtToEbitda: latest.netDebtToEbitda,
    );

    if (coc.costOfDebtWasClamped) {
      final alavancagem = latest.netDebtToEbitda;
      warnings.add(
        'O custo da dívida implícito nos demonstrativos deu '
        '${_pct(kd)} a.a., fora da faixa defensável de '
        '${_pct(capm.riskFreeRate)} a '
        '${_pct(capm.riskFreeRate + CostOfCapital.maxCreditSpread)}. A despesa '
        'financeira publicada inclui arrendamento e variação cambial, que não '
        'são captação. Adotado ${_pct(coc.effectiveCostOfDebt)} a.a., da '
        'classificação sintética por alavancagem'
        '${alavancagem == null ? ' (dívida líquida sobre EBITDA não medível)' : ' de ${alavancagem.toStringAsFixed(2)}x'}.',
      );
    }
    if (coc.waccWasFloored) {
      warnings.add(
        'O WACC calculado (${_pct(coc.rawWacc)} a.a.) ficou abaixo da taxa '
        'livre de risco; adotada a própria taxa livre de risco '
        '(${_pct(capm.riskFreeRate)} a.a.) como piso do desconto.',
      );
    }

    _auditWacc(audit, coc);
    return (rate: coc.wacc, costOfDebtEstimated: coc.costOfDebtWasClamped);
  }

  static String _pct(double fraction) =>
      '${(fraction * 100).toStringAsFixed(1)}%';
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
    required ValuationDiagnostics diagnostics,
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
        diagnostics: diagnostics,
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
      diagnostics: diagnostics,
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
        if (result.diagnostics != null)
          'diagnostics': {
            'terminalShare': _r(result.diagnostics!.terminalShare, 4),
            'equityShare': _r(result.diagnostics!.equityShare, 4),
            'baseFactor': _r(result.diagnostics!.baseFactor, 4),
            'growthIdentified': result.diagnostics!.growthIdentified,
            'moatApplied': result.diagnostics!.moatApplied,
            'caveats': [
              for (final c in result.diagnostics!.caveats) c.name,
            ],
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

  static void _auditQuotedShares(
    AuditTransaction? audit,
    FundamentalsSnapshot latest,
    double marketPrice,
    QuotedShares divisor,
  ) {
    if (audit == null) return;
    final vm = latest.marketCap;
    audit.step(
      formulaName: 'Contagem de papéis da ponte',
      latex: r'N_{ponte} = \max\!\left(\frac{VM}{P_{mkt}},\; '
          r'\frac{N_{conciliado}}{u}\right)'
          r'\;\;\text{na divergência};\;\; \frac{VM}{P_{mkt}}\;\;\text{fora dela}',
      variables: {
        'VM (R\$)': vm == null ? null : _r(vm),
        'P_mkt (R\$)': _r(marketPrice),
        'N pelo mercado': divisor.fromMarketCap == null
            ? null
            : _r(divisor.fromMarketCap!, 0),
        'N pelas demonstrações': divisor.fromStatements == null
            ? null
            : _r(divisor.fromStatements!, 0),
        'divergência (x)':
            divisor.divergence == null ? null : _r(divisor.divergence!, 3),
      },
      steps: [
        'Passo 1: contagem implícita no valor de mercado → '
            '${vm == null ? 'valor de mercado ausente' : '${_r(vm)} ÷ ${_r(marketPrice)} = ${_r(divisor.fromMarketCap ?? 0, 0)}'}',
        'Passo 2: contagem conciliada pelas demonstrações, na unidade '
            'negociada → ${_r(divisor.fromStatements ?? 0, 0)}',
        'Passo 3: as duas ${divisor.diverge ? 'divergem além da banda de ${FundamentalsSnapshot.reconciliationBand}x; adotada a maior, que é o sentido conservador do erro' : 'concordam dentro da banda de ${FundamentalsSnapshot.reconciliationBand}x; adotada a do mercado'} → '
            '${divisor.source.label}',
      ],
      result: _r(divisor.count, 0).toDouble(),
      unit: 'papéis na unidade negociada',
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
    final afterTax = kd * (1 - coc.effectiveTaxShield);
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
        't (%)': _r(coc.effectiveTaxShield * 100),
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
            '${_r(coc.effectiveTaxShield, 4)}) = ${_pct(afterTax)}',
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

  /// Registra as três guardas da Saída 1 e o veredito sobre a base.
  static void _auditBaseGuards(
    AuditTransaction? audit,
    double? retornoAtual,
    double? retornoCiclo,
    TrendVerdict? tendencia,
    double? phi,
    bool destoa,
    bool normaliza,
    double fator,
    CapitalSeries series, {
    required bool precedenciaDoCiclo,
    required double rawFactor,
    required bool saturated,
    required double? operationalDecline,
    required bool healthCapped,
    required bool healthExempt,
  }) {
    if (audit == null) return;
    audit.step(
      sample: _returnSample(series, retornoCiclo, retornoAtual, normaliza),
      formulaName: 'Base do fluxo: convergência ao ciclo',
      latex: r'r_t = r_{atual} + (r_{ciclo} - r_{atual}) \cdot \frac{t}{N}',
      variables: {
        'retorno atual (% a.a.)': _r((retornoAtual ?? 0) * 100),
        'mediana do ciclo (% a.a.)': _r((retornoCiclo ?? 0) * 100),
        'inclinação da tendência (p.p./ano)':
            tendencia == null ? 'n/d' : _r(tendencia.slope * 100, 2),
        't de Newey-West': tendencia == null ? 'n/d' : _r(tendencia.tStatistic, 2),
        'capital externo / base (Φ)': phi == null ? 'n/d' : _r(phi, 2),
        // Chaves de leitura por máquina, pelo mesmo motivo das do passo da
        // vantagem residual: sem elas, "a base não foi normalizada" não diz
        // qual guarda decidiu, e a calibragem vira suposição.
        'guarda 1 — tendência': tendencia == null
            ? 'não avaliável'
            : (tendencia.dominates ? 'domina' : 'não domina'),
        'guarda 3 — desvio do ciclo':
            destoa ? 'destoa' : 'dentro da banda e do desvio robusto',
        'precedência do ciclo (setor cíclico)': precedenciaDoCiclo,
        'fator bruto': _r(rawFactor, 3),
        'fator saturado': saturated,
        'queda no triênio (%)':
            operationalDecline == null ? null : _r(operationalDecline * 100),
        'teto travado pela saúde': healthCapped,
        'isento da trava por setor cíclico': healthExempt,
      },
      steps: [
        'Guarda 1 — tendência: '
            '${tendencia == null ? "não avaliável" : (tendencia.dominates ? (precedenciaDoCiclo ? "domina a reversão, mas o setor é cíclico: a Guarda 3 tem precedência" : "domina a reversão, base mantida") : (tendencia.isSignificant ? "significante, mas a reversão é maior" : "sem tendência"))}',
        'Guarda 2 — comparabilidade (declara, não barra): '
            '${phi == null ? "não avaliável" : (phi <= ValuationParameters.maxExternalCapital ? "expansão orgânica, base comparável" : "capital externo de ${_r(phi, 2)}x a base inicial, base inorgânica")}',
        'Guarda 3 — desvio do ciclo: '
            '${destoa ? "o exercício destoa" : "dentro da banda e do desvio robusto"}',
        normaliza
            ? 'Base normalizada por ${fator.toStringAsFixed(2)}x, convergindo ao longo da projeção'
            : 'Base mantida como observada',
        if (healthCapped)
          'Saúde operacional: queda de '
              '${operationalDecline == null ? "n/d" : _pct(operationalDecline)} '
              'no triênio; o teto do fator cai para 1,00x e a base não é '
              'normalizada para cima',
        if (healthExempt)
          'Saúde operacional: queda de '
              '${operationalDecline == null ? "n/d" : _pct(operationalDecline)} '
              'no triênio, mas o setor é cíclico — isento da trava na Porta 2a. '
              'A vantagem residual segue barrada por ela',
        if (saturated)
          'Saturação: o fator bruto de ${rawFactor.toStringAsFixed(2)}x saiu da '
              'banda de [${ValuationParameters.baseFactorFloor}, '
              '${ValuationParameters.baseFactorCeiling}] e foi confinado a '
              '${fator.toStringAsFixed(2)}x',
      ],
      result: _r(fator, 3).toDouble(),
      unit: 'fator sobre o lucro observado',
    );
  }

  /// Amostra de retorno que sustenta a mediana do ciclo.
  ///
  /// Substitui a amostra do fluxo-base, que saiu com a decisão 25: o
  /// normalizador passou a operar sobre o **retorno** sobre a base de capital, e
  /// é essa a série que precisa ficar visível para quem confere a conta.
  static TraceSample? _returnSample(
    CapitalSeries series,
    double? ciclo,
    double? atual,
    bool normaliza,
  ) {
    final r = series.returns;
    if (r.length < 3) return null;
    final ini = r.length - 1 - ValuationParameters.cycleWindow;
    final janela = r.sublist(ini < 0 ? 0 : ini);

    // Marcação por **posição na ordenação**, não por valor: com exercícios de
    // retorno repetido, comparar por valor marcaria três ou quatro pontos e
    // daria a entender que todos entraram na conta. Exatamente um ponto é
    // marcado numa amostra ímpar, exatamente dois numa par.
    final ordem = [for (var i = 0; i < janela.length; i++) i]
      ..sort((a, b) => janela[a].value.compareTo(janela[b].value));
    final meio = ordem.length ~/ 2;
    final centrais = ordem.length.isOdd
        ? {ordem[meio]}
        : {ordem[meio - 1], ordem[meio]};

    return TraceSample(
      title: series.lane == ValuationLane.firm
          ? 'Retorno sobre o capital investido, por exercício'
          : 'Retorno sobre o patrimônio, por exercício',
      points: [
        for (var i = 0; i < janela.length; i++)
          TraceSamplePoint(
            label: '${janela[i].year}',
            value: _r(janela[i].value * 100).toDouble(),
            definesResult: centrais.contains(i) && i != janela.length - 1,
            isObserved: i == janela.length - 1,
          ),
      ],
      summary: ciclo == null ? null : _r(ciclo * 100).toDouble(),
      summaryLabel: 'mediana do ciclo',
      selected: (normaliza && ciclo != null)
          ? _r(ciclo * 100).toDouble()
          : (atual == null ? null : _r(atual * 100).toDouble()),
      unit: '%',
    );
  }

  /// Registra a Saída 2: qual estimador decidiu a taxa, e por quê.
  static void _auditGrowthOutcome(
    AuditTransaction? audit,
    DispersionVerdict d,
    GrowthOrigin origem,
    double g,
    double? retencao,
    double? retornoCiclo,
    double inflacao,
  ) {
    if (audit == null) return;
    final exigida =
        (retornoCiclo != null && retornoCiclo > 0) ? inflacao / retornoCiclo : null;
    audit.step(
      formulaName: 'Crescimento explícito',
      latex: r'g = \mathrm{mediana}\left(\frac{\Delta \text{base}_t}{\text{base}_{t-1}}\right)',
      variables: {
        'g pela mediana (% a.a.)': _r(d.medianGrowth * 100),
        'g pela regressão (% a.a.)': _r(d.regressionGrowth * 100),
        'erro-padrão de ĝ (p.p.)': _r(d.stdError * 100, 2),
        'discordância D': _r(d.d, 2),
        'D crítico': _r(d.criticalD, 2),
        'retenção observada (%)': retencao == null ? 'n/d' : _r(retencao * 100),
      },
      steps: [
        'Passo 1: precisão e concordância → '
            '${d.isIdentified ? "crescimento identificável" : d.failure}',
        if (!d.isIdentified)
          'Passo 2: a inflação de ${_pct(inflacao)} exigiria reter '
              '${exigida == null ? "n/d" : _pct(exigida)} contra '
              '${retencao == null ? "n/d" : _pct(retencao)} observados → '
              '${origem == GrowthOrigin.inflationAnchor ? "âncora aceita" : "âncora recusada"}',
        'Origem adotada: ${origem.label}',
      ],
      result: _r(g * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  /// Registra a migração de via disparada pela ponte de equity fina.
  static void _auditEquityBridgeFailure(
    AuditTransaction? audit,
    double equityShare,
  ) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Pós-condição da ponte de equity',
      latex: r'\frac{EV - D_{liq}}{EV} \geq 0{,}20',
      variables: {
        'participação do equity (%)': _r(equityShare * 100),
        'mínimo exigido (%)': _r(ValuationParameters.minEquityShare * 100),
        'amplificação do erro (x)':
            equityShare > 0 ? _r(1 / equityShare, 1) : 'infinita',
      },
      steps: [
        'O capital próprio responde por ${_pct(equityShare)} do valor da firma, '
            'abaixo do mínimo de ${_pct(ValuationParameters.minEquityShare)}',
        'Subtrair dois números próximos amplifica o erro relativo por '
            '${equityShare > 0 ? (1 / equityShare).toStringAsFixed(0) : "∞"}x: '
            'o preço por papel seria resíduo, não avaliação',
        'A avaliação migra para o fluxo do acionista, e a migração é declarada',
      ],
      result: _r(equityShare * 100).toDouble(),
      unit: '% do valor da firma',
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
        'g_eco nominal (% a.a.)': _r(economyGrowth * 100),
      },
      steps: [
        'Passo 1: menor entre o crescimento explícito e o da economia → '
            'min(${_pct(explicitGrowth)}, ${_pct(economyGrowth)}) = '
            '${_pct(explicitGrowth < economyGrowth ? explicitGrowth : economyGrowth)}',
        'Passo 2: confinado a [0, ${_pct(economyGrowth)}] — uma empresa não '
            'cresce acima da economia para sempre → ${_pct(perpetual)}. '
            'O teto é **nominal**: composto do crescimento real da atividade com '
            'a inflação observada, porque a taxa de desconto também é nominal, '
            'por sair do CDI. Não é o PIB real.',
      ],
      result: _r(perpetual * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditDiscountTerm(
    AuditTransaction? audit,
    ValuationInputs inputs,
    double spot,
    double terminal,
  ) {
    if (audit == null) return;
    audit.step(
      formulaName: 'Estrutura a termo da taxa de desconto',
      latex: r'r_t = r_{spot} - (r_{spot} - r_\infty)\cdot\frac{t-1}{N-1}',
      variables: {
        'R_f corrente (% a.a.)': _r(inputs.capm.riskFreeRate * 100),
        'R_f estrutural (% a.a.)': _r(inputs.terminalRiskFreeRate * 100),
        'r_spot (% a.a.)': _r(spot * 100),
        'r_inf (% a.a.)': _r(terminal * 100),
        'N (anos)': inputs.projectionYears,
      },
      steps: [
        'Passo 1: o custo de capital do ano 1 usa a taxa livre de risco '
            'corrente → ${_pct(spot)}',
        'Passo 2: o custo de capital de equilíbrio repete beta, prêmio e '
            'estrutura de capital sobre a taxa estrutural → ${_pct(terminal)}. '
            'Como Ke e WACC são afins na taxa livre de risco, decair o custo de '
            'capital equivale a decair a taxa e remontar o custo a cada ano',
        'Passo 3: a perpetuidade é descontada a ${_pct(terminal)}, e o fator de '
            'desconto acumula as taxas ano a ano em vez de elevar uma só a t',
      ],
      result: _r(terminal * 100).toDouble(),
      unit: '% a.a.',
    );
  }

  static void _auditMoat(AuditTransaction? audit, MoatVerdict v) {
    if (audit == null) return;
    final ciclo = v.cycleReturn;
    final excedente = v.spread;
    audit.step(
      formulaName: 'Vantagem competitiva residual na perpetuidade',
      latex:
          r'ROIC_\infty = WACC_\infty + \lambda\,(ROIC_{ciclo} - WACC_\infty)',
      variables: {
        'ROIC do ciclo (% a.a.)': ciclo == null ? null : _r(ciclo * 100),
        'WACC de equilíbrio (% a.a.)': _r(v.terminalDiscountRate * 100),
        'exigido pelo múltiplo (% a.a.)': _r(v.requiredByMultiple * 100),
        'exigido pelo excedente (% a.a.)': _r(v.requiredBySpread * 100),
        'excedente do ciclo (p.p.)':
            excedente == null ? null : _r(excedente * 100),
        'Phi': v.externalCapitalRatio == null
            ? null
            : _r(v.externalCapitalRatio!, 2),
        'exercícios': v.periods,
        'lambda': ValuationParameters.moatRetainedSpread,
        'queda no triênio (%)': v.operationalDecline == null
            ? null
            : _r(v.operationalDecline! * 100),
        // Chaves de leitura por máquina: é por elas que o relatório de
        // validação agrupa os reprovados sem depender de análise de texto.
        'condição que barrou': v.primaryBlock?.name ?? 'nenhuma',
        'condições que barraram': [for (final b in v.blocks) b.name],
      },
      steps: [
        'Passo 1: crescimento orgânico? Phi = '
            '${v.externalCapitalRatio == null ? "não medido" : _r(v.externalCapitalRatio!, 2)} '
            '${v.externalCapitalRatio != null && v.externalCapitalRatio! <= ValuationParameters.moatMaxExternalCapital ? "<=" : ">"} '
            '${ValuationParameters.moatMaxExternalCapital}',
        'Passo 2: rentabilidade estrutural, por união de duas pernas — '
            'múltiplo de ${ValuationParameters.moatReturnMultiple}x o WACC '
            '(${_pct(v.requiredByMultiple)}): '
            '${v.passesByMultiple ? "passa" : "reprova"}; excedente de '
            '${_pct(ValuationParameters.moatMinSpread)} sobre o WACC '
            '(${_pct(v.requiredBySpread)}): '
            '${v.passesBySpread ? "passa" : "reprova"}. ROIC do ciclo: '
            '${ciclo == null ? "não medido" : _pct(ciclo)}',
        'Passo 3: histórico longo? ${v.periods} exercícios contra '
            '${ValuationParameters.moatMinPeriods} exigidos',
        'Passo 4: saúde operacional? queda de lucro ou EBITDA no triênio de '
            '${v.operationalDecline == null ? "não medida" : _pct(v.operationalDecline!)} '
            'contra o máximo de '
            '${_pct(ValuationParameters.maxOperationalDecline)}',
        v.isProven
            ? 'Passo 5: todas as condições valem — ROIC_inf = '
                '${_pct(v.terminalReturn!)}, e o valor terminal volta a depender '
                'de g_inf, que é o preço declarado da exceção'
            : 'Passo 5: barrado por ${v.blocks.map((b) => b.label).join(", ")} — '
                'vale o estado estacionário, ROIC_inf = WACC_inf, e o valor '
                'terminal não depende de g_inf',
      ],
      // O resultado é o retorno terminal **efetivamente adotado**: o do moat
      // quando as três condições valem, o próprio custo de capital quando não.
      // Nunca nulo — a etapa decidiu algo em qualquer dos dois caminhos.
      result: _r((v.terminalReturn ?? v.terminalDiscountRate) * 100).toDouble(),
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
    final rInf = assumptions.terminalDiscountRate;
    final g = assumptions.growthRate;
    final gInf = assumptions.perpetualGrowth;
    final n = outcome.projectedFlows.length;
    final sumPv = outcome.enterpriseValue - outcome.discountedTerminalValue;

    // O rastro precisa reproduzir a conta que foi feita, e a conta usa taxa,
    // crescimento e retenção **variáveis** ano a ano. Descrevê-la com g e r
    // constantes escrevia números que não fecham com o resultado ao lado: num
    // ativo típico, o fluxo do ano 10 aparecia 2,45x maior que o efetivamente
    // usado, e o fator de desconto 1,21x maior. O fator abaixo é o mesmo
    // acumulado que `DcfCalculator._project` monta.
    var fator = 1.0;
    final fatores = <double>[];
    for (var t = 1; t <= n; t++) {
      fator *= 1 + assumptions.discountRateAt(t);
      fatores.add(fator);
    }

    audit.step(
      formulaName: 'Projeção e desconto do período explícito ($flowSymbol)',
      latex: r'VP_{explícito} = \sum_{t=1}^{N} '
          r'\frac{L_t\,(1 - b_t)}{\prod_{s=1}^{t}(1 + r_s)}'
          r'\quad;\quad L_t = L_{t-1}(1 + g_t),\; b_t = g_t / ROIC_t',
      variables: {
        'F_0': _r(baseFlow),
        'g_1 (% a.a.)': _r(g * 100),
        'g_N (% a.a.)': _r(assumptions.growthAt(n) * 100),
        'r_1 = $discountSymbol (% a.a.)': _r(r * 100),
        'r_N (% a.a.)': _r(assumptions.discountRateAt(n) * 100),
        'ROIC_1 (% a.a.)': _r(assumptions.returnOnCapitalAt(1) * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps: [
        'Passo 0: as taxas decaem linearmente ao longo da janela. O fator de '
            'desconto **acumula** a taxa de cada ano em vez de elevar uma só a '
            't, e o fluxo do ano é o lucro menos a retenção que financia o '
            'crescimento daquele mesmo ano.',
        for (var t = 1; t <= n; t++)
          'Passo $t: ano $t → g = ${_pct(assumptions.growthAt(t))}, '
              'retenção = ${_pct(assumptions.retentionAt(t))}, '
              'r = ${_pct(assumptions.discountRateAt(t))}; fluxo '
              '${_r(outcome.projectedFlows[t - 1])} ÷ fator acumulado '
              '${_r(fatores[t - 1], 6)} → valor presente '
              '${_r(outcome.discountedFlows[t - 1])}',
        'Passo ${n + 1}: soma dos valores presentes do período explícito → '
            '${_r(sumPv)}',
      ],
      result: sumPv,
      unit: perShareAlready ? r'R$ por papel' : r'R$',
    );

    // Duas formas de terminal, e o rastro precisa dizer qual foi aplicada: com
    // retorno neutro o crescimento perpétuo **sai** da fórmula, e exibir o
    // spread de Gordon ali descreveria uma conta que não foi feita. A taxa é a
    // de equilíbrio, não a corrente.
    // Três formas de terminal, e o rastro precisa dizer qual foi aplicada. Com
    // retorno neutro o crescimento perpétuo **sai** da fórmula, e exibir o
    // spread de Gordon ali descreveria uma conta que não foi feita. A taxa é
    // sempre a de equilíbrio, nunca a corrente.
    //
    // O ramo de retenção só existe quando não há retorno terminal declarado
    // **e** o retorno neutro está desligado — caminho que a cascata não usa,
    // mas que a classe permite a quem monta premissas à mão.
    final moat = assumptions.terminalReturnOnCapital;
    final neutro = moat == null && assumptions.neutralTerminalReturn;
    final reinvestimento = moat != null
        ? (gInf / moat).clamp(0.0, 0.95)
        : assumptions.retentionAt(assumptions.projectionYears);
    final fatorFinal = n == 0 ? 1.0 : fatores[n - 1];
    audit.step(
      formulaName: neutro
          ? 'Valor terminal (retorno neutro, ROIC_inf = r_inf)'
          : 'Valor terminal (Gordon com reinvestimento)',
      latex: neutro
          ? r'VT = \frac{L_{N+1}}{r_\infty}'
              r'\quad;\quad VP(VT) = \frac{VT}{\prod_{s=1}^{N}(1+r_s)}'
          : r'VT = \frac{L_{N+1}\,(1 - b_\infty)}{r_\infty - g_\infty}'
              r'\quad;\quad VP(VT) = \frac{VT}{\prod_{s=1}^{N}(1+r_s)}',
      variables: {
        'L_N': n == 0 ? null : _r(outcome.projectedFlows[n - 1]),
        'g_inf (% a.a.)': _r(gInf * 100),
        'r_inf (% a.a.)': _r(rInf * 100),
        'ROIC_inf (% a.a.)': moat == null ? null : _r(moat * 100),
        'N (anos)': assumptions.projectionYears,
      },
      steps: [
        if (neutro)
          'Passo 1: com ROIC_inf = r_inf a álgebra colapsa e o crescimento '
              'perpétuo sai da perpetuidade — VT = L_(N+1) ÷ r_inf, sem spread'
        else
          'Passo 1: spread da perpetuidade → ${_pct(rInf)} − ${_pct(gInf)} = '
              '${_pct(rInf - gInf)}; retenção perpétua = '
              '${_pct(reinvestimento)}',
        'Passo 2: valor terminal no ano ${assumptions.projectionYears} → '
            '${_r(outcome.terminalValue)}',
        'Passo 3: trazido a presente pelo fator acumulado '
            '${_r(fatorFinal, 6)} → ${_r(outcome.discountedTerminalValue)}',
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
