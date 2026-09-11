import 'dart:math' as math;

import '../entities/financial_goal.dart';
import '../entities/portfolio.dart';
import '../entities/price_series.dart';
import '../entities/valuation.dart';
import '../failures/failure.dart';
import '../failures/result.dart';
import '../repositories/repositories.dart';
import '../services/goal/feasibility.dart';
import '../services/goal/required_return.dart';
import '../services/metrics/returns.dart';
import '../services/portfolio/expected_return.dart';
import '../services/portfolio/sector_concentration.dart';
import '../value_objects/date_range.dart';
import '../value_objects/ticker.dart';

/// Resultado de mover um ativo entre as carteiras.
///
/// Devolve as duas carteiras já reequiponderadas e as consequências imediatas
/// da troca, para a interface repintar sem recalcular nada por conta própria.
class RebalanceOutcome {
  final Portfolio principal;
  final Portfolio reserva;
  final ConcentrationReport concentration;

  const RebalanceOutcome({
    required this.principal,
    required this.reserva,
    required this.concentration,
  });
}

/// Move um ativo entre Principal e Reserva.
///
/// **Síncrono de propósito.** O recálculo custa microssegundos (medido: 0,024 ms
/// para um backtest inteiro de 5 anos), então o arrastar-e-soltar atualiza a
/// cada quadro, sem `Future`, sem *debounce* e sem estado de carregamento.
abstract final class SwapAssetBetweenPortfolios {
  static Result<RebalanceOutcome> call({
    required Portfolio principal,
    required Portfolio reserva,
    required Ticker ticker,
    required bool toPrincipal,
  }) {
    final source = toPrincipal ? reserva : principal;
    final target = toPrincipal ? principal : reserva;

    final entry = source.entries[ticker];
    if (entry == null) {
      return Err(InvalidInput(
        '${ticker.value} não está na carteira ${source.kind.label}.',
      ));
    }
    if (target.entries.containsKey(ticker)) {
      return Err(InvalidInput(
        '${ticker.value} já está na carteira ${target.kind.label}.',
      ));
    }

    final added = target.add(entry.asset);
    if (added.isErr) return Err(added.failureOrNull!);

    final removed = source.remove(ticker);
    if (removed.isErr) return Err(removed.failureOrNull!);

    final newPrincipal = toPrincipal ? added.unwrap() : removed.unwrap();
    final newReserva = toPrincipal ? removed.unwrap() : added.unwrap();

    return Ok(RebalanceOutcome(
      principal: newPrincipal,
      reserva: newReserva,
      concentration: SectorConcentration.analyze(newPrincipal),
    ));
  }
}

/// Situação da carteira frente à meta patrimonial.
class GoalAlignment {
  final RequiredReturn required;
  final FeasibilityVerdict verdict;

  /// Retorno anual esperado da carteira, pelo **estimador transversal**:
  /// `Ke_i + z(potencial) · prêmio`, ponderado pelos pesos.
  ///
  /// **A âncora é o custo de capital próprio de cada ativo, e não o CDI**
  /// (decisão 58): ancorar na renda fixa dava ao ativo mediano da seção um
  /// retorno esperado sem prêmio de risco algum.
  ///
  /// **Não é mais a anualização do potencial.** Aquela leitura era uma
  /// afirmação de nível, e o nível do potencial carrega todo o conservadorismo
  /// que a estrutura a termo e o terminal neutro impõem ao custo de capital
  /// brasileiro: com potencial mediano de −39,4% no universo elegível, ela
  /// devolvia retorno esperado negativo para a carteira mediana e nenhuma meta
  /// era alcançável, por construção. O que a avaliação sustenta com firmeza é a
  /// **ordenação** entre ativos, e é só ela que este número usa — ver
  /// `ExpectedReturn.crossSection`.
  ///
  /// Não há parcela de provento: o modelo não distribui.
  final double expectedReturn;

  /// Fração do peso da carteira que possui avaliação disponível.
  final double valuationCoverage;

  const GoalAlignment({
    required this.required,
    required this.verdict,
    required this.expectedReturn,
    required this.valuationCoverage,
  });

  /// Diferença entre o esperado e o exigido, em pontos percentuais ao ano.
  double get gap => (expectedReturn - required.annual) * 100;

  bool get meetsGoal => expectedReturn >= required.annual;

  /// Cobertura baixa torna o retorno esperado pouco representativo.
  bool get coverageIsWeak => valuationCoverage < 0.6;

  // Aqui existiu `yieldToCloseGap`, o *dividend yield* que fecharia a lacuna.
  // Ele foi **removido pela decisão 62**, e o motivo é que a premissa que o
  // justificava deixou de valer três funções adiante.
  //
  // A justificativa era: "[expectedReturn] é retorno de preço e nada mais — o
  // trabalho não modela provento desde a decisão 23 —, logo a carteira que
  // paga bem aparece em déficit que não existe". Isso era verdade enquanto o
  // esperado fosse `CDI + z·prêmio`. Pela **decisão 58** ele passou a ser
  // `Ke + z·prêmio`, com `Ke = Rf + β·prêmio`, que é o retorno **total**
  // esperado pelo CAPM — dividendo incluído, por definição do modelo.
  //
  // Somar um yield a um retorno total é contar o provento duas vezes, e no
  // sentido que faz a carteira parecer melhor do que é. A lacuna sem
  // remendo é [gap], e ela já está certa.
}

