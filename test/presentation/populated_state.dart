/// Estado POPULADO para montar as telas cheias.
///
/// POR QUE ESTE ARQUIVO EXISTE. A matriz de `overflow_test.dart` monta as telas
/// com os providers remotos devolvendo `null` ou vazio, e o proprio arquivo
/// documenta o limite: `_ComparisonBody`, `_MetricsCard`,
/// `_PerAssetCard` e os graficos nao chegam a ser construidos. A suite verifica
/// o esqueleto, nao a tela cheia -- que e justamente onde vivem as colunas
/// numericas densas.
///
/// Para captura de tela isso deixa de ser limitacao e vira defeito: uma imagem
/// de tela vazia nao so e inutil para critica de direcao visual, e ENGANOSA --
/// leva a concluir que a interface esta limpa quando o conteudo nunca apareceu.
///
/// As fabricas de backtest vieram de `ui_test.dart`, onde ja existiam e ja
/// eram exercitadas. Foram movidas para ca em vez de copiadas: duas copias de
/// uma fabrica de dominio divergem, e a que diverge em silencio e a do teste.
library;

import 'package:equisim/data/repositories/portfolio_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/backtest/backtest_providers.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
// `Override` mora aqui, nao no barril principal do Riverpod 3.
import 'package:flutter_riverpod/misc.dart';

// ---------------------------------------------------------------------------
// Blocos basicos
// ---------------------------------------------------------------------------

Asset assetOf(String symbol, [String sector = 'financeiro']) => Asset(
      ticker: Ticker.parse(symbol),
      name: symbol,
      sector: Sector.fromKey(sector, label: sector),
    );

final _range = DateRange(DateTime(2024, 1, 1), DateTime(2024, 12, 31));

/// Serie diaria sintetica: um pregao por dia util a partir de [start].
PriceSeries seriesOf(String symbol, DateTime start, List<double> closes) {
  final points = <PricePoint>[];
  var date = start;
  for (final close in closes) {
    while (date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday) {
      date = date.add(const Duration(days: 1));
    }
    points.add(PricePoint(date: date, close: close));
    date = date.add(const Duration(days: 1));
  }
  return PriceSeries(ticker: Ticker.parse(symbol), points: points);
}

/// Backtest de uma carteira de um ativo so, para alimentar a tela.
BacktestOutcome outcomeOf(String symbol, List<double> closes) {
  final start = DateTime(2024, 1, 1);
  final portfolio = Portfolio.equalWeighted(
    id: symbol,
    name: symbol,
    kind: PortfolioKind.principal,
    assets: [assetOf(symbol)],
  ).unwrap();

  return PortfolioBacktest.run(
    portfolio: portfolio,
    prices: {Ticker.parse(symbol): seriesOf(symbol, start, closes)},
    plan: const ContributionPlan(initial: Money(100000), monthly: Money.zero),
    range: DateRange(start, DateTime(2024, 12, 31)),
  ).unwrap();
}

PortfolioComparison comparisonOf({
  BacktestOutcome? principal,
  BacktestOutcome? reserva,
}) =>
    PortfolioComparison(
      window: _range,
      requestedWindow: _range,
      principal: principal,
      reserva: reserva,
    );

// ---------------------------------------------------------------------------
// Fabricas novas -- o que faltava para a tela encher
// ---------------------------------------------------------------------------

/// Serie de 120 pregoes com tendencia e ondulacao.
///
/// Nao e ruido aleatorio: captura de tela precisa ser DETERMINISTICA, senao
/// duas execucoes produzem imagens diferentes e o `git diff` de PNG vira
/// ruido. A onda existe para o grafico ter forma -- uma reta nao exercita
/// rotulo de eixo nem legenda.
/// Opera em CENTAVOS INTEIROS e converte na saida, em vez de arredondar por
/// ida e volta em String. A diferenca importa menos aqui do que num caminho
/// monetario de verdade, mas o gate local reprova a forma -- e com razao: o
/// projeto inteiro segue a convencao de centavo inteiro, e uma fabrica de teste
/// que a contorna ensina a contorna-la.
List<double> _curva({required double inicio, required double fim, int n = 120}) {
  final inicioCents = (inicio * 100).round();
  final fimCents = (fim * 100).round();
  final passo = (fimCents - inicioCents) / (n - 1);
  return List<double>.generate(n, (i) {
    final tendencia = inicioCents + passo * i;
    final onda = (i % 17) * 11 - (i % 7) * 19;
    return (tendencia.round() + onda) / 100.0;
  });
}

