// Regressão múltipla e estatística de ordem para os utilitários de validação.
//
// **Por que não está no núcleo.** `Inference` resolve regressão **simples** —
// é o que as guardas da decisão 25 pedem, e ampliá-la para o caso multivariado
// acrescentaria superfície ao motor por necessidade que é de análise, não de
// avaliação. O núcleo continua com o que a cascata usa.
//
// **Por que não é NumPy.** A máquina do projeto não tem o ecossistema
// científico de Python instalado — conferido em 09/09/2026: nem `numpy`, nem
// `scipy`, nem `statsmodels`. A conferência cruzada que a §2.10 das limitações
// descreve não pôde ser estendida a este arquivo, e isso está declarado no
// relatório que ele alimenta.
//
// O tamanho do problema aqui é pequeno — quatro colunas, algumas centenas de
// linhas — e a solução por equações normais com pivoteamento parcial é exata o
// bastante. Não use isto para sistema mal condicionado sem conferir antes.
import 'dart:math' as math;

/// Saída de uma regressão múltipla `y = b0 + Σ bj·xj`.
class MultiOls {
  /// Coeficientes, com o intercepto na posição 0.
  final List<double> coefficients;

  /// Erros-padrão, alinhados com [coefficients].
  final List<double> stdErrors;

  /// Estatísticas t, alinhadas com [coefficients].
  final List<double> tStats;

  /// Coeficiente de determinação.
  final double r2;

  /// Observações usadas.
  final int n;

  /// Resíduos, alinhados com a entrada.
  final List<double> residuals;

  const MultiOls({
    required this.coefficients,
    required this.stdErrors,
    required this.tStats,
    required this.r2,
    required this.n,
    required this.residuals,
  });
}

/// Estatística que os utilitários de validação compartilham.
class Regression {
  /// Postos médios, com empate resolvido pela média das posições.
  ///
  /// Empate é a regra e não a exceção nestes dados: potencial recusado,
  /// fator ausente e retorno truncado produzem valores repetidos, e atribuir
  /// posições arbitrárias a eles enviesaria a correlação.
  static List<double> ranks(List<double> values) {
    final n = values.length;
    final idx = List<int>.generate(n, (i) => i)
      ..sort((a, b) => values[a].compareTo(values[b]));
    final out = List<double>.filled(n, 0);
    var i = 0;
    while (i < n) {
      var j = i;
      // `compareTo` e não `==`: o empate que interessa é o que a **ordenação
      // acima** considerou empate, e é `compareTo` que a define. Além de
      // evitar igualdade estrita de ponto flutuante, ele dá tratamento
      // determinístico a `-0.0` contra `0.0` e a `NaN`, que com `==` cairiam
      // em posições dependentes da ordem de entrada.
      while (j + 1 < n && values[idx[j + 1]].compareTo(values[idx[i]]) == 0) {
        j++;
      }
      final media = (i + j) / 2 + 1;
      for (var k = i; k <= j; k++) {
        out[idx[k]] = media;
      }
      i = j + 1;
    }
    return out;
  }

