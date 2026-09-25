// O rastro que o painel de logs recebe e exporta é íntegro (item D4).
//
// «Íntegro» quer dizer quatro coisas, cada uma com o seu teste:
//
// 1. **serializável sempre** — `NaN`, infinito e objetos que o JSON não
//    representa não derrubam a exportação;
// 2. **completo** — o evento de uma avaliação reproduz o resultado que a tela
//    mostra: o diagnóstico inteiro, a volatilidade da faixa, a triangulação e
//    as ressalvas;
// 3. **toda saída emite** — sucesso, recusa, exceção e falha de preparo deixam
//    evento, e nenhuma deixa dois;
// 4. **ida e volta sem perda** — o que sai no JSON volta ao painel da outra
//    janela com os mesmos valores.
import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');

FundamentalsSnapshot _ano(int y, double escala) => FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * escala,
      ebit: 1800 * escala,
      ebitda: 2400 * escala,
      netIncome: 900 * escala,
      incomeBeforeTax: 1300 * escala,
      incomeTaxExpense: -400 * escala,
      interestExpense: 400,
      earningsPerShare: 0.9 * escala,
      cash: 200,
      shortTermDebt: 1000,
      longTermDebt: 3000,
      totalStockholderEquity: 6000 * escala,
      bookValuePerShare: 6.0 * escala,
      operatingCashFlow: 2000 * escala,
      nopat: 1188 * escala,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    );

List<FundamentalsSnapshot> _serie() {
  final out = <FundamentalsSnapshot>[];
  var escala = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(_ano(2025 - i, escala));
    escala *= 1.05;
  }
  return out;
}

