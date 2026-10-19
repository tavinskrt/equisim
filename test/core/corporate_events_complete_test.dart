// O ajuste que a fonte de preços deixou de fazer (item B29).
//
// A fonte ajusta desdobramento e grupamento, e não toda bonificação: a data ex
// de uma bonificação não ajustada é uma queda que não aconteceu, e ela entrava
// no beta, na volatilidade da faixa e em todo retorno que a atravessa.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('ABCD3');

/// Série diária de dias úteis com [price] constante, salvo o [jump] aplicado a
/// partir de [ex].
PriceSeries _series({required double jump, DateTime? ex, double price = 10}) {
  final pts = <PricePoint>[];
  // O laço anda em UTC, que não tem horário de verão; o ponto trunca para o
  // dia local, como a fonte.
  var d = DateTime.utc(2024, 3, 1);
  while (d.isBefore(DateTime.utc(2024, 5, 1))) {
    if (d.weekday <= 5) {
      final day = DateTime(d.year, d.month, d.day);
      final after = ex != null && !day.isBefore(ex);
      pts.add(
        PricePoint(
          date: day,
          close: after ? price * jump : price,
          volume: 1000,
        ),
      );
    }
    d = d.add(const Duration(days: 1));
  }
  return PriceSeries(ticker: _t, points: pts);
}

ShareEvent _event(DateTime ex, double factor) =>
    ShareEvent(exDate: ex, factor: factor, observedRatio: 1 / factor);

void main() {
  final ex = DateTime(2024, 4, 2);

  group('completeAdjustment', () {
    test('bonificação de 10% sem ajuste: a queda sai e o volume sobe', () {
      final s = _series(jump: 1 / 1.1, ex: ex);
      final r = CorporateEvents.completeAdjustment(s, [_event(ex, 1.1)]);
      expect(r.applied, hasLength(1));
      final before = r.series.points.firstWhere(
        (p) => p.date == DateTime(2024, 4, 1),
      );
      final after = r.series.points.firstWhere((p) => p.date == ex);
      expect(
        after.close / before.close,
        closeTo(1, 1e-9),
        reason: 'a série fica contínua na data ex',
      );
      expect(
        before.volume! * before.close,
        closeTo(1000 * 10, 1e-6),
        reason: 'o financeiro do dia não muda',
      );
    });

    test('evento que a fonte já ajustou não muda nada', () {
      final s = _series(jump: 1.0);
      final r = CorporateEvents.completeAdjustment(s, [_event(ex, 1.1)]);
      expect(r.applied, isEmpty);
      expect(identical(r.series, s), isTrue);
    });

    test('desdobramento de 2 para 1 sem ajuste também sai', () {
      final s = _series(jump: 0.5, ex: ex);
      final r = CorporateEvents.completeAdjustment(s, [_event(ex, 2)]);
      expect(r.applied, hasLength(1));
      expect(r.series.points.first.close, closeTo(5, 1e-9));
    });

    test('um pregão de −5% na data ex de bonificação já ajustada fica como '
        'está', () {
      // Com a folga de 6% ele passaria por bonificação não ajustada, e o
      // ajuste inventaria uma alta de 10% no lugar da queda.
      final s = _series(jump: 0.95, ex: ex);
      final r = CorporateEvents.completeAdjustment(s, [_event(ex, 1.1)]);
      expect(r.applied, isEmpty);
    });

    test('bonificação não ajustada com o mercado andando 2% no dia sai', () {
      final s = _series(jump: 0.98 / 1.1, ex: ex);
      final r = CorporateEvents.completeAdjustment(s, [_event(ex, 1.1)]);
      expect(r.applied, hasLength(1));
    });

    test('evento sem pregão vizinho na série não ajusta nada', () {
      final s = _series(jump: 1 / 1.1, ex: ex);
      final r = CorporateEvents.completeAdjustment(s, [
        _event(DateTime(2023, 1, 10), 1.1),
      ]);
      expect(r.applied, isEmpty);
    });
  });

  test('applyToSeries ajusta sem perguntar', () {
    final s = _series(jump: 1.0);
    final a = CorporateEvents.applyToSeries(s, [_event(ex, 1.1)]);
    expect(a.points.first.close, closeTo(10 / 1.1, 1e-9));
    expect(a.points.last.close, closeTo(10, 1e-9));
  });

  test('o pacote de eventos de capital vai e volta, e pula o malformado', () {
    final package = CapitalEventsCodec.encodePackage({
      'ABCD3': CapitalEvents(
        issues: [
          ShareIssue(
            date: DateTime(2026, 2, 4),
            amount: Money.fromReais(5.4e9),
            shares: 270000000,
          ),
        ],
        shareEvents: [_event(DateTime(2024, 4, 16), 2)],
      ),
      'VAZI3': const CapitalEvents(),
    }, generatedAt: DateTime(2026, 9, 24));
    expect((package['ativos'] as Map).containsKey('VAZI3'), isFalse);
    final parsed = CapitalEventsCodec.decodePackage({
      ...package,
      'ativos': {
        ...(package['ativos'] as Map),
        'RUIM3': {
          'emissoes': [
            {'data': 'não é data', 'centavos': 100, 'acoes': 1},
            {'data': '2026-01-01', 'centavos': -500, 'acoes': 1},
            // Fração de ação e centavo fracionário são entrada malformada.
            {'data': '2026-01-01', 'centavos': 500, 'acoes': 1.5},
            {'data': '2026-01-01', 'centavos': 50.5, 'acoes': 1},
          ],
          'eventos': [
            {'dataEx': '2026-01-01', 'fator': 0},
          ],
        },
      },
    });
    expect(parsed.keys, ['ABCD3']);
    expect(parsed['ABCD3']!.issues.single.amount, Money.fromReais(5.4e9));
    expect(parsed['ABCD3']!.issues.single.shares, 270000000);
    expect(parsed['ABCD3']!.shareEvents.single.factor, 2);
  });
}
