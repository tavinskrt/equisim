import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Fixtures mínimas para uma cascata que chega ao DCF por FCFF.
List<FundamentalsSnapshot> _history(Ticker ticker) => [
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
    ];

ValuationInputs _inputs(Ticker ticker) => ValuationInputs(
      ticker: ticker,
      asOf: DateTime(2026, 8, 20),
      fundamentals: _history(ticker),
      dividends: const [],
      marketPrice: 20.0,
      capm: const CapmInputs(
        riskFreeRate: 0.105,
        beta: 1.2,
        marketPremium: 0.055,
      ),
      projectionYears: 5,
    );

void main() {
  final ticker = Ticker.parse('PETR4');

  setUp(AuditRecorder.detach);
  tearDown(AuditRecorder.detach);

  group('AuditRecorder', () {
    test('desligado, não constrói transação nenhuma', () {
      expect(AuditRecorder.isActive, isFalse);
      expect(AuditRecorder.begin('/qualquer'), isNull);
    });

    test('ligado, entrega o evento ao consumidor acoplado', () {
      final received = <AuditEvent>[];
      AuditRecorder.attach(received.add);

      final transaction = AuditRecorder.begin(
        '/core/teste',
        inputPayload: {'a': 1},
      );
      transaction!.step(
        formulaName: 'Soma',
        latex: r'c = a + b',
        variables: {'a': 1, 'b': 2},
        steps: const ['Passo 1: 1 + 2 = 3'],
        result: 3,
        unit: 'unidades',
      );
      transaction.complete({'c': 3});

      expect(received, hasLength(1));
      expect(received.single.endpoint, '/core/teste');
      expect(received.single.calculations.single.formulaName, 'Soma');
      expect(received.single.calculations.single.finalValue, 3);
    });

    test('concluir duas vezes não duplica o evento', () {
      final received = <AuditEvent>[];
      AuditRecorder.attach(received.add);

      final transaction = AuditRecorder.begin('/core/teste')!
        ..complete({'ok': true})
        ..complete({'ok': true});
      expect(transaction.transactionId, isNotEmpty);
      expect(received, hasLength(1));
    });
  });

  group('Contrato de serialização', () {
    test('o evento sobrevive à ida e volta em JSON', () {
      final original = AuditEvent(
        transactionId: AuditIds.uuidV4(),
        timestamp: DateTime(2026, 8, 23, 14, 32, 10),
        endpoint: '/core/valuation/PETR4',
        inputPayload: const {'marketPrice': 38.4},
        outputPayload: const {'fairValue': 51.2},
        executionTimeMs: 142,
        calculations: const [
          CalculationTrace(
            formulaName: 'CAPM',
            latexRepresentation: r'K_e = R_f + \beta (R_m - R_f)',
            mappedVariables: {'R_f': 10.5, 'beta': 1.2},
            intermediateSteps: ['Passo 1: 1,2 × 5,5% = 6,6%'],
            finalValue: 17.1,
            unit: '% a.a.',
          ),
        ],
      );

      final restored = AuditEvent.fromJson(original.toJson());

      expect(restored.transactionId, original.transactionId);
      expect(restored.timestamp.toUtc(), original.timestamp.toUtc());
      expect(restored.endpoint, original.endpoint);
      expect(restored.inputPayload, original.inputPayload);
      expect(restored.outputPayload, original.outputPayload);
      expect(restored.executionTimeMs, 142);
      expect(restored.calculations.single.latexRepresentation,
          original.calculations.single.latexRepresentation);
      expect(restored.calculations.single.mappedVariables['beta'], 1.2);
      expect(restored.calculations.single.finalValue, 17.1);
    });

    test('a amostra da mediana sobrevive à ida e volta em JSON', () {
      // O painel roda em outra janela: o que não atravessar o BroadcastChannel
      // simplesmente não existe para quem audita.
      const trace = CalculationTrace(
        formulaName: 'Normalização do fluxo-base',
        latexRepresentation: r'F_0 = \min(\max(F_{obs}, m(1-\tau)), m(1+\tau))',
        finalValue: 0.702,
        unit: r'R$',
        sample: TraceSample(
          title: 'Exercícios da amostra',
          unit: r'R$',
          summary: 0.468,
          lowerBound: 0.234,
          upperBound: 0.702,
          selected: 0.702,
          points: [
            TraceSamplePoint(label: '2021', value: 0.380),
            TraceSamplePoint(label: '2022', value: 0.242),
            TraceSamplePoint(label: '2023', value: 0.468, definesResult: true),
            TraceSamplePoint(label: '2024', value: 0.866),
            TraceSamplePoint(label: '2025', value: 4.445, isObserved: true),
          ],
        ),
      );

      final restored = CalculationTrace.fromJson(trace.toJson());
      final sample = restored.sample!;

      expect([for (final p in sample.points) p.label],
          ['2021', '2022', '2023', '2024', '2025']);
      expect(sample.points[2].definesResult, isTrue);
      expect(sample.points.last.isObserved, isTrue);
      expect(sample.summary, 0.468);
      expect(sample.lowerBound, 0.234);
      expect(sample.upperBound, 0.702);
      expect(sample.selected, 0.702);
    });

    test('rastro sem amostra não carrega a chave no JSON', () {
      const trace = CalculationTrace(
        formulaName: 'CAPM',
        latexRepresentation: r'K_e = R_f + \beta (R_m - R_f)',
      );
      expect(trace.toJson().containsKey('sample'), isFalse);
      expect(CalculationTrace.fromJson(trace.toJson()).sample, isNull);
    });

    test('uuid v4 tem o formato da RFC 4122', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (var i = 0; i < 200; i++) {
        expect(AuditIds.uuidV4(), matches(pattern));
      }
    });
  });

  group('Instrumentação da cascata', () {
    test('sem coletor acoplado, o resultado é idêntico', () {
      final semAuditoria = ValuationCascade.evaluate(_inputs(ticker));

      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);
      final comAuditoria = ValuationCascade.evaluate(_inputs(ticker));
      AuditRecorder.detach();

      expect(semAuditoria.isOk, isTrue);
      expect(comAuditoria.isOk, isTrue);
      // O ponto do teste: instrumentar não pode mover o número. Se mexer, a
      // auditoria estaria documentando um cálculo que não é o de produção.
      expect(
        comAuditoria.unwrap().fairValue.cents,
        semAuditoria.unwrap().fairValue.cents,
      );
      expect(
        comAuditoria.unwrap().discountRate,
        semAuditoria.unwrap().discountRate,
      );
      expect(comAuditoria.unwrap().model, semAuditoria.unwrap().model);
    });

    test('uma avaliação bem-sucedida emite um evento com as fórmulas', () {
      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);

      final result = ValuationCascade.evaluate(_inputs(ticker));

      expect(result.isOk, isTrue);
      expect(capturados, hasLength(1));

      final event = capturados.single;
      expect(event.endpoint, '/core/valuation/PETR4');
      expect(event.outputPayload['status'], 'ok');
      expect(event.inputPayload['ticker'], 'PETR4');

      final nomes = [for (final c in event.calculations) c.formulaName];
      expect(nomes, contains('Custo do capital próprio (CAPM)'));
      expect(
        nomes.any((n) => n.contains('WACC') || n.contains('degeneração')),
        isTrue,
        reason: 'a taxa de desconto precisa estar documentada',
      );
      expect(nomes.any((n) => n.contains('perpetuidade')), isTrue);
      expect(
        nomes.last,
        'Margem de segurança e potencial de valorização',
        reason: 'o veredito fecha a cadeia de raciocínio',
      );
    });

    test('cada fórmula traz símbolos, etapas e resultado', () {
      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);
      ValuationCascade.evaluate(_inputs(ticker));

      for (final trace in capturados.single.calculations) {
        expect(trace.latexRepresentation, isNotEmpty,
            reason: '${trace.formulaName} sem expressão em LaTeX');
        expect(trace.intermediateSteps, isNotEmpty,
            reason: '${trace.formulaName} sem decomposição');
        expect(trace.mappedVariables, isNotEmpty,
            reason: '${trace.formulaName} sem variáveis mapeadas');
        expect(trace.finalValue, isNotNull,
            reason: '${trace.formulaName} sem resultado');
      }
    });

    test('a normalização do fluxo-base publica a amostra da mediana, por ano',
        () {
      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);
      ValuationCascade.evaluate(_inputs(ticker));

      final base = capturados.single.calculations
          .firstWhere((c) => c.formulaName.contains('Normalização'));
      final sample = base.sample!;

      // O histórico vai de 2019 a 2024 e a janela é de cinco: 2019 fica fora.
      expect([for (final p in sample.points) p.label],
          ['2020', '2021', '2022', '2023', '2024']);
      expect(sample.points.last.isObserved, isTrue);
      expect(sample.points.where((p) => p.definesResult), hasLength(1));

      // A mediana publicada é a dos pontos publicados — não um número à parte.
      final valores = [for (final p in sample.points) p.value]..sort();
      expect(sample.summary, closeTo(valores[2], 1e-9));
      expect(sample.lowerBound, closeTo(sample.summary! * 0.5, 1e-9));
      expect(sample.upperBound, closeTo(sample.summary! * 1.5, 1e-9));
      expect(sample.selected, closeTo(base.finalValue!, 1e-6));
    });

    test('o CAPM registrado reproduz o Ke usado no desconto', () {
      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);
      final inputs = _inputs(ticker);
      ValuationCascade.evaluate(inputs);

      final capm = capturados.single.calculations
          .firstWhere((c) => c.formulaName.contains('CAPM'));

      // A conferência que a banca faria à mão, feita no teste.
      final rf = capm.mappedVariables['R_f (% a.a.)']! as num;
      final beta = capm.mappedVariables['beta']! as num;
      final premio = capm.mappedVariables['R_m - R_f (% a.a.)']! as num;

      expect(rf + beta * premio, closeTo(capm.finalValue!, 0.01));
      expect(capm.finalValue! / 100, closeTo(inputs.capm.costOfEquity, 1e-4));
    });

    test('avaliação recusada também emite evento, com o motivo', () {
      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);

      final result = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 8, 20),
        fundamentals: const [],
        dividends: const [],
        marketPrice: 20.0,
        capm: const CapmInputs(
          riskFreeRate: 0.105,
          beta: 1.0,
          marketPremium: 0.055,
        ),
      ));

      expect(result.isErr, isTrue);
      expect(capturados, hasLength(1));
      expect(capturados.single.outputPayload['status'], 'falha');
      expect(capturados.single.outputPayload['motivo'], isA<String>());
    });
  });
}