/// Confronta o retorno esperado da carteira com a rentabilidade exigida.
abstract final class EvaluateGoalAlignment {
  /// - [crossSection]: potenciais que definem mediana e escala do escore. Passe
  ///   o universo avaliado sempre que ele estiver à mão; omitido, a seção é a
  ///   própria carteira, e o escore de cada ativo passa a medir desconto
  ///   contra os próprios companheiros em vez de contra o mercado — limitação
  ///   declarada em `ExpectedReturn.crossSection`, não escondida.
  static Result<GoalAlignment> call({
    required Portfolio portfolio,
    required FinancialGoal goal,
    required Map<Ticker, ValuationResult> valuations,
    required MarketAnchors anchors,
    Iterable<double>? crossSection,
  }) {
    final solved = RequiredReturnSolver.solve(goal);
    if (solved.isErr) return Err(solved.failureOrNull!);

    final required = solved.unwrap();
    return Ok(GoalAlignment(
      required: required,
      verdict: GoalFeasibility.assess(
        required: required,
        anchors: anchors,
        goal: goal,
      ),
      expectedReturn: ExpectedReturn.forPortfolioCrossSectional(
        portfolio: portfolio,
        valuations: valuations,
        spotRiskFree: anchors.currentRiskFreeRate,
        reference: crossSection,
      ),
      valuationCoverage: ExpectedReturn.coverage(
        portfolio: portfolio,
        valuations: valuations,
      ),
    ));
  }
}

/// Deriva as âncoras de mercado a partir das séries observadas.
///
/// Os limiares de viabilidade da meta **não são constantes de código**: saem do
/// CDI e do Ibovespa na janela consultada. Assim se atualizam sozinhos conforme
/// o mercado muda, e a mensagem ao usuário pode citar o número concreto em vez
/// de um limite arbitrário.
abstract final class ResolveMarketAnchors {
  static const int defaultWindowYears = 10;

  static Future<Result<MarketAnchors>> call({
    required MacroRepository macro,
    required BenchmarkRepository benchmark,
    DateTime? asOf,
    int windowYears = defaultWindowYears,
  }) async {
    final end = asOf ?? DateTime.now();
    final range = DateRange(
      DateTime(end.year - windowYears, end.month, end.day),
      end,
    );

    final cdi = await macro.riskFreeDaily(range);
    final ibov = await benchmark.ibovespa(range);
    final ipca = await macro.inflationMonthly(range);
    final ibc = await macro.activityIndexMonthly(range);

    if (cdi.isErr && ibov.isErr) {
      return const Err(InsufficientData(
        'Nem CDI nem Ibovespa puderam ser carregados para calibrar os limiares.',
      ));
    }

    final riskFree = cdi.isOk
        ? cdi.unwrap().annualized()
        : MarketAnchors.fallback2026.riskFreeCagr;

    final market = ibov.isOk
        ? _cagrOf(ibov.unwrap())
        : MarketAnchors.fallback2026.marketCagr;

    // A série do IPCA é mensal, daí os 12 períodos por ano. Sem ela, a
    // inflação de fallback mantém o crescimento perpétuo nominal — o que é
    // menos errado que voltar a misturar real com nominal.
    final inflation = ipca.isOk && ipca.unwrap().rates.isNotEmpty
        ? ipca.unwrap().annualized()
        : MarketAnchors.fallback2026.inflationCagr;

    final current = cdi.isOk
        ? _currentRateOf(cdi.unwrap())
        : MarketAnchors.fallback2026.currentRiskFreeRate;

    // Parcela real do teto da perpetuidade, medida em vez de arbitrada. Sem a
    // série, cai no valor observado em 10 anos, declarado como fallback.
    final realGrowth = ibc.isOk
        ? _activityCagrOf(ibc.unwrap(), windowYears) ??
            MarketAnchors.fallback2026.realEconomyGrowth
        : MarketAnchors.fallback2026.realEconomyGrowth;

    return Ok(MarketAnchors(
      riskFreeCagr: riskFree,
      currentRiskFreeRate: current,
      marketCagr: market,
      inflationCagr: inflation,
      realEconomyGrowth: realGrowth,
      observedYears: windowYears,
    ));
  }

  /// Trimestre mais recente do CDI, anualizado.
  ///
  /// É a taxa livre de risco que entra no desconto, e ela precisa ser a de
  /// **hoje**: um DCF compara o fluxo futuro da empresa com o que o investidor
  /// obteria agora sem risco, não com a média da década. Um trimestre é longo
  /// o bastante para não repicar num único dia atípico e curto o bastante para
  /// acompanhar o ciclo de juros.
  static const int currentRateWindowDays = 63;

