import 'package:equisim/audit/audit_bus.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/audit/logs_page.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shared/ui_kit.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/manual_valuation_page.dart';
import 'package:equisim/presentation/valuation/valuation_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_valuation_store.dart';
import 'populated_state.dart';

/// O valuation confirmado (decisão 150): confirmar na edição grava as
/// premissas e o resultado, o registro aparece na aba Valuation, e vai ao
/// painel de logs — na confirmação e ao carregar o histórico gravado.
void main() {
  late List<AuditEvent> events;

  setUp(() {
    events = [];
    AuditRecorder.attach(events.add);
  });

  tearDown(AuditRecorder.detach);

  /// O botão de confirmar do cartão do resultado, achado pelo rótulo.
  FilledButton confirmButton(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ));

  group('confirmar na edição', () {
    Future<ValuationResult> open(
      WidgetTester tester,
      MemoryValuationStore store, {
      String? userId = 'usuario-1',
      ManualPremises Function(ManualPremises engine)? initial,
    }) async {
      final r = cascadeValuation();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 7000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(userId),
          manualValuationStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: buildFinTheme(isLight: true),
          home: ManualValuationPage(
            result: r,
            initial: initial?.call(r.manual!.enginePremises),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return r;
    }

    Future<void> confirm(WidgetTester tester) async {
      final button = find.text('Confirmar valuation');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('grava as premissas e o resultado, e registra no painel',
        (tester) async {
      final store = MemoryValuationStore();
      final r = await open(
        tester,
        store,
        initial: (m) => m.copyWith(
          growth: m.growth + 0.02,
          discountRate: m.discountRate - 0.01,
        ),
      );
      final m = r.manual!;

      await confirm(tester);

      final saved = store.recordsOf('usuario-1');
      expect(saved, hasLength(1));
      final record = saved.single;
      final p = m.enginePremises.copyWith(
        growth: m.enginePremises.growth + 0.02,
        discountRate: m.enginePremises.discountRate - 0.01,
      );
      expect(record.ticker, r.ticker);
      expect(record.premises.growth, p.growth);
      expect(record.premises.discountRate, p.discountRate);
      expect(
        record.fairValuePerShare,
        m.evaluate(p).unwrap().fairValuePerShare,
      );
      expect(
        record.changedFields,
        [ManualField.growth, ManualField.discountRate],
      );

      // No painel: um evento de cálculo, com o identificador do registro.
      final logged = events.where((e) => e.transactionId == record.id);
      expect(logged, hasLength(1));
      expect(logged.single.outputPayload['status'], 'confirmado');
      expect(AuditBus.isCalculation(logged.single), isTrue);

      // O botão vira o recibo, e não grava de novo as mesmas premissas.
      expect(find.text('Valuation salvo'), findsOneWidget);
      expect(confirmButton(tester, 'Valuation salvo').onPressed, isNull);
      expect(find.textContaining('Valuation salvo:'), findsOneWidget);
    });

    testWidgets('trocar um campo depois de salvar oferece confirmar de novo',
        (tester) async {
      final store = MemoryValuationStore();
      await open(tester, store);
      await confirm(tester);
      expect(find.text('Valuation salvo'), findsOneWidget);

      final rate = find.byKey(const ValueKey('campo-discountRate'));
      await tester.ensureVisible(rate);
      await tester.enterText(rate, '20');
      await tester.pumpAndSettle();

      expect(find.text('Valuation salvo'), findsNothing);
      expect(confirmButton(tester, 'Confirmar valuation').onPressed, isNotNull);
      await confirm(tester);
      expect(store.recordsOf('usuario-1'), hasLength(2));
      expect(store.recordsOf('usuario-1').first.premises.discountRate, 0.20);
    });

    testWidgets('sem os números do motor trocados, salva o preço do motor',
        (tester) async {
      final store = MemoryValuationStore();
      final r = await open(tester, store);
      await confirm(tester);
      final record = store.recordsOf('usuario-1').single;
      expect(record.changedFields, isEmpty);
      expect(record.fairValuePerShare, r.manual!.engineFairValue);
    });

    testWidgets('a gravação recusada avisa, e o painel registra a falha',
        (tester) async {
      final store = MemoryValuationStore()
        ..failOnSave = const ComputationFailure('Servidor fora do ar.');
      await open(tester, store);
      await confirm(tester);

      expect(store.documents, isEmpty);
      expect(find.text('Servidor fora do ar.'), findsOneWidget);
      expect(find.text('Confirmar valuation'), findsOneWidget);
      final failed = events.where((e) => e.outputPayload['status'] == 'falha');
      expect(failed, hasLength(1));
      expect(
        failed.single.endpoint.startsWith(ManualValuationRecord.endpointPrefix),
        isTrue,
      );
    });

    testWidgets('sem usuário autenticado, não grava e diz por quê',
        (tester) async {
      final store = MemoryValuationStore();
      await open(tester, store, userId: null);
      await confirm(tester);
      expect(store.documents, isEmpty);
      expect(find.textContaining('Entre na sua conta'), findsOneWidget);
    });

    testWidgets('a conta recusada não deixa confirmar', (tester) async {
      await open(
        tester,
        MemoryValuationStore(),
        initial: (m) => m.copyWith(baseProfit: -1),
      );
      expect(confirmButton(tester, 'Confirmar valuation').onPressed, isNull);
    });
  });

  group('na aba Valuation', () {
    late ValuationResult r;
    late List<ManualValuationRecord> seed;

    ManualValuationRecord record(
      ValuationResult result,
      String id,
      DateTime savedAt,
      ManualPremises Function(ManualPremises engine) premises,
    ) =>
        ManualValuationRecord.capture(
          id: id,
          ticker: result.ticker,
          engineAsOf: result.asOf,
          valuation: result.manual!,
          premises: premises(result.manual!.enginePremises),
          savedAt: savedAt,
        ).unwrap();

    setUp(() {
      r = cascadeValuation();
      final other = cascadeValuation(firm: false);
      seed = [
        record(r, 'antigo', DateTime(2026, 10, 1, 9, 15), (m) => m),
        record(
          r,
          'recente',
          DateTime(2026, 10, 20, 16, 40),
          (m) => m.copyWith(growth: m.growth + 0.03),
        ),
        // De outro ativo: não aparece no cartão deste.
        record(other, 'outro', DateTime(2026, 10, 21), (m) => m),
      ];
    });

    Future<MemoryValuationStore> openTab(WidgetTester tester) async {
      final store = MemoryValuationStore(seed: seed);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 6000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('usuario-1'),
          manualValuationStoreProvider.overrideWithValue(store),
          marketAnchorsProvider
              .overrideWith((ref) async => MarketAnchors.fallback2026),
          valuationProvider.overrideWith((ref, ticker) async => r),
          isLightModeProvider.overrideWith(() => IsLightMode(initial: true)),
        ],
        child: MaterialApp(
          theme: buildFinTheme(isLight: true),
          home: Scaffold(body: ValuationView(ticker: r.ticker)),
        ),
      ));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('lista os salvos do ativo, do mais recente ao mais antigo',
        (tester) async {
      await openTab(tester);

      expect(find.text('SEUS VALUATIONS SALVOS'), findsOneWidget);
      final recent = seed[1];
      final old = seed[0];
      final recentTitle =
          find.text('${Fmt.money(recent.fairValuePerShare)} por ação');
      final oldTitle = find.text('${Fmt.money(old.fairValuePerShare)} por ação');
      expect(recentTitle, findsOneWidget);
      expect(oldTitle, findsOneWidget);
      expect(
        tester.getTopLeft(recentTitle).dy,
        lessThan(tester.getTopLeft(oldTitle).dy),
      );
      expect(
        find.text('Você trocou: crescimento nos primeiros anos.'),
        findsOneWidget,
      );
      expect(
        find.text('Nenhum campo trocado: o preço do motor naquele dia.'),
        findsOneWidget,
      );
      // O de outro ativo fica de fora.
      expect(find.textContaining('20/10/2026 16:40'), findsOneWidget);
      expect(find.textContaining('21/10/2026'), findsNothing);
    });

    testWidgets('carregar o histórico registra cada salvo no painel',
        (tester) async {
      await openTab(tester);
      // Só os confirmados: montar as avaliações do teste também emite rastro,
      // o da cascata do motor.
      final confirmed = [
        for (final e in events)
          if (e.endpoint.startsWith(ManualValuationRecord.endpointPrefix)) e,
      ];
      // Todos os do usuário, de qualquer ativo, do mais antigo ao mais recente.
      expect(
        [for (final e in confirmed) e.transactionId],
        ['antigo', 'recente', 'outro'],
      );
      expect(confirmed.first.timestamp, seed[0].savedAt);
    });

    testWidgets('abrir mostra as premissas e o resultado guardados',
        (tester) async {
      await openTab(tester);
      final recent = seed[1];
      await tester.tap(
        find.text('${Fmt.money(recent.fairValuePerShare)} por ação'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seus números'), findsOneWidget);
      expect(find.text('O resultado'), findsOneWidget);
      expect(find.text('Valor do patrimônio (VPL)'), findsOneWidget);
      expect(
        find.text(Fmt.money(recent.outcome.fairValuePerShare)),
        findsWidgets,
      );
      expect(find.text('Reabrir na edição'), findsOneWidget);
    });

    testWidgets('reabrir leva à edição com os números salvos', (tester) async {
      await openTab(tester);
      final recent = seed[1];
      await tester.tap(
        find.text('${Fmt.money(recent.fairValuePerShare)} por ação'),
      );
      await tester.pumpAndSettle();
      final reopen = find.text('Reabrir na edição');
      await tester.ensureVisible(reopen);
      await tester.tap(reopen);
      await tester.pumpAndSettle();

      final page = tester.widget<ManualValuationPage>(
        find.byType(ManualValuationPage),
      );
      expect(page.initial!.growth, recent.premises.growth);
      expect(find.text('A conta do motor com os seus números'), findsOneWidget);
    });

    testWidgets('apagar pede confirmação e tira o registro', (tester) async {
      final store = await openTab(tester);
      final old = seed[0];
      await tester.tap(find.text('${Fmt.money(old.fairValuePerShare)} por ação'));
      await tester.pumpAndSettle();
      final delete = find.text('Apagar');
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();

      expect(find.text('Apagar este valuation?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Apagar').last);
      await tester.pumpAndSettle();

      expect(store.documents.containsKey('antigo'), isFalse);
      expect(
        find.text('${Fmt.money(old.fairValuePerShare)} por ação'),
        findsNothing,
      );
    });

    testWidgets('sem salvo do ativo, o cartão não aparece', (tester) async {
      seed = [seed[2]];
      await openTab(tester);
      expect(find.text('SEUS VALUATIONS SALVOS'), findsNothing);
    });
  });

  group('no painel de logs', () {
    setUp(() {
      AuditRecorder.detach();
      AuditBus.instance.clear();
      AuditBus.instance.start(AuditRole.emitter);
    });

    tearDown(AuditBus.instance.clear);

    testWidgets('o valuation confirmado tem selo e filtro próprios',
        (tester) async {
      final r = cascadeValuation();
      final record = ManualValuationRecord.capture(
        id: 'confirmado-1',
        ticker: r.ticker,
        engineAsOf: r.asOf,
        valuation: r.manual!,
        premises: r.manual!.enginePremises.copyWith(perpetualGrowth: 0.05),
        savedAt: DateTime(2026, 10, 22, 15, 4, 5),
      ).unwrap();
      AuditRecorder.emit(record.toAuditEvent());
      // Emitido de novo — como ao recarregar o histórico —, é o mesmo evento.
      AuditRecorder.emit(record.toAuditEvent());
      // E uma ida à rede, que o filtro deixa de fora.
      AuditRecorder.emit(AuditEvent(
        transactionId: 'rede-1',
        timestamp: DateTime(2026, 10, 22, 15, 4, 6),
        endpoint: '/api/quote/WEGE3',
        inputPayload: const {},
        outputPayload: const {'statusCode': 200},
        executionTimeMs: 12,
      ));

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: LogsPage()));
      await tester.pumpAndSettle();

      final endpoint = '/core/valuation/manual/${r.ticker.value}';
      expect(find.text(endpoint), findsOneWidget);
      expect(find.text('valuation confirmado'), findsOneWidget);
      expect(find.text('/api/quote/WEGE3'), findsOneWidget);
      expect(find.textContaining('22/10/2026 15:04:05'), findsOneWidget);

      await tester.tap(find.text('Valuations confirmados'));
      await tester.pumpAndSettle();
      expect(find.text(endpoint), findsOneWidget);
      expect(find.text('/api/quote/WEGE3'), findsNothing);

      await tester.tap(find.text(endpoint));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Preço justo por ação — seus números'),
        findsNWidgets(2),
      );
    });
  });
}
