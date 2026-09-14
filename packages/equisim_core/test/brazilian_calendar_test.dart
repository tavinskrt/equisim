import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

/// Dias úteis da liquidação ao vencimento, como o Tesouro conta.
int _duDoTesouro(DateTime base, DateTime vencimento) =>
    BrazilianCalendar.businessDaysBetween(
      BrazilianCalendar.treasurySettlement(base),
      vencimento,
      knownAt: base,
    );

void main() {
  group('Feriados', () {
    test('Páscoa pelo algoritmo gregoriano', () {
      expect(BrazilianCalendar.easter(2024), _d(2024, 3, 31));
      expect(BrazilianCalendar.easter(2025), _d(2025, 4, 20));
      expect(BrazilianCalendar.easter(2026), _d(2026, 4, 5));
    });

    test('Carnaval, Paixão e Corpus Christi andam com a Páscoa', () {
      expect(BrazilianCalendar.isBusinessDay(_d(2024, 2, 12)), isFalse);
      expect(BrazilianCalendar.isBusinessDay(_d(2024, 2, 13)), isFalse);
      expect(BrazilianCalendar.isBusinessDay(_d(2024, 2, 14)), isTrue,
          reason: 'quarta de cinzas é útil no calendário nacional');
      expect(BrazilianCalendar.isBusinessDay(_d(2024, 3, 29)), isFalse);
      expect(BrazilianCalendar.isBusinessDay(_d(2024, 5, 30)), isFalse);
    });

    test('fim de semana não é útil', () {
      expect(BrazilianCalendar.isBusinessDay(_d(2026, 9, 12)), isFalse);
      expect(BrazilianCalendar.isBusinessDay(_d(2026, 9, 13)), isFalse);
      expect(BrazilianCalendar.isBusinessDay(_d(2026, 9, 14)), isTrue);
    });

    test('o 20 de novembro só é feriado para quem já conhecia a lei', () {
      // Quinta-feira, 20/11/2025.
      expect(BrazilianCalendar.isBusinessDay(_d(2025, 11, 20)), isFalse);
      expect(
        BrazilianCalendar.isBusinessDay(_d(2025, 11, 20),
            knownAt: _d(2022, 6, 9)),
        isTrue,
        reason: 'Lei 14.759 é de 21/12/2023',
      );
      expect(BrazilianCalendar.isBusinessDay(_d(2023, 11, 20)), isTrue,
          reason: 'antes de 2024 não era feriado nacional');
    });
  });

  group('Contagem', () {
    test('[início, fim): o primeiro dia conta, o último não', () {
      // Segunda 14/09/2026 a segunda 21/09/2026: cinco dias úteis.
      expect(
        BrazilianCalendar.businessDaysBetween(_d(2026, 9, 14), _d(2026, 9, 21)),
        5,
      );
      expect(
        BrazilianCalendar.businessDaysBetween(_d(2026, 9, 21), _d(2026, 9, 14)),
        0,
      );
    });

    test('a liquidação pula 24/12 e 31/12', () {
      expect(BrazilianCalendar.treasurySettlement(_d(2025, 12, 23)),
          _d(2025, 12, 26));
      expect(BrazilianCalendar.treasurySettlement(_d(2025, 12, 30)),
          _d(2026, 1, 2));
      expect(BrazilianCalendar.treasurySettlement(_d(2026, 9, 11)),
          _d(2026, 9, 14), reason: 'sexta liquida na segunda');
    });
  });

  group('Conferido contra o PU do Tesouro', () {
    // `du` implícito = 252 · ln(1000 ÷ PU) ÷ ln(1 + taxa), das LTN do arquivo
    // de preços do Tesouro Direto. Arredondado ao dia.
    test('data-base de hoje', () {
      expect(_duDoTesouro(_d(2026, 9, 10), _d(2027, 1, 1)), 76);
      expect(_duDoTesouro(_d(2026, 9, 10), _d(2029, 1, 1)), 575);
      expect(_duDoTesouro(_d(2026, 9, 10), _d(2032, 1, 1)), 1328);
    });

    test('virada de ano, onde a liquidação importa', () {
      expect(_duDoTesouro(_d(2025, 12, 23), _d(2026, 1, 1)), 4);
      expect(_duDoTesouro(_d(2025, 12, 30), _d(2027, 1, 1)), 249);
    });

    test('antes da lei, o 20 de novembro dos anos futuros ainda era útil', () {
      expect(_duDoTesouro(_d(2022, 6, 9), _d(2025, 1, 1)), 644);
      expect(_duDoTesouro(_d(2022, 6, 9), _d(2029, 1, 1)), 1647);
      expect(_duDoTesouro(_d(2019, 3, 15), _d(2025, 1, 1)), 1458);
    });
  });
}
