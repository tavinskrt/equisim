import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

FundamentalsSnapshot _s(DateTime end, {DateTime? received}) =>
    FundamentalsSnapshot(
      ticker: Ticker.parse('TEST3'),
      fiscalPeriodEnd: end,
      receiptDate: received,
      netIncome: 100,
    );

void main() {
  group('Publicidade pela data observada', () {
    final end2024 = DateTime(2024, 12, 31);
    // O Banco do Brasil entregou o DFP de 2024 em 19/02/2025.
    final received = DateTime(2025, 2, 19);

    test('com DT_RECEB, o exercício é público no dia seguinte ao recebimento',
        () {
      final s = _s(end2024, received: received);
      expect(PointInTimeView(DateTime(2025, 2, 18)).isPublished(s), isFalse);
      expect(PointInTimeView(DateTime(2025, 2, 19)).isPublished(s), isTrue);
      expect(PointInTimeView(DateTime(2025, 3, 1)).isPublished(s), isTrue);
    });

    test('a presunção de 90 dias teria atrasado em 40 dias', () {
      // Sem a data, o corte cai em 31/03/2025; com ela, 19/02/2025.
      final withoutDate = _s(end2024);
      final withDate = _s(end2024, received: received);
      final at = PointInTimeView(DateTime(2025, 3, 15));
      expect(at.isPublished(withoutDate), isFalse);
      expect(at.isPublished(withDate), isTrue,
          reason: 'o documento existia havia quase um mês');
    });

    test('a data observada também ATRASA quando a companhia demora', () {
      // O maximo medido foi 472 dias. A presuncao teria liberado cedo demais.
      final lateFiling = _s(end2024, received: DateTime(2026, 4, 17));
      final at = PointInTimeView(DateTime(2025, 6, 1));
      expect(at.isPublished(lateFiling), isFalse);
      expect(at.isPublished(_s(end2024)), isTrue,
          reason: 'sem a data, a presunção o daria por público');
    });

    test('sem data, o comportamento antigo é preservado', () {
      final s = _s(end2024);
      expect(PointInTimeView(DateTime(2025, 3, 30)).isPublished(s), isFalse);
      expect(PointInTimeView(DateTime(2025, 4, 1)).isPublished(s), isTrue);
    });

    test('a defasagem presumida continua configurável', () {
      final s = _s(end2024);
      final short =
          PointInTimeView(DateTime(2025, 2, 1), publicationLag: Duration(days: 30));
      expect(short.isPublished(s), isTrue);
    });

    test('a série mistura os dois regimes sem se confundir', () {
      final all = [
        _s(DateTime(2022, 12, 31)),
        _s(DateTime(2023, 12, 31), received: DateTime(2024, 3, 20)),
        _s(DateTime(2024, 12, 31), received: DateTime(2025, 2, 19)),
      ];
      final at = PointInTimeView(DateTime(2025, 3, 1));
      final visible = at.published(all);
      expect(visible.length, 3);
      expect(visible.last.fiscalPeriodEnd, DateTime(2024, 12, 31));

      final before = PointInTimeView(DateTime(2025, 1, 10)).published(all);
      expect(before.length, 2, reason: 'o de 2024 ainda não fora recebido');
    });
  });
}
