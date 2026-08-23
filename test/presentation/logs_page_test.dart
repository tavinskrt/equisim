import 'package:equisim/audit/audit_bus.dart';
import 'package:equisim/presentation/audit/logs_page.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testes do painel de auditoria.
///
/// O caminho exercitado é o de produção inteiro: o cálculo chama
/// [AuditRecorder], o barramento recebe e a tela renderiza. Montar eventos
/// direto na tela testaria a tela contra uma fixture escrita à mão, que é
/// exatamente o tipo de segunda verdade que este painel existe para eliminar.
void main() {
  setUp(() {
    AuditBus.instance.clear();
    AuditBus.instance.start(AuditRole.emitter);
  });

  tearDown(AuditBus.instance.clear);

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsPage()));
    await tester.pumpAndSettle();
  }

  void emitValuation() {
    final ticker = Ticker.parse('PETR4');
    ValuationCascade.evaluate(ValuationInputs(
      ticker: ticker,
      asOf: DateTime(2026, 8, 20),
      fundamentals: [
        for (var year = 2019; year <= 2024; year++)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(year, 12, 31),
            netIncome: 1000.0 * (year - 2018),
            ebit: 1400.0 * (year - 2018),
            ebitda: 1800.0 * (year - 2018),
            incomeBeforeTax: 1300.0 * (year - 2018),
            incomeTaxExpense: 300.0 * (year - 2018),
            interestExpense: 120.0,
            operatingCashFlow: 1600.0 * (year - 2018),
            freeCashFlow: 1200.0 * (year - 2018),
            shortTermDebt: 400.0,
            longTermDebt: 1600.0,
            cash: 300.0,
            sharesOutstanding: 1000.0,
            marketCap: 20000.0,
            bookValuePerShare: 8.0,
            enterpriseToEbitda: 6.0,
          ),
      ],
      dividends: const [],
      marketPrice: 20.0,
      capm: const CapmInputs(
        riskFreeRate: 0.105,
        beta: 1.2,
        marketPremium: 0.055,
      ),
    ));
  }

  testWidgets('a janela paralela sobe com a rota /logs da plataforma',
      (tester) async {
    // Reproduz o arranque real: a guia é aberta em '#/logs', e é isso que a
    // plataforma entrega como rota inicial. Sem fixar a raiz, o Navigator
    // procurava '/logs' na tabela de rotas do painel — que não existe — e caía
    // em `onUnknownRoute`, nulo, lançando no console a cada abertura.
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/logs';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(const AuditLogsApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Painel de Auditoria de Cálculos'), findsOneWidget);
  });

  testWidgets('sem execuções, o painel explica o que está esperando',
      (tester) async {
    await pumpPanel(tester);

    expect(find.text('Painel de Auditoria de Cálculos'), findsOneWidget);
    expect(find.text('Aguardando execuções'), findsOneWidget);
    expect(find.text('Limpar Logs'), findsOneWidget);
    expect(find.text('Pausar Auto-scroll'), findsOneWidget);
    expect(find.text('Exportar Auditoria (JSON)'), findsOneWidget);
  });

  testWidgets('um cálculo real aparece na lista em tempo real', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Aguardando execuções'), findsOneWidget);

    emitValuation();
    await tester.pumpAndSettle();

    expect(find.text('Aguardando execuções'), findsNothing);
    expect(find.text('/core/valuation/PETR4'), findsOneWidget);
  });

  testWidgets('o item expande nas três seções pedidas', (tester) async {
    emitValuation();
    await pumpPanel(tester);

    await tester.tap(find.text('/core/valuation/PETR4'));
    await tester.pumpAndSettle();

    expect(find.text('SEÇÃO A'), findsOneWidget);
    expect(find.text('Requisição & Resposta'), findsOneWidget);
    expect(find.text('SEÇÃO B'), findsOneWidget);
    expect(find.text('Fórmulas e Equações'), findsOneWidget);
    expect(find.text('SEÇÃO C'), findsOneWidget);
    expect(
      find.text('Substituição de Variáveis e Decomposição'),
      findsOneWidget,
    );

    // Seção A: os dois payloads do contrato.
    expect(find.text('inputPayload'), findsOneWidget);
    expect(find.text('outputPayload'), findsOneWidget);

    // Seção B: as fórmulas chegam ao renderizador de TeX, não a um texto solto.
    expect(find.byType(Math), findsWidgets);

    // Seções B e C compartilham a numeração, então o nome aparece duas vezes:
    // uma sobre a fórmula renderizada, outra sobre a tabela de substituição.
    expect(
      find.textContaining('Custo do capital próprio (CAPM)'),
      findsNWidgets(2),
    );
    expect(find.text('R_f (% a.a.)'), findsWidgets);
  });

  testWidgets('o filtro separa cálculo de rede', (tester) async {
    AuditRecorder.emit(AuditEvent(
      transactionId: AuditIds.uuidV4(),
      timestamp: DateTime.now(),
      endpoint: '/v2/stocks/historical',
      inputPayload: const {'method': 'GET'},
      outputPayload: const {'statusCode': 200},
      executionTimeMs: 3460,
    ));
    emitValuation();
    await pumpPanel(tester);

    expect(find.text('/v2/stocks/historical'), findsOneWidget);
    expect(find.text('/core/valuation/PETR4'), findsOneWidget);

    await tester.tap(find.text('Cálculos'));
    await tester.pumpAndSettle();
    expect(find.text('/v2/stocks/historical'), findsNothing);
    expect(find.text('/core/valuation/PETR4'), findsOneWidget);

    await tester.tap(find.text('Rede'));
    await tester.pumpAndSettle();
    expect(find.text('/v2/stocks/historical'), findsOneWidget);
    expect(find.text('/core/valuation/PETR4'), findsNothing);
  });

  testWidgets('limpar esvazia a lista', (tester) async {
    emitValuation();
    await pumpPanel(tester);
    expect(find.text('/core/valuation/PETR4'), findsOneWidget);

    await tester.tap(find.text('Limpar Logs'));
    await tester.pumpAndSettle();

    expect(find.text('Aguardando execuções'), findsOneWidget);
  });

  testWidgets('o auto-scroll pode ser pausado e retomado', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Pausar Auto-scroll'));
    await tester.pumpAndSettle();
    expect(find.text('Retomar Auto-scroll'), findsOneWidget);

    await tester.tap(find.text('Retomar Auto-scroll'));
    await tester.pumpAndSettle();
    expect(find.text('Pausar Auto-scroll'), findsOneWidget);
  });
}
