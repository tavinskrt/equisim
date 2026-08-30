import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/backtest/backtest_page.dart';
import 'package:equisim/presentation/backtest/backtest_providers.dart';
import 'package:equisim/presentation/export/csv_export.dart';
import 'package:equisim/presentation/goals/goal_page.dart';
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
import 'package:flutter_riverpod/misc.dart';
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
        isLightModeProvider.overrideWith(() => IsLightMode(inicial: isLight)),
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
          message: 'Aviso de teste',
        ),
      ));
      expect(find.text('Aviso de teste'), findsOneWidget);
    });

    testWidgets('MetricTile mostra rótulo, valor e dica', (tester) async {
      await tester.pumpWidget(harness(
        child: const MetricTile(
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

    /// Viewport alto o bastante para conter a tela inteira.
    ///
    /// Necessario desde que a tela virou `CustomScrollView`: o `SliverList` so
    /// infla os cartoes que entram na viewport, entao na altura padrao de teste
    /// (600 px) os cartoes de baixo simplesmente nao existem na arvore. Isso e
    /// o ganho da conversao, nao um defeito -- mas o teste precisa trazer o
    /// alvo para a tela antes de procura-lo.
    void telaAlta(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
    }

    testWidgets('os ativos das duas carteiras aparecem no mesmo cartão',
        (tester) async {
      telaAlta(tester);
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
      telaAlta(tester);
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
      telaAlta(tester);
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
      telaAlta(tester);
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

  group('Backtest — a janela declarada contra o prazo da meta', () {
    void telaAlta(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
    }

    /// Monta a tela com uma meta ja definida, pelo mesmo caminho que o usuario
    /// usaria: o notifier, e nao um override do estado.
    Future<void> comMeta(WidgetTester tester, int months) async {
      late WidgetRef capturado;
      await tester.pumpWidget(harness(
        overrides: [
          comparisonProvider.overrideWith((ref) async => null),
          correlationProvider.overrideWith((ref) async => null),
        ],
        child: Consumer(builder: (context, ref, _) {
          capturado = ref;
          return const BacktestPage();
        }),
      ));
      capturado.read(studyProvider.notifier).setGoal(FinancialGoal(
            initialContribution: const Money(1000000),
            monthlyContribution: const Money(100000),
            months: months,
            targetWealth: const Money(50000000),
          ));
      await tester.pumpAndSettle();
    }

    testWidgets('os dois horizontes aparecem empilhados', (tester) async {
      telaAlta(tester);
      // Sem a segunda linha, "5 anos" nao tem com o que ser comparado: o
      // leitor supoe que a simulacao percorre o plano inteiro.
      await comMeta(tester, 120);

      expect(find.text('Janela'), findsOneWidget);
      expect(find.text('Prazo da meta'), findsOneWidget);
      expect(find.text('10 anos e 0 meses'), findsOneWidget);
    });

    testWidgets('janela menor que o prazo avisa qual fracao cobre',
        (tester) async {
      telaAlta(tester);
      await comMeta(tester, 120);

      expect(
        find.textContaining('cobre 5 dos 10 anos da meta'),
        findsOneWidget,
      );
    });

    testWidgets('prazo acima do teto da fonte diz que nenhuma janela alcanca',
        (tester) async {
      telaAlta(tester);
      await comMeta(tester, 240);

      expect(
        find.textContaining('nenhuma posição do controle alcança o prazo'),
        findsOneWidget,
      );
    });

    testWidgets('janela que cobre o prazo inteiro nao avisa nada',
        (tester) async {
      telaAlta(tester);
      // Aviso que aparece sempre deixa de ser aviso.
      await comMeta(tester, 48);

      expect(find.textContaining('anos da meta'), findsNothing);
    });

    testWidgets('prazo nao multiplo de doze arredonda para cima',
        (tester) async {
      telaAlta(tester);
      // 66 meses sao 5,5 anos: uma janela de cinco NAO os cobre, e truncar
      // para 5 diria exatamente que cobre.
      await comMeta(tester, 66);

      expect(find.textContaining('cobre 5 dos 6 anos da meta'), findsOneWidget);
    });
  });

  group('Backtest — confronto com a meta no período simulado', () {
    void telaAlta(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
    }

    FeasibilityVerdict veredito(double annual) => FeasibilityVerdict(
          level: FeasibilityLevel.demanding,
          requiredAnnualRate: annual,
          anchors: MarketAnchors.fallback2026,
          message: 'meta exigente',
        );

    /// Serie longa o bastante para o XIRR existir.
    ///
    /// Tres pregoes NAO bastam: `moneyWeightedReturn` devolve `null` quando os
    /// fluxos nao sustentam a taxa, e um cenario assim testaria o travessao em
    /// vez do confronto.
    List<double> serieLonga(double passo) =>
        List<double>.generate(120, (i) => 10 + i * passo);

    List<Override> cenario({
      required PortfolioComparison comparison,
      FeasibilityVerdict? verdict,
    }) =>
        [
          comparisonProvider.overrideWith((ref) async => comparison),
          correlationProvider.overrideWith((ref) async => null),
          goalFeasibilityProvider.overrideWith((ref) async => verdict),
        ];

    testWidgets('o exigido e o realizado aparecem no mesmo cartao',
        (tester) async {
      telaAlta(tester);
      // O glossario do XIRR sempre disse que "e este o numero a confrontar
      // com a meta". Este e o cartao em que o confronto acontece.
      await tester.pumpWidget(harness(
        overrides: cenario(
          comparison: comparisonOf(
            principal: outcomeOf('PETR4', serieLonga(0.05)),
          ),
          verdict: veredito(0.184),
        ),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A CARTEIRA FRENTE À META'), findsOneWidget);
      // Os mesmos tres rotulos da aba Meta -- e a mesma grandeza medida de
      // outro jeito, e vocabulario divergente esconderia isso.
      expect(find.text('Exigido'), findsOneWidget);
      expect(find.text('Realizado'), findsOneWidget);
      expect(find.text('Folga'), findsOneWidget);
      // Os tres numeros vem da serie deterministica acima: exigido de 18,40%
      // contra um XIRR de 180,89% deixa 162,5 pontos de folga.
      expect(find.text('18,40%'), findsOneWidget);
      expect(find.text('+162,5 p.p.'), findsOneWidget);
      // DUAS ocorrencias, e e assim que tem de ser: o mesmo XIRR aparece no
      // confronto e no painel de indicadores logo abaixo. Os dois leem
      // `principal.metrics.moneyWeightedReturn`, entao nao ha como divergirem
      // -- que e a propriedade que faltava aos dois "exigido" da aba Meta.
      expect(find.text('+180,89%'), findsNWidgets(2));
    });

    testWidgets('XIRR ausente vira travessao, nao numero inventado',
        (tester) async {
      telaAlta(tester);
      // Tres pregoes nao sustentam a taxa. Admitir a ausencia do dado e a
      // convencao do projeto -- exibir NaN colorido de verde seria pior.
      await tester.pumpWidget(harness(
        overrides: cenario(
          comparison: comparisonOf(
            principal: outcomeOf('PETR4', const [10, 12, 14]),
          ),
          verdict: veredito(0.184),
        ),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A CARTEIRA FRENTE À META'), findsOneWidget);
      expect(find.text('18,40%'), findsOneWidget);
      // Realizado, a Folga que dele deriva, e o XIRR do painel abaixo.
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('sem veredito de viabilidade o cartao nao aparece',
        (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(harness(
        overrides: cenario(
          comparison: comparisonOf(
            principal: outcomeOf('PETR4', const [10, 12, 14]),
          ),
        ),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A CARTEIRA FRENTE À META'), findsNothing);
    });

    testWidgets('taxa exigida nao finita nao rende cartao', (tester) async {
      telaAlta(tester);
      // Meta que o solver nao resolveu ja e explicada na aba Meta; repetir um
      // travessao sem contexto aqui so ocuparia espaco.
      await tester.pumpWidget(harness(
        overrides: cenario(
          comparison: comparisonOf(
            principal: outcomeOf('PETR4', const [10, 12, 14]),
          ),
          verdict: veredito(double.infinity),
        ),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A CARTEIRA FRENTE À META'), findsNothing);
    });

    testWidgets('com Reserva simulada, a alternativa ganha a propria linha',
        (tester) async {
      telaAlta(tester);
      // "E se eu tivesse montado a outra?" e a pergunta que faz a aba existir.
      await tester.pumpWidget(harness(
        overrides: cenario(
          comparison: comparisonOf(
            principal: outcomeOf('PETR4', serieLonga(0.05)),
            reserva: outcomeOf('ITUB4', serieLonga(0.12)),
          ),
          verdict: veredito(0.184),
        ),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('A Reserva, sob os mesmos aportes'),
        findsOneWidget,
      );
    });

    testWidgets('sem Principal simulada nao ha o que confrontar',
        (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(harness(
        overrides: cenario(
          comparison: comparisonOf(
            reserva: outcomeOf('ITUB4', const [10, 18, 25]),
          ),
          verdict: veredito(0.184),
        ),
        child: const BacktestPage(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('A CARTEIRA FRENTE À META'), findsNothing);
    });
  });

  group('Meta — a rentabilidade exigida sai uma vez so', () {
    void telaAlta(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 4000);
      addTearDown(tester.view.reset);
    }

    /// Os dois cartoes da tela, alimentados por providers DIFERENTES e com
    /// taxas de proposito divergentes: 18,40% no veredito contra 18,44% no
    /// alinhamento. E o cenario que a lente `tela` flagrou.
    List<Override> doisCartoes() => [
          goalFeasibilityProvider.overrideWith((ref) async => FeasibilityVerdict(
                level: FeasibilityLevel.demanding,
                requiredAnnualRate: 0.184,
                anchors: MarketAnchors.fallback2026,
                message: 'A meta exige 18,40% ao ano.',
              )),
          goalAlignmentProvider.overrideWith((ref) async => GoalAlignment(
                required: const RequiredReturn(monthly: 0.0142, iterations: 24),
                verdict: FeasibilityVerdict(
                  level: FeasibilityLevel.demanding,
                  requiredAnnualRate: 0.1844,
                  anchors: MarketAnchors.fallback2026,
                  message: 'meta exigente',
                ),
                expectedReturn: 0.1495,
                valuationCoverage: 0.75,
              )),
        ];

    testWidgets('a taxa aparece em um unico bloco numerico', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(
        harness(overrides: doisCartoes(), child: const GoalPage()),
      );
      await tester.pumpAndSettle();

      // O bloco do cartao de viabilidade, que e onde a taxa nasce.
      expect(find.text('18,40%'), findsOneWidget);
      // O do cartao de confronto saiu. Era ele que exibia 18,44% ao lado do
      // outro -- dois providers resolvendo a mesma taxa por conta propria.
      expect(find.text('18,44%'), findsNothing);
    });

    testWidgets('o confronto mantem esperado e folga', (tester) async {
      telaAlta(tester);
      await tester.pumpWidget(
        harness(overrides: doisCartoes(), child: const GoalPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('CARTEIRA FRENTE À META'), findsOneWidget);
      expect(find.text('Esperado da carteira'), findsOneWidget);
      expect(find.text('Folga'), findsOneWidget);
      // Sem a coluna "Exigido" na fila, a folga precisa dizer contra o que se
      // mede -- senao o numero fica solto no cartao.
      expect(find.text('sobre o exigido acima'), findsOneWidget);
    });

    testWidgets('o rotulo e o mesmo que a aba Analise usa', (tester) async {
      telaAlta(tester);
      // Literal de proposito, e nao `Lexico.exigido`: e a palavra que o
      // usuario le, e trocar o valor da constante e mudanca de vocabulario --
      // deve exigir tocar no teste, nao passar despercebida.
      await tester.pumpWidget(
        harness(overrides: doisCartoes(), child: const GoalPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exigido'), findsOneWidget);
      expect(find.text('Rentabilidade exigida'), findsNothing);
    });

    testWidgets('a prosa do veredito ainda cita a taxa -- residuo conhecido',
        (tester) async {
      telaAlta(tester);
      // `FeasibilityVerdict.message` chega do nucleo com o percentual ja
      // embutido na frase. Fechar essa segunda saida depende de uma decisao
      // sobre o `equisim_core`, nao da interface. O teste registra o residuo
      // para que ele nao seja descoberto de novo como se fosse novidade.
      await tester.pumpWidget(
        harness(overrides: doisCartoes(), child: const GoalPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('A meta exige 18,40% ao ano.'), findsOneWidget);
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