  static double _currentRateOf(RateSeries series) {
    if (series.isEmpty) {
      return MarketAnchors.fallback2026.currentRiskFreeRate;
    }
    return series.tail(currentRateWindowDays).annualized();
  }

  /// Pregões de cada ponta que formam a média do CAGR do índice.
  ///
  /// **Um trimestre, pela mesma razão de [currentRateWindowDays]:** longo o
  /// bastante para não repicar num único dia atípico e curto o bastante para
  /// não comer o horizonte. Numa janela de cinco anos são 5% da amostra em
  /// cada ponta.
  static const int indexEndWindowDays = 63;

  /// CAGR do índice entre as **médias das duas pontas**, medido de centro a
  /// centro.
  ///
  /// A janela usada é a da própria série, não a solicitada: se o índice começa
  /// depois do início pedido, anualizar sobre o prazo pedido subestimaria o
  /// retorno.
  ///
  /// **Ponta a ponta herdava o ruído de dois dias** (decisão 60). O índice de
  /// atividade já era medido por média móvel nas pontas — *"um CAGR entre dois
  /// pontos isolados herdaria inteiramente o ruído deles"* —, e o Ibovespa, que
  /// oscila muito mais, era o que não recebia o mesmo tratamento. Medido em
  /// 11/09/2026 na janela de dez anos: **12,57% ponta a ponta contra 11,06%**
  /// com trimestre nas pontas.
  ///
  /// **De centro a centro, e não de ponta a ponta**, como em
  /// [_activityCagrOf]: com as pontas mediadas, o crescimento medido é o que
  /// vai do centro da primeira janela ao centro da última, e usar as datas
  /// extremas alongaria o prazo e diluiria o CAGR.
  ///
  /// Devolve o CAGR de [MarketAnchors.fallback2026] quando a série é curta
  /// demais, tem preço inicial não positivo ou colapsa num único dia.
  static double _cagrOf(PriceSeries series) {
    final p = series.points;
    if (p.length < 2) return MarketAnchors.fallback2026.marketCagr;

    // Com série curta demais para duas pontas inteiras, cada ponta é metade do
    // que há — nunca sobrepostas, para que os dois centros sejam distintos.
    final n = p.length ~/ 2 < indexEndWindowDays
        ? p.length ~/ 2
        : indexEndWindowDays;
    if (n < 1) return MarketAnchors.fallback2026.marketCagr;

    double media(Iterable<PricePoint> xs) {
      var soma = 0.0;
      var quantos = 0;
      for (final x in xs) {
        soma += x.close;
        quantos++;
      }
      return quantos == 0 ? 0 : soma / quantos;
    }

    final inicio = media(p.take(n));
    final fim = media(p.skip(p.length - n));
    if (inicio <= 0 || fim <= 0) {
      return MarketAnchors.fallback2026.marketCagr;
    }

    final centroInicial = p[(n - 1) ~/ 2].date;
    final centroFinal = p[p.length - 1 - (n - 1) ~/ 2].date;
    final years = DateRange(centroInicial, centroFinal).years;
    if (years <= 0) return MarketAnchors.fallback2026.marketCagr;

    return Returns.annualize(fim / inicio - 1, years);
  }

  /// Crescimento real anual a partir do índice de atividade.
  ///
  /// O IBC-Br é **índice de nível**, não taxa: [RateSeries.annualized]
  /// compõe-o como se cada ponto fosse um retorno e devolveria absurdo. Aqui se
  /// tomam razões entre pontas, o que também torna irrelevante o fato de o
  /// datasource dividir tudo por 100.
  ///
  /// **Média móvel de 12 meses nas duas pontas.** Mesmo dessazonalizado, o
  /// índice tem ruído mensal, e um CAGR entre dois pontos isolados herdaria
  /// inteiramente o ruído deles — o mesmo defeito que a regressão sobre CAGR
  /// ponta a ponta tem no crescimento de fundamentos.
  ///
  /// Devolve `null` quando não há 12 meses em cada ponta ou quando a janela
  /// efetiva é curta demais, para que o chamador decida o fallback.
  static double? _activityCagrOf(RateSeries series, int windowYears) {
    const janela = 12;
    final v = series.rates;
    if (v.length < janela * 2) return null;

    double media(int fim) {
      var soma = 0.0;
      for (var i = fim - janela + 1; i <= fim; i++) {
        soma += v[i];
      }
      return soma / janela;
    }

    final inicio = media(janela - 1);
    final fim = media(v.length - 1);
    if (inicio <= 0 || fim <= 0) return null;

    // Anos entre os centros das duas médias móveis, não entre as pontas cruas.
    final meses = v.length - janela;
    final anos = meses / 12.0;
    if (anos < 1) return null;

    final g = math.pow(fim / inicio, 1 / anos).toDouble() - 1;
    return g.isFinite ? g : null;
  }
}
