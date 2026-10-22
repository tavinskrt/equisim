import 'package:equisim/data/repositories/portfolio_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/backtest/backtest_providers.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shared/ui_kit.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim/presentation/study/study_page.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_valuation_store.dart';
import 'populated_state.dart';

/// A tela Estudo mostra o valuation do usuário (decisão 151): quando o mais
/// recente que ele confirmou para o ativo discorda do motor, o preço justo e o
/// potencial da linha são os dele, contra a cotação de hoje, marcados "seu".
void main() {
  late ValuationResult r;

  setUpAll(() => r = cascadeValuation());

  ManualValuationRecord record(
    String id,
    DateTime savedAt,
    ManualPremises Function(ManualPremises engine) premises,
  ) =>
      ManualValuationRecord.capture(
        id: id,
        ticker: r.ticker,
        engineAsOf: r.asOf,
        valuation: r.manual!,
        premises: premises(r.manual!.enginePremises),
        savedAt: savedAt,
      ).unwrap();

  Future<void> openStudy(
    WidgetTester tester,
    List<ManualValuationRecord> seed, {
    bool toPrincipal = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      currentUserIdProvider.overrideWithValue('usuario-1'),
      manualValuationStoreProvider
          .overrideWithValue(MemoryValuationStore(seed: seed)),
      marketAnchorsProvider
          .overrideWith((ref) async => MarketAnchors.fallback2026),
      savedStudiesProvider.overrideWith((ref) async => const <PortfolioStudy>[]),
      valuationProvider.overrideWith((ref, ticker) async => r),
      portfolioValuationsProvider.overrideWith(
        (ref) async => const <Ticker, ValuationResult>{},
      ),
      portfolioSignalsProvider.overrideWith(
        (ref) async => const <Ticker, TransversalSignals>{},
      ),
      comparisonProvider.overrideWith((ref) async => null),
      correlationProvider.overrideWith((ref) async => null),
      goalAlignmentProvider.overrideWith((ref) async => null),
      goalFeasibilityProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
    container.read(isLightModeProvider.notifier).setValue(true);
    container
        .read(studyProvider.notifier)
        .addAsset(assetOf(r.ticker.value, 'industria'), toPrincipal: toPrincipal);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFinTheme(isLight: true),
        home: const Scaffold(body: StudyPage()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String upsideOf(double fair) =>
      Fmt.percent(fair / r.marketPrice.reais - 1, decimals: 0, signed: true);

  testWidgets('sem valuation salvo, a linha é a do motor', (tester) async {
    await openStudy(tester, const []);
    expect(find.text('justo ${Fmt.money(r.fairValue.reais)}'), findsOneWidget);
    expect(find.textContaining('seu R\$'), findsNothing);
  });

  testWidgets('com o seu valuation divergente, a linha mostra o seu preço',
      (tester) async {
    final mine = record(
      'meu',
      DateTime(2026, 10, 22, 10),
      (m) => m.copyWith(growth: m.growth + 0.03),
    );
    expect(mine.changedFields, isNotEmpty);
    await openStudy(tester, [mine]);

    expect(find.text('seu ${Fmt.money(mine.fairValuePerShare)}'), findsOneWidget);
    expect(find.text('justo ${Fmt.money(r.fairValue.reais)}'), findsNothing);
    // O potencial é o do preço do usuário contra a cotação de hoje.
    expect(find.text(upsideOf(mine.fairValuePerShare)), findsOneWidget);
  });

  testWidgets('também na Reserva', (tester) async {
    final mine = record(
      'meu',
      DateTime(2026, 10, 22, 10),
      (m) => m.copyWith(discountRate: m.discountRate + 0.02),
    );
    await openStudy(tester, [mine], toPrincipal: false);
    expect(find.text('seu ${Fmt.money(mine.fairValuePerShare)}'), findsOneWidget);
  });

  testWidgets('confirmar depois os números do motor devolve o preço do motor',
      (tester) async {
    final old = record(
      'antigo',
      DateTime(2026, 10, 1),
      (m) => m.copyWith(growth: m.growth + 0.03),
    );
    final agreed = record('concordo', DateTime(2026, 10, 22), (m) => m);
    await openStudy(tester, [old, agreed]);

    expect(find.text('justo ${Fmt.money(r.fairValue.reais)}'), findsOneWidget);
    expect(find.textContaining('seu R\$'), findsNothing);
  });
}
