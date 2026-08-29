import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/backtest/backtest_page.dart';
import 'package:equisim/presentation/backtest/backtest_providers.dart';
import 'package:equisim/presentation/export/csv_export.dart';
import 'package:equisim/presentation/shared/charts.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shared/ui_kit.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim/presentation/study/study_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Asset assetOf(String symbol, [String sector = 'financeiro']) => Asset(
      ticker: Ticker.parse(symbol),
      name: symbol,
      sector: Sector.fromKey(sector, label: sector),
    );

/// Monta a tela isolando a rede: avaliações e universo são fornecidos
/// diretamente, de modo que o teste exercita a interface, não a API.
/// [isLight] alimenta ao mesmo tempo o provider legado e o `ThemeData`.
/// Manter os dois em sincronia importa: as extensões `FinColors`/
/// `FinTypography` vêm do tema, e um harness sem elas faz `context.fin`
/// estourar em qualquer widget que use `FinAmount`.
Widget harness({
  required Widget child,
  List<Override> overrides = const [],
  bool isLight = false,
}) =>
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('usuario-1'),
        universeProvider.overrideWith((ref) async => const <Ticker>[]),
        riskFreeRateProvider.overrideWith((ref) async => 0.094),
        marketAnchorsProvider
            .overrideWith((ref) async => MarketAnchors.fallback2026),
        netDividendYieldsProvider
            .overrideWith((ref) async => const <Ticker, double>{}),
        portfolioValuationsProvider
            .overrideWith((ref) async => const <Ticker, ValuationResult>{}),
        valuationProvider.overrideWith((ref, ticker) async => null),
        isLightModeProvider.overrideWith((ref) => isLight),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildFinTheme(isLight: isLight),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('StudyPage — dupla carteira', () {
    testWidgets('mostra estado vazio nas duas colunas', (tester) async {
      await tester.pumpWidget(harness(child: const StudyPage()));
      await tester.pump();

      expect(find.text('CARTEIRA PRINCIPAL'), findsOneWidget);
      expect(find.text('CARTEIRA RESERVA'), findsOneWidget);
      expect(find.text('Nenhum ativo'), findsNWidgets(2));
    });

    testWidgets('ativo adicionado aparece com seu peso', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(harness(
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const StudyPage();
          },
        ),
      ));
      await tester.pump();

      capturedRef
          .read(studyProvider.notifier)
          .addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      await tester.pump();

      expect(find.text('PETR4'), findsOneWidget);
      expect(find.text('100.00%'), findsOneWidget);
    });

    testWidgets('dois ativos dividem o peso igualmente', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(harness(
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const StudyPage();
          },
        ),
      ));
      await tester.pump();

      final notifier = capturedRef.read(studyProvider.notifier);
      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      notifier.addAsset(assetOf('VALE3', 'materiais'), toPrincipal: true);
      await tester.pump();

      expect(find.text('50.00%'), findsNWidgets(2));
    });

    testWidgets('alerta de concentração aparece e não bloqueia', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(harness(
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const StudyPage();
          },
        ),
      ));
      await tester.pump();

      final notifier = capturedRef.read(studyProvider.notifier);
      notifier.addAsset(assetOf('ITUB4'), toPrincipal: true);
      await tester.pump();
      expect(find.textContaining('Concentração setorial'), findsNothing);

      notifier.addAsset(assetOf('BBAS3'), toPrincipal: true);
      await tester.pump();

      expect(find.textContaining('Concentração setorial'), findsOneWidget);
      expect(find.textContaining('não um impedimento'), findsOneWidget);
      // O ativo entrou mesmo assim.
      expect(
        capturedRef.read(studyProvider).study.principal.length,
        2,
      );
    });

    testWidgets('arrastar um ativo o move para a outra carteira',
        (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(harness(
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const StudyPage();
          },
        ),
      ));
      await tester.pump();

      capturedRef
          .read(studyProvider.notifier)
          .addAsset(assetOf('PETR4', 'energia'), toPrincipal: false);
      await tester.pump();

      expect(capturedRef.read(studyProvider).study.reserva.length, 1);
      expect(capturedRef.read(studyProvider).study.principal.length, 0);

      // Arrasta da Reserva para a Principal.
      final origin = tester.getCenter(find.text('PETR4'));
      final target = tester.getCenter(find.text('CARTEIRA PRINCIPAL'));
      final gesture = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(capturedRef.read(studyProvider).study.principal.length, 1);
      expect(capturedRef.read(studyProvider).study.reserva.length, 0);
    });
  });

  group('Componentes de interface', () {
    testWidgets('NoticeBanner exibe a mensagem', (tester) async {
      await tester.pumpWidget(harness(
        child: const NoticeBanner(
          isLight: false,
          message: 'Aviso de teste',
        ),
      ));
      expect(find.text('Aviso de teste'), findsOneWidget);
    });

    testWidgets('MetricTile mostra rótulo, valor e dica', (tester) async {
      await tester.pumpWidget(harness(
        child: const MetricTile(
          isLight: false,
          label: 'Sharpe',
          value: '1,25',
          hint: 'vs CDI',
        ),
      ));
      expect(find.text('Sharpe'), findsOneWidget);
      expect(find.text('1,25'), findsOneWidget);
      expect(find.text('vs CDI'), findsOneWidget);
    });

    testWidgets('HintIcon abre o glossário e explica cada indicador',
        (tester) async {
      await tester.pumpWidget(harness(
        child: const HintIcon(
          isLight: false,
          title: 'Indicadores da Carteira Principal',
          intro: 'Todos se referem à janela simulada.',
          entries: [HintEntry('TWR', 'Neutraliza o cronograma de aportes.')],
        ),
      ));

      expect(find.text('TWR'), findsNothing);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Todos se referem à janela simulada.'), findsOneWidget);
      expect(find.text('TWR'), findsOneWidget);
      expect(
        find.text('Neutraliza o cronograma de aportes.'),
        findsOneWidget,
      );
    });

    testWidgets('tema claro e escuro renderizam sem erro', (tester) async {
      for (final isLight in [true, false]) {
        await tester.pumpWidget(harness(
          isLight: isLight,
          child: const StudyPage(),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Gráficos', () {
    testWidgets('dispersão com um único ponto não degenera os eixos',
        (tester) async {
      // Regressão: com um ponto só, o `fl_chart` fazia minX == maxX e
      // minY == maxY, e a conversão de valor para pixel dividia por zero.
      await tester.pumpWidget(harness(
        child: const RiskReturnScatter(
          isLight: false,
          points: [
            (
              label: 'Principal',
              risk: 18.4,
              ret: 12.7,
              color: Colors.green,
              highlight: true,
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final chart = tester.widget<ScatterChart>(find.byType(ScatterChart));
      expect(chart.data.maxX, greaterThan(chart.data.minX));
      expect(chart.data.maxY, greaterThan(chart.data.minY));
      expect(chart.data.minX, greaterThanOrEqualTo(0));
    });

    testWidgets('dispersão desenha um ponto por ativo e rotula todos',
        (tester) async {
      await tester.pumpWidget(harness(
        child: const RiskReturnScatter(
          isLight: false,
          points: [
            (
              label: 'PETR4',
              risk: 32.0,
              ret: 21.0,
              color: Colors.grey,
              highlight: false,
            ),
            (
              label: 'ABEV3',
              risk: 21.0,
              ret: 4.0,
              color: Colors.grey,
              highlight: false,
            ),
            (
              label: 'Principal',
              risk: 18.0,
              ret: 13.0,
              color: Colors.green,
              highlight: true,
            ),
          ],
        ),
      ));
      await tester.pump();

      final chart = tester.widget<ScatterChart>(find.byType(ScatterChart));
      expect(chart.data.scatterSpots, hasLength(3));
      expect(chart.data.scatterLabelSettings.showLabel, isTrue);
      expect(
        chart.data.scatterLabelSettings.getLabelFunction(
          0,
          chart.data.scatterSpots.first,
        ),
        'PETR4',
      );
    });

    testWidgets('curvas de tamanhos diferentes alinham pela data',
        (tester) async {
      // A Principal começa um mês depois da Reserva. Desenhadas por índice,
      // as duas ficavam encostadas na esquerda e a mais curta parecia acabar
      // antes do fim do período.
      final calendario = [
        for (var i = 0; i < 6; i++) DateTime(2024, 1 + i, 1),
      ];

      await tester.pumpWidget(harness(
        child: Base100Chart(
          isLight: false,
          dates: calendario,
          series: [
            ChartSeries(
              label: 'Reserva',
              values: const [100, 101, 102, 103, 104, 105],
              dates: calendario,
              color: Colors.blue,
            ),
            ChartSeries(
              label: 'Principal',
              values: const [100, 99, 98, 97, 96],
              dates: calendario.skip(1).toList(),
              color: Colors.green,
            ),
          ],
        ),
      ));
      await tester.pump();

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final reserva = chart.data.lineBarsData[0].spots;
      final principal = chart.data.lineBarsData[1].spots;

      expect(reserva.first.x, 0);
      expect(reserva.last.x, 5);
      // A curva mais curta começa deslocada e termina na mesma borda.
      expect(principal.first.x, 1);
      expect(principal.last.x, 5);
    });
  });


  group('Formatação', () {
    test('percentual com sinal usa virgula decimal, como manda o pt_BR', () {
      // `toStringAsFixed` ignora locale e emitia ponto: `12.34%`. O teste
      // antigo travava esse defeito, enquanto o de moeda logo abaixo ja exigia
      // virgula -- as duas convencoes conviviam no mesmo arquivo.
      expect(Fmt.percent(0.1234), '12,34%');
      expect(Fmt.percent(0.1234, signed: true), '+12,34%');
      expect(Fmt.percent(-0.05, signed: true), '-5,00%');
      expect(Fmt.percent(0.0, signed: true), '0,00%');
    });

    test('percentual grande recebe separador de milhar', () {
      expect(Fmt.percent(12.3456), '1.234,56%');
    });

    test('valor nao finito vira travessao em vez de NaN na tela', () {
      // NumberFormat nao lanca: devolve 'NaN' e '∞'. Exibir isso ao
      // investidor e pior que admitir a ausencia do dado.
      expect(Fmt.percent(double.nan), '—');
      expect(Fmt.percent(double.infinity), '—');
      expect(Fmt.ratio(double.nan), '—');
    });

    test('numero adimensional tambem segue pt_BR', () {
      expect(Fmt.ratio(0.43), '0,43');
      expect(Fmt.ratio(1234.5, decimals: 1), '1.234,5');
    });

    test('moeda em português brasileiro', () {
      expect(Fmt.money(1234.56), contains('1.234,56'));
    });
  });

  group('Exportação CSV', () {
    test('usa separador e decimal que o Excel brasileiro entende', () {
      final result = PortfolioComparison(
        window: _emptyRange,
        requestedWindow: _emptyRange,
      );
      final csv = CsvExport.metrics(result);

      expect(csv, contains(';'));
      expect(csv.split('\n').first, 'metrica;principal;reserva');
      // Sem dados, as colunas ficam vazias em vez de zeradas.
      expect(csv, contains('cagr;;'));
    });

    test('cabeçalho da série temporal identifica as duas carteiras', () {
      final result = PortfolioComparison(
        window: _emptyRange,
        requestedWindow: _emptyRange,
      );
      expect(CsvExport.comparisonSeries(result), isEmpty,
          reason: 'sem simulação não há série a exportar');
    });
  });
  group('Backtest — desempenho das duas carteiras', () {
    /// Sobrescreve a comparação inteira: o alvo aqui é a montagem da tela,
    /// não o motor de simulação, que tem os próprios testes no domínio.
    List<Override> withComparison(PortfolioComparison comparison) => [
          comparisonProvider.overrideWith((ref) async => comparison),
          correlationProvider.overrideWith((ref) async => null),
        ];

    testWidgets('os ativos das duas carteiras aparecem no mesmo cartão',
        (tester) async {
      // A troca de ativo se decide comparando o pior detido com o melhor
      // candidato: sem a Reserva no cartão, metade da decisão fica invisível.
      await tester.pumpWidget(harness(
        overrides: withComparison(comparisonOf(
          principal: outcomeOf('PETR4', const [10, 12, 14]),
          reserva: outcomeOf('ITUB4', const [10, 18, 25]),
        )),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('DESEMPENHO POR ATIVO'), findsOneWidget);
      // Um selo por carteira, dentro do cartão.
      expect(find.text('PRINCIPAL'), findsOneWidget);
      expect(find.text('RESERVA'), findsOneWidget);
      expect(find.text('PETR4'), findsOneWidget);
      expect(find.text('ITUB4'), findsOneWidget);
    });

    testWidgets('sem Reserva, o cartão mostra só a Principal', (tester) async {
      await tester.pumpWidget(harness(
        overrides: withComparison(comparisonOf(
          principal: outcomeOf('PETR4', const [10, 12, 14]),
        )),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('DESEMPENHO POR ATIVO'), findsOneWidget);
      expect(find.text('PETR4'), findsOneWidget);
      expect(find.text('RESERVA'), findsNothing);
    });

    testWidgets('cada carteira tem o próprio cartão de proventos',
        (tester) async {
      await tester.pumpWidget(harness(
        overrides: withComparison(comparisonOf(
          principal: outcomeOf('PETR4', const [10, 12, 14]),
          reserva: outcomeOf('ITUB4', const [10, 18, 25]),
        )),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PROVENTOS NO PERÍODO — PRINCIPAL'), findsOneWidget);
      expect(find.text('PROVENTOS NO PERÍODO — RESERVA'), findsOneWidget);
    });

    testWidgets('os cabeçalhos das carteiras trazem o ícone de ajuda',
        (tester) async {
      await tester.pumpWidget(harness(
        overrides: withComparison(comparisonOf(
          principal: outcomeOf('PETR4', const [10, 12, 14]),
          reserva: outcomeOf('ITUB4', const [10, 18, 25]),
        )),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      // Um em cada cartão de métricas, mais o de desempenho por ativo.
      expect(find.byType(HintIcon), findsNWidgets(3));
    });
  });

  group('Dispersão risco × retorno', () {
    test('marca cada ativo pela carteira de origem', () async {
      final today = DateTime.now();
      final start = DateTime(today.year - 2, today.month, today.day);
      final closes = List<double>.generate(300, (i) => 10 + i * 0.02);

      final container = ProviderContainer(overrides: [
        riskFreeRateProvider.overrideWith((ref) async => 0.10),
        priceRepositoryProvider.overrideWithValue(FakePriceRepository({
          for (final symbol in ['PETR4', 'VALE3', 'ITUB4'])
            Ticker.parse(symbol): seriesOf(symbol, start, closes),
        })),
        dividendRepositoryProvider.overrideWithValue(FakeDividendRepository()),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      notifier.addAsset(assetOf('VALE3', 'materiais'), toPrincipal: true);
      notifier.addAsset(assetOf('ITUB4'), toPrincipal: false);
      notifier.setGoal(const FinancialGoal(
        initialContribution: Money(100000),
        monthlyContribution: Money(50000),
        months: 120,
        targetWealth: Money(10000000),
      ));

      final result = await container.read(comparisonProvider.future);
      final kinds = {
        for (final point in result!.riskReturn) point.label: point.kind,
      };

      expect(kinds['PETR4'], RiskReturnKind.principalAsset);
      expect(kinds['VALE3'], RiskReturnKind.principalAsset);
      // Antes, o candidato da Reserva simplesmente não era desenhado.
      expect(kinds['ITUB4'], RiskReturnKind.reservaAsset);
      expect(kinds['Principal'], RiskReturnKind.principal);
      expect(kinds['Reserva'], RiskReturnKind.reserva);
    });
  });

}

final _emptyRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 12, 31));

/// Série diária sintética: um pregão por dia útil a partir de [start].
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

/// Backtest de uma carteira de um ativo só, para alimentar a tela.
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
    dividends: const {},
    plan: const ContributionPlan(initial: Money(100000), monthly: Money.zero),
    range: DateRange(start, DateTime(2024, 12, 31)),
  ).unwrap();
}

PortfolioComparison comparisonOf({
  BacktestOutcome? principal,
  BacktestOutcome? reserva,
}) =>
    PortfolioComparison(
      window: _emptyRange,
      requestedWindow: _emptyRange,
      principal: principal,
      reserva: reserva,
    );

/// Cotações servidas de memória, sem rede.
class FakePriceRepository implements PriceRepository {
  final Map<Ticker, PriceSeries> series;

  FakePriceRepository(this.series);

  @override
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range) async {
    final found = series[ticker];
    return found == null
        ? Err(InsufficientData('Sem série para ${ticker.value}.'))
        : Ok(found);
  }

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  ) async =>
      Ok({
        for (final ticker in tickers)
          if (series[ticker] != null) ticker: series[ticker]!,
      });

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(
    Ticker ticker,
    DateRange range,
  ) =>
      daily(ticker, range);
}

/// Carteira sem proventos: isola o efeito de preço na dispersão.
class FakeDividendRepository implements DividendRepository {
  @override
  Future<Result<List<DividendEvent>>> history(Ticker ticker) async =>
      const Ok([]);

  @override
  Future<Result<Map<Ticker, List<DividendEvent>>>> historyBatch(
    List<Ticker> tickers,
  ) async =>
      const Ok({});

  @override
  Future<Result<double>> publishedTrailingYield(Ticker ticker) async =>
      const Ok(0.0);
}
