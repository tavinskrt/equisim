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

FundamentalsSnapshot _year(int y, double scale) => FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1800 * scale,
      ebitda: 2400 * scale,
      netIncome: 900 * scale,
      incomeBeforeTax: 1300 * scale,
      incomeTaxExpense: -400 * scale,
      interestExpense: 400,
      earningsPerShare: 0.9 * scale,
      cash: 200,
      shortTermDebt: 1000,
      longTermDebt: 3000,
      totalStockholderEquity: 6000 * scale,
      bookValuePerShare: 6.0 * scale,
      operatingCashFlow: 2000 * scale,
      nopat: 1188 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    );

List<FundamentalsSnapshot> _series() {
  final out = <FundamentalsSnapshot>[];
  var scale = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(_year(2025 - i, scale));
    scale *= 1.05;
  }
  return out;
}

ValuationInputs _inputs({List<String> notes = const []}) => ValuationInputs(
      ticker: _ticker,
      asOf: DateTime(2026, 9, 9),
      fundamentals: _series(),
      marketPrice: 12.0,
      capm: const CapmInputs(
          riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
      declaredTerminalRiskFreeRate: 0.094,
      peerMultiples: PeerMultipleSet(byKind: const {
        MultipleKind.priceToEarnings: PeerMultiple(median: 9, peers: 8, group: 'g'),
        MultipleKind.priceToBook:
            PeerMultiple(median: 1.4, peers: 8, group: 'g'),
        MultipleKind.evToEbitda:
            PeerMultiple(median: 6, peers: 8, group: 'g'),
      }, asOf: DateTime(2026, 9, 1)),
      contextNotes: notes,
    );

/// Captura os eventos emitidos durante [body].
List<AuditEvent> _events(void Function() body) {
  final out = <AuditEvent>[];
  AuditRecorder.attach(out.add);
  try {
    body();
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
        'enum': CashTiming.endOfYear,
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
      final events = _events(() {
        AuditRecorder.begin('/core/teste', inputPayload: {'x': double.nan})!
          ..step(
            formulaName: 'conta degenerada',
            latex: r'x = 0/0',
            variables: {'a': double.nan, 'b': double.infinity},
            result: double.nan,
          )
          ..complete({'saida': double.negativeInfinity});
      });
      final text = jsonEncode(events.single.toJson());
      final roundTrip = AuditEvent.fromJson(
          jsonDecode(text) as Map<String, dynamic>);
      expect(roundTrip.calculations.single.finalValue!.isNaN, isTrue);
      expect(roundTrip.calculations.single.mappedVariables['b'], 'Infinity');
      expect(roundTrip.inputPayload['x'], 'NaN');
      expect(roundTrip.outputPayload['saida'], '-Infinity');
    });

    test('o JSON de um rastro sem valor degenerado não muda um byte', () {
      final e = _events(() => ValuationCascade.evaluate(_inputs())).single;
      final raw = jsonEncode({
        'entrada': e.inputPayload,
        'saida': e.outputPayload,
        'calculos': [for (final c in e.calculations) c.toJson()],
      });
      final j = e.toJson();
      final safe = jsonEncode({
        'entrada': j['inputPayload'],
        'saida': j['outputPayload'],
        'calculos': j['calculations'],
      });
      expect(safe, raw);
    });
  });

  group('completo', () {
    test('o evento reproduz o resultado que a tela mostra', () {
      late Result<ValuationResult> r;
      final e = _events(() {
        r = ValuationCascade.evaluate(
            _inputs(notes: const ['CVM defasada', 'curva de 12/09']));
      }).single;
      final v = r.unwrap();
      final event = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
      final output = event['outputPayload'] as Map<String, dynamic>;

      expect(output['status'], 'ok');
      expect(output['fairValue'], v.fairValue.reais);
      expect(output['marketPrice'], v.marketPrice.reais);
      expect((output['discountRate'] as num).toDouble(),
          closeTo(v.discountRate, 1e-6));
      expect(output['warnings'], v.warnings,
          reason: 'a tela e o arquivo leem as mesmas ressalvas');
      expect(v.warnings, containsAll(['CVM defasada', 'curva de 12/09']));
      expect(output.containsKey('priceVolatility'), isTrue);

      final d = output['diagnostics'] as Map<String, dynamic>;
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
        final t = output['triangulation'] as Map<String, dynamic>;
        expect((t['readings'] as List).length, tri.readings.length);
      }
    });

    test('a entrada diz com que insumo a cascata rodou', () {
      final e = _events(() => ValuationCascade.evaluate(
            _inputs(notes: const ['nota']).withOverrides(
                lane: ValuationLane.firm, cashTiming: CashTiming.endOfYear),
          )).single;
      final entry = e.toJson()['inputPayload'] as Map<String, dynamic>;
      expect(entry['fundamentalsPeriods'], 13);
      expect(entry['fundamentalsOmitted'], 7,
          reason: 'o resumo tem seis exercícios, e diz que resumiu');
      expect(entry['terminalRiskFreeRate'], 0.094);
      expect((entry['peerMultiples'] as Map)['precoLucro'],
          {'median': 9, 'peers': 8, 'group': 'g'});
      expect(entry['overrides'], {'lane': 'firm', 'cashTiming': 'fimDeAno'});
      expect(entry['contextNotes'], ['nota']);
    });
  });

  group('toda saída emite, e uma vez só', () {
    test('sucesso', () {
      expect(_events(() => ValuationCascade.evaluate(_inputs())).length, 1);
    });

    test('recusa antes do primeiro passo', () {
      final events = _events(() => ValuationCascade.evaluate(ValuationInputs(
            ticker: _ticker,
            asOf: DateTime(2026, 9, 9),
            fundamentals: _series(),
            marketPrice: 0,
            capm: const CapmInputs(
                riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
          )));
      expect(events.single.outputPayload['status'], 'falha');
      expect(events.single.endpoint, '/core/valuation/ABCD3');
    });

    test('uma exceção no meio da cascata fecha a transação e continua subindo',
        () {
      final events = <AuditEvent>[];
      AuditRecorder.attach(events.add);
      addTearDown(AuditRecorder.detach);
      expect(
        () => ValuationCascade.evaluate(
          _inputs(),
          scenarioBuilder: (_) => throw StateError('fonte de cenários quebrada'),
        ),
        throwsStateError,
      );
      expect(events, hasLength(1));
      final output = events.single.outputPayload;
      expect(output['status'], 'falha');
      expect(output['motivo'], contains('fonte de cenários quebrada'));
      expect(output['excecao'], 'StateError');
      expect(output['pilha'], isNotEmpty);
    });

    test('a falha de preparo deixa evento no endpoint da avaliação', () async {
      final events = <AuditEvent>[];
      AuditRecorder.attach(events.add);
      addTearDown(AuditRecorder.detach);
      final r = await PrepareValuationInputs.call(
        ticker: _ticker,
        prices: _Nothing(),
        fundamentals: _NoFiscalYears(),
        benchmark: _Nothing(),
        riskFreeRate: 0.14,
        asOf: DateTime(2026, 9, 9),
      );
      expect(r.isErr, isTrue);
      final e = events.single;
      expect(e.endpoint, '/core/valuation/ABCD3');
      expect(e.outputPayload['etapa'], 'preparo');
      expect(e.outputPayload['fonte'], 'exercícios');
      expect(e.outputPayload['motivo'], 'fonte fora');
    });
  });
}

class _NoFiscalYears implements FundamentalsRepository {
  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async =>
      const Err(InsufficientData('fonte fora'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Nothing implements PriceRepository, BenchmarkRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
