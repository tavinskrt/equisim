// Conferência da estatística usada pelos utilitários de validação.
//
// `tool/validation/regression.dart` foi escrito à mão porque a máquina do
// projeto não tem NumPy nem statsmodels. Sem conferência, ele seria uma
// segunda implementação não verificada logo abaixo de um núcleo que fez
// questão de verificar a primeira.
//
// **A referência é o próprio núcleo.** `Inference.ols` já está conferido
// contra `statsmodels` na ordem de 1e-14 (docs/validacao/conferencia_inferencia.md),
// e no caso de **um** regressor a regressão múltipla tem de reproduzi-lo
// exatamente — inclusive erro-padrão e R². É referência independente de
// verdade, e não a mesma conta escrita duas vezes: os caminhos são diferentes
// (fórmula fechada de mínimos quadrados simples contra inversão de X'X).
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/validation/regression.dart';

void main() {
  group('Regression.ols contra Inference.ols do núcleo', () {
    test('reproduz inclinação, intercepto, erro-padrão e R² com 1 regressor',
        () {
      final xs = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      final ys = <double>[
        2.1, 3.9, 6.2, 7.8, 10.3, 11.9, 14.4, 15.8, 18.1, 20.4, 21.7, 24.2,
      ];

      final referencia = Inference.ols(xs, ys)!;
      final medido = Regression.ols([xs], ys)!;

      expect(medido.coefficients[1], closeTo(referencia.slope, 1e-10));
      expect(medido.coefficients[0], closeTo(referencia.intercept, 1e-10));
      expect(medido.stdErrors[1], closeTo(referencia.slopeStdError, 1e-10));
      expect(medido.r2, closeTo(referencia.r2, 1e-10));
      expect(medido.n, referencia.n);
    });

    test('recupera coeficientes conhecidos sem resíduo', () {
      // y = 3 + 2·x1 − 0,5·x2, exato. Um solucionador correto devolve os três
      // com R² igual a 1.
      final x1 = <double>[1, 2, 3, 4, 5, 6, 7, 8];
      final x2 = <double>[4, 1, 7, 2, 9, 3, 8, 5];
      final y = [
        for (var i = 0; i < x1.length; i++) 3 + 2 * x1[i] - 0.5 * x2[i],
      ];

      final f = Regression.ols([x1, x2], y)!;
      expect(f.coefficients[0], closeTo(3.0, 1e-9));
      expect(f.coefficients[1], closeTo(2.0, 1e-9));
      expect(f.coefficients[2], closeTo(-0.5, 1e-9));
      expect(f.r2, closeTo(1.0, 1e-9));
    });

    test('devolve nulo em colinearidade exata', () {
      final x1 = <double>[1, 2, 3, 4, 5, 6];
      final x2 = [for (final v in x1) 2 * v];
      expect(Regression.ols([x1, x2], [1, 2, 3, 4, 5, 7]), isNull);
    });

    test('devolve nulo sem graus de liberdade', () {
      expect(Regression.ols([[1.0, 2.0], [3.0, 1.0]], [1.0, 2.0]), isNull);
    });
  });

  group('postos e correlação de ordem', () {
    test('empate recebe a média das posições', () {
      expect(Regression.ranks([10, 20, 20, 40]), [1.0, 2.5, 2.5, 4.0]);
    });

    test('Spearman é 1 em transformação monótona', () {
      final xs = <double>[1, 2, 3, 4, 5, 6, 7];
      final ys = [for (final v in xs) v * v * v];
      expect(Regression.spearman(xs, ys)!, closeTo(1.0, 1e-12));
    });

    test('Spearman é −1 na ordem invertida', () {
      final xs = <double>[1, 2, 3, 4, 5];
      expect(Regression.spearman(xs, [5.0, 4, 3, 2, 1])!, closeTo(-1.0, 1e-12));
    });

    test('amostra unitária não devolve NaN silencioso', () {
      // Com n = 1 a variância divide por zero. O `NaN` resultante atravessaria
      // qualquer guarda escrita como `sd <= 0`, porque toda comparação com
      // `NaN` é falsa, e contaminaria os somatórios a jusante.
      final z = Regression.standardizedRanks([7.0]);
      expect(z, hasLength(1));
      expect(z.first.isNaN, isFalse);
      expect(z.first, 0.0);
      expect(Regression.standardizedRanks([]), isEmpty);
    });

    test('postos padronizados têm média zero e desvio um', () {
      final z = Regression.standardizedRanks([3, 1, 4, 1, 5, 9, 2, 6]);
      final media = z.reduce((a, b) => a + b) / z.length;
      var ss = 0.0;
      for (final v in z) {
        ss += (v - media) * (v - media);
      }
      expect(media, closeTo(0.0, 1e-12));
      expect(ss / (z.length - 1), closeTo(1.0, 1e-12));
    });
  });

  group('Regression.residualize', () {
    test('resíduo é ortogonal aos regressores', () {
      final x1 = <double>[1, 3, 2, 5, 4, 7, 6, 9, 8, 10];
      final alvo = <double>[2, 5, 3, 9, 6, 14, 11, 20, 15, 21];
      final r = Regression.residualize(alvo, [x1])!;
      var produto = 0.0, soma = 0.0;
      for (var i = 0; i < r.length; i++) {
        produto += r[i] * x1[i];
        soma += r[i];
      }
      expect(produto, closeTo(0.0, 1e-9));
      expect(soma, closeTo(0.0, 1e-9));
    });
  });

  group('Regression.summarize', () {
    test('média, desvio e t de uma série conhecida', () {
      final s = Regression.summarize([0.1, 0.2, 0.3, 0.4, 0.5])!;
      expect(s.mean, closeTo(0.3, 1e-12));
      // desvio amostral de {0,1..0,5} é 0,1581138830...
      expect(s.sd, closeTo(0.15811388300841897, 1e-12));
      expect(s.t, closeTo(0.3 / (0.15811388300841897 / 2.23606797749979), 1e-9));
      expect(s.positive, 5);
    });
  });
}
