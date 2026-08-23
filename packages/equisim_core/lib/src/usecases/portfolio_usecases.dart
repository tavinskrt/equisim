import '../entities/asset.dart';
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

  /// Retorno anual esperado da carteira, já anualizado pelo horizonte de
  /// convergência e somado ao dividend yield líquido.
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
}

/// Confronta o retorno esperado da carteira com a rentabilidade exigida.
abstract final class EvaluateGoalAlignment {
  static Result<GoalAlignment> call({
    required Portfolio portfolio,
    required FinancialGoal goal,
    required Map<Ticker, ValuationResult> valuations,
    required Map<Ticker, double> netDividendYields,
    required MarketAnchors anchors,
    int horizonMonths = ExpectedReturn.defaultHorizonMonths,
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
      expectedReturn: ExpectedReturn.forPortfolio(
        portfolio: portfolio,
        valuations: valuations,
        netDividendYields: netDividendYields,
        horizonMonths: horizonMonths,
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

    if (cdi.isErr && ibov.isErr) {
      return const Err(InsufficientData(
        'Nem CDI nem Ibovespa puderam ser carregados para calibrar os limiares.',
      ));
    }

    final riskFree = cdi.isOk
        ? cdi.unwrap().annualized()
        : MarketAnchors.fallback2026.riskFreeCagr;

    final market = ibov.isOk
        ? _cagrOf(ibov.unwrap(), range)
        : MarketAnchors.fallback2026.marketCagr;

    // A série do IPCA é mensal, daí os 12 períodos por ano. Sem ela, a
    // inflação de fallback mantém o crescimento perpétuo nominal — o que é
    // menos errado que voltar a misturar real com nominal.
    final inflation = ipca.isOk && ipca.unwrap().rates.isNotEmpty
        ? ipca.unwrap().annualized(periodsPerYear: 12)
        : MarketAnchors.fallback2026.inflationCagr;

    final current = cdi.isOk
        ? _currentRateOf(cdi.unwrap())
        : MarketAnchors.fallback2026.currentRiskFreeRate;

    return Ok(MarketAnchors(
      riskFreeCagr: riskFree,
      currentRiskFreeRate: current,
      marketCagr: market,
      inflationCagr: inflation,
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
    if (series.rates.isEmpty) {
      return MarketAnchors.fallback2026.currentRiskFreeRate;
    }
    final tail = series.rates.length <= currentRateWindowDays
        ? series.rates
        : series.rates.sublist(series.rates.length - currentRateWindowDays);
    return RateSeries(
      dates: series.dates.sublist(series.dates.length - tail.length),
      rates: tail,
    ).annualized();
  }

  static double _cagrOf(PriceSeries series, DateRange range) {
    if (series.points.length < 2) {
      return MarketAnchors.fallback2026.marketCagr;
    }
    final first = series.points.first;
    final last = series.points.last;
    if (first.close <= 0) return MarketAnchors.fallback2026.marketCagr;

    final years = DateRange(first.date, last.date).years;
    if (years <= 0) return MarketAnchors.fallback2026.marketCagr;

    return Returns.annualize(last.close / first.close - 1, years);
  }
}

/// Monta uma carteira a partir de tickers, buscando o perfil de cada ativo.
///
/// O perfil traz a classificação setorial, sem a qual o alerta de concentração
/// — requisito funcional — não teria como operar.
abstract final class BuildPortfolio {
  static Future<Result<Portfolio>> equalWeighted({
    required FundamentalsRepository repository,
    required String id,
    required String name,
    required PortfolioKind kind,
    required List<Ticker> tickers,
  }) async {
    if (tickers.isEmpty) {
      return const Err(InvalidInput('Informe ao menos um ativo.'));
    }
    if (tickers.length > Portfolio.maxAssets) {
      return Err(InvalidInput(
        'Limite de ${Portfolio.maxAssets} ativos por carteira excedido.',
      ));
    }

    final assets = <Asset>[];
    final unresolved = <String>[];

    for (final ticker in tickers) {
      final profile = await repository.profile(ticker);
      profile.fold(
        assets.add,
        (_) {
          // Sem perfil o ativo entra sem setor: participa da carteira, mas não
          // do alerta de concentração. É melhor que descartá-lo em silêncio.
          unresolved.add(ticker.value);
          assets.add(Asset(ticker: ticker, name: ticker.value));
        },
      );
    }

    return Portfolio.equalWeighted(
      id: id,
      name: name,
      kind: kind,
      assets: assets,
    );
  }
}