/// Avaliacao com os tres cenarios discretos preenchidos.
ValuationResult valuationOf(
  String symbol, {
  double justo = 42.80,
  double mercado = 33.15,
}) =>
    ValuationResult(
      ticker: Ticker.parse(symbol),
      asOf: DateTime(2024, 12, 31),
      model: ValuationModel.dcfEarnings,
      fairValue: Money.fromReais(justo),
      marketPrice: Money.fromReais(mercado),
      discountRate: 0.132,
      marginOfSafety: 0.20,
      mode: ScenarioMode.discrete,
      discreteScenarios: {
        ScenarioBand.bear: Money.fromReais(justo * 0.72),
        ScenarioBand.base: Money.fromReais(justo),
        ScenarioBand.bull: Money.fromReais(justo * 1.31),
      },
      warnings: const [],
    );

/// Veredito de meta no nivel `demanding`: o unico que exercita ao mesmo tempo
/// o alerta na interface e a exibicao dos numeros, sem bloquear a tela.
FeasibilityVerdict feasibilidade() => FeasibilityVerdict(
      level: FeasibilityLevel.demanding,
      reason: FeasibilityReason.aboveMarket,
      requiredAnnualRate: 0.1840,
      anchors: MarketAnchors.fallback2026,
    );

GoalAlignment alinhamento() => GoalAlignment(
      required: const RequiredReturn(
        monthly: 0.0142,
        iterations: 24,
        usedBisection: false,
      ),
      verdict: feasibilidade(),
      expectedReturn: 0.1495,
      valuationCoverage: 0.75,
    );

// ---------------------------------------------------------------------------
// O conjunto completo
// ---------------------------------------------------------------------------

/// Meta de demonstracao: prazo de dez anos contra a janela padrao de cinco.
///
/// O descasamento e DELIBERADO. A aba Analise so declara a relacao entre os
/// dois horizontes quando eles diferem, e uma meta de cinco anos deixaria essa
/// declaracao fora da captura -- que e justamente onde ela precisa ser
/// conferida.
const metaDemo = FinancialGoal.unvalidated(
  initialContribution: Money(1000000),
  monthlyContribution: Money(100000),
  months: 120,
  targetWealth: Money(50000000),
);

/// Tickers da carteira de demonstracao, com setores distintos para que a
/// dispersao e a barra de concentracao tenham mais de uma cor.
const carteiraDemo = <(String, String)>[
  ('PETR4', 'energia'),
  ('VALE3', 'materiais'),
  ('ITUB4', 'financeiro'),
  ('WEGE3', 'industrial'),
];

/// Todos os providers remotos, preenchidos.
///
/// E a diferenca entre este arquivo e o `_overrides()` de `overflow_test.dart`:
/// la tudo devolve vazio de proposito, para isolar o esqueleto; aqui tudo
/// devolve conteudo, para a tela encher.
List<Override> populatedOverrides() {
  final tickers = [for (final (s, _) in carteiraDemo) Ticker.parse(s)];

  return <Override>[
    currentUserIdProvider.overrideWithValue('captura'),
    universeProvider.overrideWith((ref) async => tickers),
    riskFreeRateProvider.overrideWith((ref) async => 0.094),
    marketAnchorsProvider.overrideWith((ref) async => MarketAnchors.fallback2026),
    savedStudiesProvider.overrideWith((ref) async => const <PortfolioStudy>[]),

    valuationProvider.overrideWith(
      (ref, ticker) async => valuationOf(ticker.value),
    ),
    portfolioValuationsProvider.overrideWith(
      (ref) async => {for (final t in tickers) t: valuationOf(t.value)},
    ),

    comparisonProvider.overrideWith(
      (ref) async => comparisonOf(
        principal: outcomeOf('PETR4', _curva(inicio: 32.10, fim: 41.75)),
        reserva: outcomeOf('ITUB4', _curva(inicio: 28.40, fim: 33.90)),
      ),
    ),
    correlationProvider.overrideWith((ref) async => null),

    goalAlignmentProvider.overrideWith((ref) async => alinhamento()),
    goalFeasibilityProvider.overrideWith((ref) async => feasibilidade()),
  ];
}