  /// Correlação de Pearson. `null` sem dispersão em qualquer das séries.
  static double? pearson(List<double> xs, List<double> ys) {
    final n = xs.length;
    if (n < 3 || ys.length != n) return null;
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += xs[i];
      sy += ys[i];
    }
    final mx = sx / n, my = sy / n;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx, dy = ys[i] - my;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
    }
    if (sxx <= 0 || syy <= 0) return null;
    return sxy / math.sqrt(sxx * syy);
  }

  /// Correlação de ordem de Spearman — Pearson sobre os postos.
  static double? spearman(List<double> xs, List<double> ys) =>
      pearson(ranks(xs), ranks(ys));

  /// Postos reescalados para média zero e desvio um.
  ///
  /// É a forma em que os coeficientes de uma coorte são comparáveis com os de
  /// outra: sem isso, o coeficiente carrega o tamanho da seção transversal.
  static List<double> standardizedRanks(List<double> values) {
    final r = ranks(values);
    final n = r.length;
    // Com `n = 1` a variância divide por zero e devolve `NaN`, e o teste
    // `sd <= 0` abaixo **não** o pega: em IEEE-754 toda comparação com `NaN`
    // é falsa. O retorno seria uma lista de `NaN` que contamina em silêncio
    // todo somatório a jusante.
    if (n < 2) return List<double>.filled(n, 0);
    var s = 0.0;
    for (final v in r) {
      s += v;
    }
    final m = s / n;
    var ss = 0.0;
    for (final v in r) {
      ss += (v - m) * (v - m);
    }
    final sd = math.sqrt(ss / (n - 1));
    if (sd <= 0) return List<double>.filled(n, 0);
    return [for (final v in r) (v - m) / sd];
  }

  /// Mínimos quadrados com intercepto, por equações normais.
  ///
  /// - [columns]: regressores, cada um com [n] observações.
  /// - [y]: resposta.
  ///
  /// Devolve `null` quando não há graus de liberdade ou o sistema é singular —
  /// o que aqui significa regressor constante ou colinearidade exata.
  static MultiOls? ols(List<List<double>> columns, List<double> y) {
    final n = y.length;
    final k = columns.length + 1;
    if (n <= k) return null;
    for (final c in columns) {
      if (c.length != n) return null;
    }

    // X'X e X'y, com a coluna de uns na posição 0.
    double x(int j, int i) => j == 0 ? 1.0 : columns[j - 1][i];

    final xtx = [
      for (var a = 0; a < k; a++) List<double>.filled(k, 0),
    ];
    final xty = List<double>.filled(k, 0);
    for (var a = 0; a < k; a++) {
      for (var b = 0; b < k; b++) {
        var s = 0.0;
        for (var i = 0; i < n; i++) {
          s += x(a, i) * x(b, i);
        }
        xtx[a][b] = s;
      }
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        s += x(a, i) * y[i];
      }
      xty[a] = s;
    }

    final inv = _inverse(xtx);
    if (inv == null) return null;

    final beta = List<double>.filled(k, 0);
    for (var a = 0; a < k; a++) {
      var s = 0.0;
      for (var b = 0; b < k; b++) {
        s += inv[a][b] * xty[b];
      }
      beta[a] = s;
    }

    var sy = 0.0;
    for (final v in y) {
      sy += v;
    }
    final my = sy / n;
    var sse = 0.0, sst = 0.0;
    final res = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var yhat = 0.0;
      for (var a = 0; a < k; a++) {
        yhat += beta[a] * x(a, i);
      }
      final e = y[i] - yhat;
      res[i] = e;
      sse += e * e;
      sst += (y[i] - my) * (y[i] - my);
    }
    final sigma2 = sse / (n - k);
    final se = [for (var a = 0; a < k; a++) math.sqrt(sigma2 * inv[a][a])];

    return MultiOls(
      coefficients: beta,
      stdErrors: se,
      tStats: [
        for (var a = 0; a < k; a++) se[a] > 0 ? beta[a] / se[a] : double.nan,
      ],
      r2: sst > 0 ? 1 - sse / sst : double.nan,
      n: n,
      residuals: res,
    );
  }

  /// Resíduo de [target] depois de projetá-lo em [columns].
  ///
  /// É o que isola a informação **própria** de um ordenador: o que sobra dele
  /// quando o que os outros explicam já foi retirado.
  static List<double>? residualize(
    List<double> target,
    List<List<double>> columns,
  ) =>
      ols(columns, target)?.residuals;

  /// Média, desvio e `t` de uma série de coeficientes de coorte.
  ///
  /// É o segundo passo de Fama-MacBeth. **O `t` supõe coortes independentes**,
  /// e janelas de 36 meses medidas de ano em ano se sobrepõem em dois terços —
  /// quem o lê precisa da ressalva junto.
  static ({double mean, double sd, double t, int n, int positive})? summarize(
    List<double> values,
  ) {
    final v = [for (final x in values) if (x.isFinite) x];
    if (v.length < 2) return null;
    var s = 0.0;
    for (final x in v) {
      s += x;
    }
    final m = s / v.length;
    var ss = 0.0;
    for (final x in v) {
      ss += (x - m) * (x - m);
    }
    final sd = math.sqrt(ss / (v.length - 1));
    return (
      mean: m,
      sd: sd,
      t: sd > 0 ? m / (sd / math.sqrt(v.length)) : double.nan,
      n: v.length,
      positive: v.where((x) => x > 0).length,
    );
  }

  /// Inversa por Gauss-Jordan com pivoteamento parcial. `null` se singular.
  static List<List<double>>? _inverse(List<List<double>> a) {
    final n = a.length;
    final m = [
      for (var i = 0; i < n; i++)
        [
          ...a[i],
          for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0,
        ],
    ];
    for (var c = 0; c < n; c++) {
      var piv = c;
      for (var r = c + 1; r < n; r++) {
        if (m[r][c].abs() > m[piv][c].abs()) piv = r;
      }
      if (m[piv][c].abs() < 1e-12) return null;
      final tmp = m[c];
      m[c] = m[piv];
      m[piv] = tmp;
      final d = m[c][c];
      for (var j = 0; j < 2 * n; j++) {
        m[c][j] /= d;
      }
      for (var r = 0; r < n; r++) {
        if (r == c) continue;
        // Sem atalho para multiplicador nulo: pular exigiria comparar um
        // `double` com zero, e a subtração de `0 · x` não custa nada numa
        // matriz desta ordem. O atalho era economia de nada paga com
        // igualdade estrita de ponto flutuante.
        final f = m[r][c];
        for (var j = 0; j < 2 * n; j++) {
          m[r][j] -= f * m[c][j];
        }
      }
    }
    return [
      for (var i = 0; i < n; i++) m[i].sublist(n),
    ];
  }
}
