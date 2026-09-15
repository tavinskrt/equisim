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

  /// `t` da média de uma série de coeficientes de coorte com erro-padrão de
  /// Newey-West (item C1a).
  ///
  /// Coortes anuais medidas em 36 meses se sobrepõem por dois anos, e o
  /// retorno de uma carrega o choque das duas vizinhas: os coeficientes saem
  /// autocorrelados, e o `t` de [summarize] superestima a confiança. A variância
  /// de longo prazo soma as autocovariâncias até [lags], com o núcleo de
  /// Bartlett `w_j = 1 − j/(L+1)`, que a mantém não negativa:
  ///
  /// ```
  /// V̂(média) = [γ₀ + 2 Σ_{j=1}^{L} w_j γ_j] / k · k/(k−1)
  /// γ_j = (1/k) Σ_{t=j+1}^{k} (x_t − x̄)(x_{t−j} − x̄)
  /// ```
  ///
  /// O fator `k/(k−1)` faz `lags = 0` devolver exatamente o `t` de
  /// [summarize] — é a conferência de que as duas contas são a mesma no caso
  /// sem sobreposição. A ordem dos valores é a das coortes: **a série tem de
  /// vir em ordem de data**.
  ///
  /// Devolve `null` com menos de duas coortes ou variância não positiva.
  static ({double mean, double se, double t, int n, int lags})? neweyWestMean(
    List<double> values,
    int lags,
  ) {
    final v = [for (final x in values) if (x.isFinite) x];
    final k = v.length;
    if (k < 2 || lags < 0) return null;
    var s = 0.0;
    for (final x in v) {
      s += x;
    }
    final m = s / k;
    double gama(int j) {
      var soma = 0.0;
      for (var t = j; t < k; t++) {
        soma += (v[t] - m) * (v[t - j] - m);
      }
      return soma / k;
    }

    final l = lags < k ? lags : k - 1;
    var lrv = gama(0);
    for (var j = 1; j <= l; j++) {
      lrv += 2 * (1 - j / (l + 1)) * gama(j);
    }
    final variancia = lrv / k * k / (k - 1);
    if (!(variancia > 0) || !variancia.isFinite) return null;
    final se = math.sqrt(variancia);
    return (mean: m, se: se, t: m / se, n: k, lags: l);
  }

  /// `t` da média de uma série de coeficientes de coorte **corrigido pela
  /// estrutura da sobreposição**, e não estimado dela (item C1c).
  ///
  /// Coortes trimestrais medidas em 36 meses compartilham até 33 meses de
  /// retorno: a coorte `t` e a `t+j` têm correlação `ρ_j = 1 − j/(L+1)` quando o
  /// que as move são choques independentes mês a mês, com `L = h/Δ − 1`
  /// sobreposições. É a correlação que a sobreposição **produz**, antes de
  /// qualquer persistência do sinal. Sob ela, duas coisas erram no `t` de
  /// [summarize], e as duas são contas fechadas em `k` e `L`:
  ///
  /// ```
  /// E[s²] = σ² · c,   c = 1 − 2/(k(k−1)) · Σ_{j=1}^{L} (k−j) ρ_j
  /// V(média) = σ²/k · F,   F = 1 + 2 Σ_{j=1}^{L} (1 − j/k) ρ_j
  /// t corrigido = t de summarize · √(c/F)
  /// ```
  ///
  /// **Por que ao lado do Newey-West, e não no lugar.** O Newey-West estima as
  /// autocovariâncias da própria série, e com 22 coortes e 11 defasagens a
  /// estimativa é ruído — com cinco coortes anuais ela saiu negativa e
  /// estreitou o erro (decisão 93). Esta correção não estima nada: vale o que a
  /// sobreposição impõe, e o critério do R3 fica com o menor dos dois.
  ///
  /// Com `L = 0` devolve o `t` de [summarize]. Devolve `null` com menos de duas
  /// coortes, `L` negativo ou desvio nulo.
  static ({double t, double c, double f, int n, int overlap})? overlapAdjustedT(
    List<double> values,
    int overlap,
  ) {
    final base = summarize(values);
    if (base == null || overlap < 0 || !base.t.isFinite) return null;
    final k = base.n;
    final l = overlap < k ? overlap : k - 1;
    var somaC = 0.0, somaF = 0.0;
    for (var j = 1; j <= l; j++) {
      final rho = 1 - j / (l + 1);
      somaC += (k - j) * rho;
      somaF += (1 - j / k) * rho;
    }
    final c = 1 - 2 / (k * (k - 1)) * somaC;
    final f = 1 + 2 * somaF;
    if (!(c > 0) || !(f > 0)) return null;
    return (t: base.t * math.sqrt(c / f), c: c, f: f, n: k, overlap: l);
  }

  /// Nível unilateral de `t > 2` sob a normal: `1 − Φ(2)`. É o que o critério
  /// do R3 pede, escrito como probabilidade.
  static const double r3Tail = 0.022750131948179195;

  static final Map<String, List<double>> _nulas = {};

  /// Distribuição, sob a hipótese nula, do `t` de [overlapAdjustedT] para `k`
  /// coortes com `L` sobreposições: [draws] séries de somas sobrepostas de
  /// choques normais independentes, média zero, ordenadas.
  ///
  /// **Por que simular.** A correção acerta a variância da média, mas o desvio
  /// no denominador tem poucos graus de liberdade efetivos, e o `t` corrigido
  /// tem cauda mais pesada que a normal — medido: o percentil 95 de `|t|` é
  /// 2,66 com 22 coortes e 11 sobreposições, e 3,14 com cinco coortes anuais e
  /// duas. O limiar de `t > 2` tem de vir da mesma distribuição. A semente é
  /// fixa: o crítico é o mesmo em toda execução.
  static List<double> overlapNull(int k, int overlap,
      {int draws = 20000, int seed = 20260915}) {
    final l = overlap < k ? overlap : k - 1;
    return _nulas['$k|$l|$draws|$seed'] ??= () {
      final rng = SplitMix64(seed);
      double normal() {
        // Box-Muller: u em (0, 1] para o logaritmo.
        final u = 1 - rng.nextDouble();
        final v = rng.nextDouble();
        return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
      }

      final out = <double>[];
      final choques = List<double>.filled(k + l, 0);
      while (out.length < draws) {
        for (var i = 0; i < choques.length; i++) {
          choques[i] = normal();
        }
        final serie = [
          for (var t = 0; t < k; t++)
            [for (var m = t; m <= t + l; m++) choques[m]]
                .fold<double>(0, (a, b) => a + b),
        ];
        final r = overlapAdjustedT(serie, l);
        if (r != null && r.t.isFinite) out.add(r.t);
      }
      return out..sort();
    }();
  }

  /// Crítico unilateral do `t` corrigido com o nível de [tail] — por padrão, o
  /// de `t > 2` sob a normal.
  static double overlapCritical(int k, int overlap, {double tail = r3Tail}) {
    final nula = overlapNull(k, overlap);
    final i = ((1 - tail) * nula.length).floor().clamp(0, nula.length - 1);
    return nula[i];
  }

  /// Probabilidade unilateral, sob a nula da sobreposição, de um `t` corrigido
  /// pelo menos tão alto quanto [t].
  static double overlapPValue(double t, int k, int overlap) {
    final nula = overlapNull(k, overlap);
    var lo = 0, hi = nula.length;
    while (lo < hi) {
      final m = (lo + hi) ~/ 2;
      if (nula[m] < t) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    return (nula.length - lo) / nula.length;
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

/// Gerador splitmix64, escrito igual em `tool/recusas_custo.py`.
///
/// O crítico da sobreposição sai de uma simulação, e o Dart e o Python têm de
/// chegar ao mesmo número: `math.Random` e o `random` do Python são geradores
/// diferentes. Este é pequeno, de período 2⁶⁴ e com a mesma sequência nos dois.
class SplitMix64 {
  SplitMix64(int seed) : _estado = seed;
  int _estado;

  /// Próximo inteiro de 64 bits, com a aritmética modular do inteiro nativo.
  int nextInt() {
    _estado += 0x9E3779B97F4A7C15;
    var z = _estado;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Uniforme em [0, 1), com os 53 bits altos.
  double nextDouble() => (nextInt() >>> 11) * (1.0 / 9007199254740992);
}
