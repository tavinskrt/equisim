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
        for (var year = 2016; year <= 2025; year++)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(year, 12, 31),
            netIncome: 1000.0 * (year - 2015),
            ebit: 1400.0 * (year - 2015),
            ebitda: 1800.0 * (year - 2015),
            incomeBeforeTax: 1300.0 * (year - 2015),
            incomeTaxExpense: 300.0 * (year - 2015),
            interestExpense: 120.0,
            operatingCashFlow: 1600.0 * (year - 2015),
            freeCashFlow: 1200.0 * (year - 2015),
            shortTermDebt: 400.0,
            longTermDebt: 1600.0,
            cash: 300.0,
            nopat: 1000.0 * (year - 2015),
            sharesOutstanding: 1000.0,
            sharesOutstandingAsOf: 1000.0,
            marketCap: 20000.0,
            bookValuePerShare: 8.0 * (year - 2015),
            enterpriseToEbitda: 6.0,
          ),
      ],
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

  testWidgets(
      'a amostra de retorno mostra os exercícios que formaram a mediana do ciclo',
      (tester) async {
    // Retorno comportado até 2023 e um exercício deprimido em 2024 — a forma do
    // caso VALE3, que a decisão 25 passou a tratar por convergência ao ciclo em
    // vez de winsorização do fluxo absoluto.
    final ticker = Ticker.parse('SAPR11');
    const lucro = {
      2016: 700.0,
      2017: 750.0,
      2018: 820.0,
      2019: 900.0,
      2020: 1000.0,
      2021: 1100.0,
      2022: 1150.0,
      2023: 1200.0,
      2024: 1250.0,
      2025: 400.0,
    };
    ValuationCascade.evaluate(ValuationInputs(
      ticker: ticker,
      asOf: DateTime(2026, 8, 20),
      fundamentals: [
        for (final entry in lucro.entries)
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(entry.key, 12, 31),
            netIncome: entry.value,
            nopat: entry.value,
            ebit: entry.value * 1.4,
            ebitda: entry.value * 1.8,
            incomeBeforeTax: entry.value * 1.3,
            incomeTaxExpense: entry.value * 0.3,
            interestExpense: 120.0,
            operatingCashFlow: entry.value,
            freeCashFlow: entry.value,
            shortTermDebt: 400.0,
            longTermDebt: 1600.0,
            cash: 300.0,
            sharesOutstanding: 1000.0,
            sharesOutstandingAsOf: 1000.0,
            marketCap: 20000.0,
            // Patrimônio crescendo devagar: é o denominador do retorno, e é o
            // que faz 2025 destoar do ciclo.
            bookValuePerShare: 8.0 + (entry.key - 2016) * 0.5,
            enterpriseToEbitda: 6.0,
          ),
      ],
      marketPrice: 20.0,
      capm: const CapmInputs(
        riskFreeRate: 0.105,
        beta: 1.2,
        marketPremium: 0.055,
      ),
    ));

    // Superfície alta: o roteamento por porta acrescentou um passo antes da
    // base, e o gráfico da amostra passou a cair abaixo da dobra padrão.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPanel(tester);
    await tester.tap(find.text('/core/valuation/SAPR11'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // O gráfico da amostra e sua tabela de apoio.
    expect(find.textContaining('RETORNO SOBRE O CAPITAL INVESTIDO'),
        findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    // Um exercício central em amostra ímpar, dois em par — a paridade depende
    // de quantos exercícios a janela do ciclo alcançou.
    expect(find.text('define a mediana do ciclo'), findsAtLeastNWidgets(1));

    // **Duas amostras, porque duas vias foram percorridas.** O ativo tem
    // dívida líquida consumindo quase todo o valor da firma, a pós-condição da
    // ponte dispara e a avaliação migra para o fluxo do acionista — e o painel
    // mostra a base de cada uma, com o retorno sobre o capital investido na
    // primeira e sobre o patrimônio na segunda. É o que o rastro deve mostrar:
    // a via descartada é parte de como o número foi obtido.
    expect(find.textContaining('RETORNO SOBRE O PATRIMÔNIO'), findsOneWidget);
    expect(find.text('observado · normalizado'), findsNWidgets(2));
    expect(
      find.textContaining('migra para o fluxo do acionista'),
      findsAtLeastNWidgets(1),
      reason: 'a migração precisa estar declarada junto das duas amostras',
    );

    // Em tela estreita a etiqueta desce para a segunda linha em vez de
    // disputar espaço com o número: numa única linha ela espremia o valor até
    // zero e estourava a lateral.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'nenhuma faixa de estouro em 320 px, no painel inteiro');

    final etiqueta = find.text('define a mediana do ciclo').first;
    expect(etiqueta, findsOneWidget);
    expect(
      tester.getBottomRight(etiqueta).dx,
      lessThanOrEqualTo(320.0),
      reason: 'a etiqueta precisa caber na largura da tela',
    );
  });

  testWidgets('o cabeçalho cabe em 320 px, também nos rótulos alternativos',
      (tester) async {
    // O painel também é aberto empilhado sobre a aplicação, onde não há
    // segunda janela. O cabeçalho é uma faixa de rótulos longos em português
    // — "Exportar Auditoria (JSON)", "Entrega local (mesma janela)" —, e cada
    // um deles chegou a estourar a lateral com a listra de erro do Flutter.
    //
    // Cobre o papel de emissor. O de inspetor troca uma pílula e acrescenta
    // "Recarregar histórico" — mais curto que os rótulos já exercitados, e nas
    // mesmas duas classes (`_StatusPill` e `_ConsoleButton`). Não é testado
    // aqui porque `AuditBus` é singleton e só `dispose()` devolve o papel:
    // dentro da suíte, todo teste roda como emissor.
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPanel(tester);
    expect(tester.takeException(), isNull, reason: 'estado inicial');

    // Os rótulos que trocam de texto ao serem acionados: o estado alternativo
    // é mais longo que o inicial em dois deles.
    await tester.tap(find.text('Pausar Auto-scroll'));
    await tester.pumpAndSettle();
    expect(find.text('Retomar Auto-scroll'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'auto-scroll pausado');

    await tester.tap(find.text('Modo claro'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'tema claro');
  });

  testWidgets('o cabeçalho cede metade da tela à lista sob fonte ampliada',
      (tester) async {
    // Com a fonte do sistema em 2,0 — o teto do Android —, o cabeçalho quer
    // 696 px numa tela de 568. Sem o limite, a `Column` da página estourava
    // por baixo e a lista de eventos, que é o conteúdo do painel, sumia.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2.0),
        ),
        child: MaterialApp(home: LogsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final cabecalho = tester.getSize(find.byType(SingleChildScrollView).first);
    expect(cabecalho.height, lessThanOrEqualTo(284.0),
        reason: 'metade de 568; acima disso o cabeçalho rola por dentro');

    // E o que sobra continua sendo do conteúdo.
    expect(find.text('Aguardando execuções'), findsOneWidget);
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
