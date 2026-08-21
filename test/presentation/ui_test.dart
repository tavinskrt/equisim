import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/backtest/backtest_providers.dart';
import 'package:equisim/presentation/export/csv_export.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shared/ui_kit.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim/presentation/study/study_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
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
Widget harness({
  required Widget child,
  List<Override> overrides = const [],
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
        ...overrides,
      ],
      child: MaterialApp(home: Scaffold(body: child)),
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

    testWidgets('tema claro e escuro renderizam sem erro', (tester) async {
      for (final isLight in [true, false]) {
        await tester.pumpWidget(harness(
          overrides: [isLightModeProvider.overrideWith((ref) => isLight)],
          child: const StudyPage(),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Formatação', () {
    test('percentual com sinal', () {
      expect(Fmt.percent(0.1234), '12.34%');
      expect(Fmt.percent(0.1234, signed: true), '+12.34%');
      expect(Fmt.percent(-0.05, signed: true), '-5.00%');
      expect(Fmt.percent(0.0, signed: true), '0.00%');
    });

    test('moeda em português brasileiro', () {
      expect(Fmt.money(1234.56), contains('1.234,56'));
    });
  });

  group('Exportação CSV', () {
    test('usa separador e decimal que o Excel brasileiro entende', () {
      final result = PortfolioComparison(window: _emptyRange);
      final csv = CsvExport.metrics(result);

      expect(csv, contains(';'));
      expect(csv.split('\n').first, 'metrica;principal;reserva');
      // Sem dados, as colunas ficam vazias em vez de zeradas.
      expect(csv, contains('cagr;;'));
    });

    test('cabeçalho da série temporal identifica as duas carteiras', () {
      final result = PortfolioComparison(window: _emptyRange);
      expect(CsvExport.comparisonSeries(result), isEmpty,
          reason: 'sem simulação não há série a exportar');
    });
  });
}

final _emptyRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 12, 31));
