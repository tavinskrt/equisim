import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int m, int d) => DateTime.utc(2024, m, d);

void main() {
  group('Detecção', () {
    test('a bonificação do BBAS3 em 2024, com os números do COTAHIST', () {
      final q = [
        RawQuote(_d(4, 12), 56.10, 321),
        RawQuote(_d(4, 15), 56.46, 321),
        RawQuote(_d(4, 16), 27.91, 322), // bonificação de 100%
        RawQuote(_d(4, 17), 28.05, 322),
      ];
      final e = CorporateEvents.detect(q);
      expect(e.length, 1);
      expect(e.single.factor, 2);
      expect(e.single.exDate, _d(4, 16));
    });

    test('provento muda o DISMES e NÃO vira evento de ações', () {
      // As oito outras trocas de DISMES do BBAS3 em 2024: quedas de 1% a 4%.
      final q = [
        RawQuote(_d(2, 21), 59.44, 319),
        RawQuote(_d(2, 22), 58.10, 320),
        RawQuote(_d(6, 11), 27.51, 322),
        RawQuote(_d(6, 12), 26.54, 323),
      ];
      expect(CorporateEvents.detect(q), isEmpty,
          reason: 'e o salto de fevereiro a junho não é pregão vizinho');
    });

    test('salto entre pregões distantes não é atribuído a evento', () {
      // Papel suspenso volta com DISMES novo e preço à metade: pode ser
      // evento, pode ser mercado. Sem pregões vizinhos, não se infere.
      final q = [
        RawQuote(_d(2, 22), 58.10, 320),
        RawQuote(_d(6, 11), 27.51, 322),
      ];
      expect(CorporateEvents.detect(q), isEmpty);
    });

    test('grupamento de 2 para 1 tem a folga larga, e não a de bonificação', () {
      // Razão 2,08: 4% longe de 2. Com "perto de 1" medido como |fator − 1|,
      // o fator 0,5 cairia na folga de 1,5% e seria recusado.
      final q = [
        RawQuote(_d(5, 2), 10.0, 50),
        RawQuote(_d(5, 3), 20.8, 51),
      ];
      expect(CorporateEvents.detect(q).single.factor, closeTo(0.5, 1e-12));
    });

    test('grupamento de 10 para 1', () {
      final q = [
        RawQuote(_d(5, 2), 1.20, 50),
        RawQuote(_d(5, 3), 12.30, 51),
      ];
      final e = CorporateEvents.detect(q).single;
      expect(e.factor, closeTo(0.1, 1e-12));
    });

    test('queda grande SEM troca de DISMES não é evento', () {
      final q = [
        RawQuote(_d(3, 1), 10.0, 7),
        RawQuote(_d(3, 2), 5.0, 7),
      ];
      expect(CorporateEvents.detect(q), isEmpty,
          reason: 'sem distribuição registrada, é mercado');
    });

    test('crise em data ex que não está perto de fração é recusada', () {
      // -37%: nem 1/2 (fator 2 exigiria 0,5) nem 2/3 (não listado) — fica fora.
      final q = [
        RawQuote(_d(3, 1), 10.0, 7),
        RawQuote(_d(3, 2), 6.3, 8),
      ];
      expect(CorporateEvents.detect(q), isEmpty);
    });

    test('bonificação pequena NÃO é detectada, e isso está declarado', () {
      // 10% de bonificação (0,909) e 8,5% de queda em data ex (0,915) estão a
      // 0,6% uma da outra. Separá-las pelo preço é impossível; a régua recusa
      // as duas em vez de acertar uma por sorte.
      final bonificacao = [
        RawQuote(_d(3, 1), 11.0, 7),
        RawQuote(_d(3, 2), 10.0, 8),
      ];
      final dividendo = [
        RawQuote(_d(3, 1), 10.0, 7),
        RawQuote(_d(3, 2), 9.15, 8),
      ];
      expect(CorporateEvents.detect(bonificacao), isEmpty);
      expect(CorporateEvents.detect(dividendo), isEmpty);
    });

    test('bonificação de 50% é detectada com folga apertada', () {
      final q = [
        RawQuote(_d(3, 1), 15.0, 7),
        RawQuote(_d(3, 2), 10.05, 8), // 0,67 ≈ 1/1,5
      ];
      expect(CorporateEvents.detect(q).single.factor, 1.5);
    });
  });

  group('Ajuste', () {
    test('divide o passado pelo fator, e o presente fica intacto', () {
      final q = [
        RawQuote(_d(4, 15), 56.46, 321),
        RawQuote(_d(4, 16), 27.91, 322),
        RawQuote(_d(4, 17), 28.05, 322),
      ];
      final ajustada = CorporateEvents.adjust(q, CorporateEvents.detect(q));
      expect(ajustada[0].close, closeTo(28.23, 1e-12));
      expect(ajustada[1].close, 27.91);
      expect(ajustada[2].close, 28.05);
    });

    test('dois eventos se compõem', () {
      final q = [
        RawQuote(_d(1, 2), 100, 1),
        RawQuote(_d(1, 3), 50, 2), // 1 -> 2
        RawQuote(_d(1, 4), 500, 3), // 10 -> 1
      ];
      final e = CorporateEvents.detect(q);
      expect(e.length, 2);
      final a = CorporateEvents.adjust(q, e);
      // 100 / 2 * 10 = 500
      expect(a.first.close, closeTo(500, 1e-9));
    });
  });
}