ValuationInputs _insumos({List<String> notas = const []}) => ValuationInputs(
      ticker: _ticker,
      asOf: DateTime(2026, 9, 9),
      fundamentals: _serie(),
      marketPrice: 12.0,
      capm: const CapmInputs(
          riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
      declaredTerminalRiskFreeRate: 0.094,
      peerMultiples: PeerMultipleSet(byKind: const {
        MultipleKind.precoLucro: PeerMultiple(median: 9, peers: 8, group: 'g'),
        MultipleKind.precoPatrimonio:
            PeerMultiple(median: 1.4, peers: 8, group: 'g'),
        MultipleKind.firmaEbitda:
            PeerMultiple(median: 6, peers: 8, group: 'g'),
      }, asOf: DateTime(2026, 9, 1)),
      contextNotes: notas,
    );

/// Captura os eventos emitidos durante [corpo].
List<AuditEvent> _eventos(void Function() corpo) {
  final out = <AuditEvent>[];
  AuditRecorder.attach(out.add);
  try {
    corpo();
  } finally {
    AuditRecorder.detach();
  }
  return out;
}

void main() {
  group('serializável sempre', () {
    test('valores que o JSON não representa viram texto, e o resto passa', () {
      final safe = AuditJson.safe({
        'nan': double.nan,
        'inf': double.infinity,
        'menosInf': double.negativeInfinity,
        'data': DateTime.utc(2026, 9, 24),
        'enum': CashTiming.fimDeAno,
        'objeto': Ticker.parse('PETR4'),
        'lista': [1, 2.5, double.nan],
        1: 'chave numérica',
        'finito': 0.1234,
        'inteiro': 7,
      })! as Map<String, dynamic>;
      expect(() => jsonEncode(safe), returnsNormally);
      expect(safe['nan'], 'NaN');
      expect(safe['inf'], 'Infinity');
      expect(safe['menosInf'], '-Infinity');
      expect(safe['data'], '2026-09-24T00:00:00.000Z');
      expect(safe['enum'], 'fimDeAno');
      expect(safe['objeto'], 'PETR4');
      expect(safe['lista'], [1, 2.5, 'NaN']);
      expect(safe['1'], 'chave numérica');
      expect(safe['finito'], 0.1234);
      expect(safe['inteiro'], 7);
    });

    test('um passo degenerado não derruba a exportação, e volta como NaN', () {
      final eventos = _eventos(() {
        AuditRecorder.begin('/core/teste', inputPayload: {'x': double.nan})!
          ..step(
            formulaName: 'conta degenerada',
            latex: r'x = 0/0',
            variables: {'a': double.nan, 'b': double.infinity},
            result: double.nan,
          )
          ..complete({'saida': double.negativeInfinity});
      });
      final texto = jsonEncode(eventos.single.toJson());
      final volta = AuditEvent.fromJson(
          jsonDecode(texto) as Map<String, dynamic>);
      expect(volta.calculations.single.finalValue!.isNaN, isTrue);
      expect(volta.calculations.single.mappedVariables['b'], 'Infinity');
      expect(volta.inputPayload['x'], 'NaN');
      expect(volta.outputPayload['saida'], '-Infinity');
    });

    test('o JSON de um rastro sem valor degenerado não muda um byte', () {
      final e = _eventos(() => ValuationCascade.evaluate(_insumos())).single;
      final cru = jsonEncode({
        'entrada': e.inputPayload,
        'saida': e.outputPayload,
        'calculos': [for (final c in e.calculations) c.toJson()],
      });
      final j = e.toJson();
      final seguro = jsonEncode({
        'entrada': j['inputPayload'],
        'saida': j['outputPayload'],
        'calculos': j['calculations'],
      });
      expect(seguro, cru);
    });
  });

  group('completo', () {
    test('o evento reproduz o resultado que a tela mostra', () {
      late Result<ValuationResult> r;
      final e = _eventos(() {
        r = ValuationCascade.evaluate(
            _insumos(notas: const ['CVM defasada', 'curva de 12/09']));
      }).single;
      final v = r.unwrap();
      final saida = jsonDecode(jsonEncode(e.toJson()))['outputPayload']
          as Map<String, dynamic>;

      expect(saida['status'], 'ok');
      expect(saida['fairValue'], v.fairValue.reais);
      expect(saida['marketPrice'], v.marketPrice.reais);
      expect((saida['discountRate'] as num).toDouble(),
          closeTo(v.discountRate, 1e-6));
      expect(saida['warnings'], v.warnings,
          reason: 'a tela e o arquivo leem as mesmas ressalvas');
      expect(v.warnings, containsAll(['CVM defasada', 'curva de 12/09']));
      expect(saida.containsKey('priceVolatility'), isTrue);

      final d = saida['diagnostics'] as Map<String, dynamic>;
      expect(
          d.keys.toSet(),
          containsAll(<String>{
            'terminalShare', 'equityShare', 'baseFactor', 'growthIdentified',
            'moatApplied', 'caveats', 'terminalRetainedSpread', 'growthRate',
            'terminalReturnOnCapital', 'firmTaxRate', 'returnOnCapital',
            'terminalDiscountRate', 'terminalCostOfEquity', 'costOfEquity',
            'terminalExcessShare', 'impliedTerminalReturn',
            'terminalEquityShare', 'growthPath', 'retentionPath',
          }),
          reason: 'os dezenove campos do diagnóstico, e não cinco');
      expect((d['costOfEquity'] as num).toDouble(),
          closeTo(v.diagnostics!.costOfEquity, 1e-6));
      expect((d['growthPath'] as List).length,
          v.diagnostics!.growthPath.length);

      final tri = v.triangulation;
      if (tri != null) {
        final t = saida['triangulation'] as Map<String, dynamic>;
        expect((t['readings'] as List).length, tri.readings.length);
      }
    });

    test('a entrada diz com que insumo a cascata rodou', () {
      final e = _eventos(() => ValuationCascade.evaluate(
            _insumos(notas: const ['nota']).withOverrides(
                lane: ValuationLane.firm, cashTiming: CashTiming.fimDeAno),
          )).single;
      final entrada = e.toJson()['inputPayload'] as Map<String, dynamic>;
      expect(entrada['fundamentalsPeriods'], 13);
      expect(entrada['fundamentalsOmitted'], 7,
          reason: 'o resumo tem seis exercícios, e diz que resumiu');
      expect(entrada['terminalRiskFreeRate'], 0.094);
      expect((entrada['peerMultiples'] as Map)['precoLucro'],
          {'median': 9, 'peers': 8, 'group': 'g'});
      expect(entrada['overrides'], {'lane': 'firm', 'cashTiming': 'fimDeAno'});
      expect(entrada['contextNotes'], ['nota']);
    });
  });

  group('toda saída emite, e uma vez só', () {
    test('sucesso', () {
      expect(_eventos(() => ValuationCascade.evaluate(_insumos())).length, 1);
    });

    test('recusa antes do primeiro passo', () {
      final eventos = _eventos(() => ValuationCascade.evaluate(ValuationInputs(
            ticker: _ticker,
            asOf: DateTime(2026, 9, 9),
            fundamentals: _serie(),
            marketPrice: 0,
            capm: const CapmInputs(
                riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
          )));
      expect(eventos.single.outputPayload['status'], 'falha');
      expect(eventos.single.endpoint, '/core/valuation/ABCD3');
    });

    test('uma exceção no meio da cascata fecha a transação e continua subindo',
        () {
      final eventos = <AuditEvent>[];
      AuditRecorder.attach(eventos.add);
      addTearDown(AuditRecorder.detach);
      expect(
        () => ValuationCascade.evaluate(
          _insumos(),
          scenarioBuilder: (_) => throw StateError('fonte de cenários quebrada'),
        ),
        throwsStateError,
      );
      expect(eventos, hasLength(1));
      final saida = eventos.single.outputPayload;
      expect(saida['status'], 'falha');
      expect(saida['motivo'], contains('fonte de cenários quebrada'));
      expect(saida['excecao'], 'StateError');
      expect(saida['pilha'], isNotEmpty);
    });

    test('a falha de preparo deixa evento no endpoint da avaliação', () async {
      final eventos = <AuditEvent>[];
      AuditRecorder.attach(eventos.add);
      addTearDown(AuditRecorder.detach);
      final r = await PrepareValuationInputs.call(
        ticker: _ticker,
        prices: _Nada(),
        fundamentals: _SemExercicios(),
        benchmark: _Nada(),
        riskFreeRate: 0.14,
        asOf: DateTime(2026, 9, 9),
      );
      expect(r.isErr, isTrue);
      final e = eventos.single;
      expect(e.endpoint, '/core/valuation/ABCD3');
      expect(e.outputPayload['etapa'], 'preparo');
      expect(e.outputPayload['fonte'], 'exercícios');
      expect(e.outputPayload['motivo'], 'fonte fora');
    });
  });
}

class _SemExercicios implements FundamentalsRepository {
  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async =>
      const Err(InsufficientData('fonte fora'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Nada implements PriceRepository, BenchmarkRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
