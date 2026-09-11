import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

FundamentalsSnapshot _s(DateTime fim, {DateTime? recebido}) =>
    FundamentalsSnapshot(
      ticker: Ticker.parse('TEST3'),
      fiscalPeriodEnd: fim,
      receiptDate: recebido,
      netIncome: 100,
    );

void main() {
  group('Publicidade pela data observada', () {
    final fim2024 = DateTime(2024, 12, 31);
    // O Banco do Brasil entregou o DFP de 2024 em 19/02/2025.
    final recebido = DateTime(2025, 2, 19);

    test('com DT_RECEB, o exercício é público no dia seguinte ao recebimento',
        () {
      final s = _s(fim2024, recebido: recebido);
      expect(PointInTimeView(DateTime(2025, 2, 18)).isPublished(s), isFalse);
      expect(PointInTimeView(DateTime(2025, 2, 19)).isPublished(s), isTrue);
      expect(PointInTimeView(DateTime(2025, 3, 1)).isPublished(s), isTrue);
    });

    test('a presunção de 90 dias teria atrasado em 40 dias', () {
      // Sem a data, o corte cai em 31/03/2025; com ela, 19/02/2025.
      final semData = _s(fim2024);
      final comData = _s(fim2024, recebido: recebido);
      final em = PointInTimeView(DateTime(2025, 3, 15));
      expect(em.isPublished(semData), isFalse);
      expect(em.isPublished(comData), isTrue,
          reason: 'o documento existia havia quase um mês');
    });

    test('a data observada também ATRASA quando a companhia demora', () {
      // O maximo medido foi 472 dias. A presuncao teria liberado cedo demais.
      final tarde = _s(fim2024, recebido: DateTime(2026, 4, 17));
      final em = PointInTimeView(DateTime(2025, 6, 1));
      expect(em.isPublished(tarde), isFalse);
      expect(em.isPublished(_s(fim2024)), isTrue,
          reason: 'sem a data, a presunção o daria por público');
    });

    test('sem data, o comportamento antigo é preservado', () {
      final s = _s(fim2024);
      expect(PointInTimeView(DateTime(2025, 3, 30)).isPublished(s), isFalse);
      expect(PointInTimeView(DateTime(2025, 4, 1)).isPublished(s), isTrue);
    });

    test('a defasagem presumida continua configurável', () {
      final s = _s(fim2024);
      final curto =
          PointInTimeView(DateTime(2025, 2, 1), publicationLag: Duration(days: 30));
      expect(curto.isPublished(s), isTrue);
    });

    test('a série mistura os dois regimes sem se confundir', () {
      final todos = [
        _s(DateTime(2022, 12, 31)),
        _s(DateTime(2023, 12, 31), recebido: DateTime(2024, 3, 20)),
        _s(DateTime(2024, 12, 31), recebido: DateTime(2025, 2, 19)),
      ];
      final em = PointInTimeView(DateTime(2025, 3, 1));
      final vis = em.published(todos);
      expect(vis.length, 3);
      expect(vis.last.fiscalPeriodEnd, DateTime(2024, 12, 31));

      final antes = PointInTimeView(DateTime(2025, 1, 10)).published(todos);
      expect(antes.length, 2, reason: 'o de 2024 ainda não fora recebido');
    });
  });
}
