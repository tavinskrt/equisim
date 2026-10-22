// O valuation confirmado guarda as premissas e o resultado juntos, e vai ao
// armazenamento e ao painel de auditoria pelo mesmo retrato (decisão 150).
//
// O que estes testes travam: o registro guarda **o que a conta deu**, sem
// refazê-la; relê-lo devolve os mesmos números, bit a bit; um documento
// corrompido é descartado sem lançar; e o evento do painel carrega o mesmo
// identificador e os mesmos valores da tela.
import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// A mesma companhia sintética da cascata usada na tela (`populated_state`):
/// a via da firma com o resultado operacional sustentado, a do acionista com
/// ele negativo.
ValuationResult _cascade({bool firm = true}) {
  final ticker = Ticker.parse(firm ? 'WEGE3' : 'ITUB4');
  final series = <FundamentalsSnapshot>[];
  var e = 1.0;
  for (var i = 12; i >= 0; i--) {
    series.add(FundamentalsSnapshot(
      ticker: ticker,
      fiscalPeriodEnd: DateTime(2025 - i, 12, 31),
      totalRevenue: 10000e6 * e,
      ebit: (firm ? 1800e6 : -200e6) * e,
      ebitda: (firm ? 2400e6 : 300e6) * e,
      netIncome: 900e6 * e,
      incomeBeforeTax: (firm ? 1300e6 : 1200e6) * e,
      incomeTaxExpense: (firm ? -400e6 : -300e6) * e,
      interestExpense: firm ? 400e6 : 50e6,
      earningsPerShare: 0.9 * e,
      cash: firm ? 200e6 : 2000e6 * e,
      shortTermDebt: firm ? 1000e6 : 500e6,
      longTermDebt: firm ? 3000e6 : 500e6,
      totalStockholderEquity: 6000e6 * e,
      bookValuePerShare: 6.0 * e,
      operatingCashFlow: firm ? 2000e6 * e : null,
      nopat: firm ? 1188e6 * e : null,
      sharesOutstanding: 1000e6,
      sharesOutstandingAsOf: 1000e6,
      marketCap: 12000e6,
    ));
    e *= i.isEven ? 1.04 : 1.06;
  }
  final r = ValuationCascade.evaluate(ValuationInputs(
    ticker: ticker,
    asOf: DateTime(2026, 9, 9),
    fundamentals: series,
    marketPrice: 12.0,
    capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
    declaredTerminalRiskFreeRate: 0.10,
    unleveredBeta: firm ? 0.8 : 0.9,
  ));
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

final _savedAt = DateTime.utc(2026, 10, 22, 18, 30, 15);

ManualValuationRecord _capture(
  ValuationResult r,
  ManualPremises p, {
  String id = '7f0c2b1e-0000-4000-8000-000000000001',
}) {
  final record = ManualValuationRecord.capture(
    id: id,
    ticker: r.ticker,
    engineAsOf: r.asOf,
    valuation: r.manual!,
    premises: p,
    savedAt: _savedAt,
  );
  expect(record.isOk, isTrue, reason: record.failureOrNull?.message);
  return record.unwrap();
}

/// O que se grava, passado por texto como o armazenamento e o canal fazem.
Map<String, dynamic> _wire(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  for (final firm in [true, false]) {
    final via = firm ? 'da firma' : 'do acionista';

    group('via $via', () {
      late ValuationResult r;
      late ManualValuation m;

      setUpAll(() {
        r = _cascade(firm: firm);
        m = r.manual!;
      });

      test('sem troca, o registro guarda o preço do motor, bit a bit', () {
        final record = _capture(r, m.enginePremises);
        expect(record.fairValuePerShare, m.engineFairValue);
        expect(record.changedFields, isEmpty);
        expect(record.attribution, isEmpty);
        expect(record.lane, firm ? ValuationLane.firm : ValuationLane.shareholder);
      });

      test('com troca, guarda o que a conta deu, sem refazê-la', () {
        final p = m.enginePremises.copyWith(
          growth: m.enginePremises.growth + 0.02,
          discountRate: m.enginePremises.discountRate - 0.01,
          ratePath: ManualRatePath.constant,
        );
        final record = _capture(r, p);
        final expected = m.evaluate(p).unwrap();
        expect(record.fairValuePerShare, expected.fairValuePerShare);
        expect(record.outcome.equityValue, expected.equityValue);
        expect(record.outcome.years.length, expected.years.length);
        expect(
          record.changedFields,
          [ManualField.growth, ManualField.discountRate],
        );
        expect(record.attribution, isNotEmpty);
        expect(record.engineDelta, expected.fairValuePerShare - m.engineFairValue);
        expect(record.upside, expected.fairValuePerShare / m.marketPrice - 1);
        expect(
          record.fairValue,
          Money.fromReais(expected.fairValuePerShare),
        );
      });

      test('relido do texto, o registro é o mesmo, número a número', () {
        final p = m.enginePremises.copyWith(
          baseProfit: m.enginePremises.baseProfit * 1.2,
          reinvestment: ManualReinvestment.fixedFraction,
          retention: 0.35,
          terminalReturn: m.enginePremises.discountRate + 0.04,
        );
        final record = _capture(r, p);
        final again = ManualValuationRecord.fromJson(_wire(record.toJson()));
        expect(again, isNotNull);
        expect(again!.toJson(), record.toJson());
        expect(again.id, record.id);
        expect(again.ticker, record.ticker);
        expect(again.savedAt.isAtSameMomentAs(record.savedAt), isTrue);
        expect(again.engineAsOf, record.engineAsOf);
        expect(again.premises.retention, 0.35);
        expect(again.premises.reinvestment, ManualReinvestment.fixedFraction);
        expect(again.fairValuePerShare, record.fairValuePerShare);
        expect(again.changedFields, record.changedFields);
      });

      test('o evento do painel carrega o mesmo identificador e os números', () {
        final p = m.enginePremises.copyWith(
          perpetualGrowth: m.enginePremises.perpetualGrowth + 0.005,
        );
        final record = _capture(r, p);
        final event = record.toAuditEvent();

        expect(event.transactionId, record.id);
        expect(event.timestamp, record.savedAt);
        expect(event.endpoint, '/core/valuation/manual/${r.ticker.value}');
        // O painel conta o evento entre os cálculos pela origem `/core/`.
        expect(event.endpoint.startsWith('/core/'), isTrue);
        expect(event.outputPayload['status'], 'confirmado');
        expect(event.outputPayload['precoJusto'], record.fairValuePerShare);
        expect(event.outputPayload['precoJustoCentavos'], record.fairValue.cents);
        expect(event.inputPayload['camposTrocados'], ['crescimentoPerpetuo']);

        final byName = {
          for (final c in event.calculations) c.formulaName: c.finalValue,
        };
        expect(
          byName['Preço justo por ação — seus números'],
          record.fairValuePerShare,
        );
        expect(
          byName['Valor do patrimônio — seus números'],
          record.outcome.equityValue,
        );
        expect(
          byName['Valor presente dos anos explícitos — seus números'],
          record.outcome.explicitPresentValue,
        );

        // O canal entre janelas e a exportação passam o evento por JSON.
        final back = AuditEvent.fromJson(_wire(event.toJson()));
        expect(back.transactionId, record.id);
        expect(back.calculations.length, event.calculations.length);
      });
    });
  }

  group('recusa e leitura tolerante', () {
    late ValuationResult r;

    setUpAll(() => r = _cascade());

    test('premissa sem conta não vira registro, e a falha nomeia o campo', () {
      final p = r.manual!.enginePremises.copyWith(baseProfit: -1);
      final record = ManualValuationRecord.capture(
        id: 'x',
        ticker: r.ticker,
        engineAsOf: r.asOf,
        valuation: r.manual!,
        premises: p,
        savedAt: _savedAt,
      );
      expect(record.isOk, isFalse);
      final failure = record.failureOrNull;
      expect(failure, isA<InvalidInput>());
      expect((failure! as InvalidInput).field, ManualField.baseProfit.name);
    });

    test('identificador vazio é recusado', () {
      final record = ManualValuationRecord.capture(
        id: '  ',
        ticker: r.ticker,
        engineAsOf: r.asOf,
        valuation: r.manual!,
        premises: r.manual!.enginePremises,
        savedAt: _savedAt,
      );
      expect(record.failureOrNull, isA<InvalidInput>());
    });

    test('documento corrompido devolve null, e não lança', () {
      final good = _wire(_capture(r, r.manual!.enginePremises).toJson());

      Map<String, dynamic> without(String key) =>
          Map.of(good)..remove(key);

      expect(ManualValuationRecord.fromJson({...good, 'formato': 2}), isNull);
      expect(ManualValuationRecord.fromJson(without('resultado')), isNull);
      expect(ManualValuationRecord.fromJson(without('premissas')), isNull);
      expect(ManualValuationRecord.fromJson({...good, 'via': 'outra'}), isNull);
      expect(ManualValuationRecord.fromJson({...good, 'ticker': '??'}), isNull);
      expect(ManualValuationRecord.fromJson({...good, 'id': ''}), isNull);
      expect(
        ManualValuationRecord.fromJson({...good, 'salvoEm': 'ontem'}),
        isNull,
      );
      expect(ManualValuationRecord.fromJson(const {}), isNull);
    });

    test('a mesma confirmação dá sempre o mesmo registro', () {
      final p = r.manual!.enginePremises.copyWith(growth: 0.07);
      expect(_capture(r, p).toJson(), _capture(r, p).toJson());
    });
  });
}
