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
import 'dart:math' as math;

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

  group('Regression.neweyWestMean — item C1a', () {
    test('sem defasagem é exatamente o t de summarize', () {
      final v = <double>[0.12, -0.03, 0.08, 0.15, 0.02, 0.07];
      final ingenuo = Regression.summarize(v)!;
      final nw = Regression.neweyWestMean(v, 0)!;
      expect(nw.mean, closeTo(ingenuo.mean, 1e-15));
      expect(nw.t, closeTo(ingenuo.t, 1e-12));
    });

    test('reproduz a conta à mão com uma defasagem', () {
      // {1..5}: média 3; γ₀ = 10/5 = 2; γ₁ = (2 + 0 + 0 + 2)/5 = 0,8;
      // w₁ = 1/2; variância de longo prazo 2 + 2·½·0,8 = 2,8; da média,
      // 2,8/5 · 5/4 = 0,7.
      final nw = Regression.neweyWestMean([1, 2, 3, 4, 5], 1)!;
      expect(nw.se, closeTo(0.8366600265340756, 1e-12));
      expect(nw.t, closeTo(3 / 0.8366600265340756, 1e-12));
    });

    test('autocorrelação positiva alarga o erro, e a negativa estreita', () {
      final persistente = <double>[0.1, 0.12, 0.11, 0.3, 0.32, 0.31];
      final alternada = <double>[0.1, 0.3, 0.1, 0.3, 0.1, 0.3];
      expect(Regression.neweyWestMean(persistente, 2)!.se,
          greaterThan(Regression.neweyWestMean(persistente, 0)!.se));
      expect(Regression.neweyWestMean(alternada, 1)!.se,
          lessThan(Regression.neweyWestMean(alternada, 0)!.se));
    });

    test('defasagem além da série é truncada, e uma coorte não tem t', () {
      expect(Regression.neweyWestMean([0.1, 0.2, 0.4], 9)!.lags, 2);
      expect(Regression.neweyWestMean([0.1], 0), isNull);
    });
  });

  group('Regression.overlapAdjustedT — item C1c', () {
    test('sem sobreposição é exatamente o t de summarize', () {
      final v = <double>[0.12, -0.03, 0.08, 0.15, 0.02, 0.07];
      expect(Regression.overlapAdjustedT(v, 0)!.t,
          closeTo(Regression.summarize(v)!.t, 1e-12));
    });

    test('reproduz c e F à mão com cinco coortes anuais de 36 meses', () {
      // ρ₁ = 2/3, ρ₂ = 1/3.
      // c = 1 − 2/(5·4)·(4·2/3 + 3·1/3) = 1 − 0,1·11/3 = 19/30.
      // F = 1 + 2·(4/5·2/3 + 3/5·1/3) = 1 + 2·(8/15 + 3/15) = 37/15.
      final v = <double>[0.12, -0.03, 0.08, 0.15, 0.02];
      final r = Regression.overlapAdjustedT(v, 2)!;
      expect(r.c, closeTo(19 / 30, 1e-12));
      expect(r.f, closeTo(37 / 15, 1e-12));
      expect(r.t,
          closeTo(Regression.summarize(v)!.t * math.sqrt((19 / 30) / (37 / 15)),
              1e-12));
    });

    test('o crítico mantém o nível sob séries sobrepostas de outro gerador', () {
      // Nula construída por outro caminho — somas parciais e diferenças, com
      // outra semente —, e não pela mesma função que gera o crítico.
      const k = 22, l = 11, series = 3000;
      final rng = math.Random(4242);
      double normal() {
        final u = 1 - rng.nextDouble();
        return math.sqrt(-2 * math.log(u)) *
            math.cos(2 * math.pi * rng.nextDouble());
      }

      final critico = Regression.overlapCritical(k, l, tail: 0.05);
      var rejeita = 0, rejeitaIngenuo = 0;
      for (var s = 0; s < series; s++) {
        final acumulada = <double>[0];
        for (var i = 0; i < k + l; i++) {
          acumulada.add(acumulada.last + normal());
        }
        final x = [
          for (var t = 0; t < k; t++) acumulada[t + l + 1] - acumulada[t],
        ];
        if (Regression.overlapAdjustedT(x, l)!.t > critico) rejeita++;
        if (Regression.summarize(x)!.t > 1.645) rejeitaIngenuo++;
      }
      // Erro de Monte Carlo de 0,4 p.p.: a banda é de três desvios.
      expect(rejeita / series, inInclusiveRange(0.038, 0.062));
      // E o t de sempre rejeita a nula verdadeira muito mais que 5%.
      expect(rejeitaIngenuo / series, greaterThan(0.2));
    });

    test('sem sobreposição, o crítico é o quantil da t de Student', () {
      // Com L = 0 o t corrigido é o t de sempre, e a nula dele é a t de Student
      // com k − 1 graus de liberdade: 2,5165 para seis, no nível de t > 2 sob a
      // normal — integrado à parte, e não pela simulação.
      expect(Regression.overlapCritical(7, 0), closeTo(2.5165, 0.05));
    });

    test('o gerador é o splitmix64 de referência, igual ao do Python', () {
      final g = SplitMix64(0);
      expect(g.nextInt(), 0xE220A8397B1DCDAF);
      expect(g.nextInt(), 0x6E789E6AA1B965F4);
      expect(g.nextInt(), 0x06C45D188009454F);
    });

    test('o p-valor sobe quando o t cai, e o crítico é o do nível pedido', () {
      final critico = Regression.overlapCritical(22, 11);
      expect(Regression.overlapPValue(critico, 22, 11),
          closeTo(Regression.r3Tail, 0.002));
      expect(Regression.overlapPValue(0, 22, 11), closeTo(0.5, 0.02));
      expect(critico, greaterThan(2));
    });
  });
}
