/// Primitivas de inferência para as guardas da cascata de avaliação.
///
/// **Por que existe.** As guardas da decisão 25 substituem limiares fixos por
/// estatísticas derivadas do próprio ativo, e isso exige regressão, erro-padrão
/// robusto e quantil da t de Student. O `equisim_core` é Dart puro com zero
/// dependências de runtime — travado por `purity_test.dart` —, então nada disso
/// pode vir de pacote.
///
/// **O limite que estas funções não superam.** A série de fundamentos tem no
/// máximo 16 exercícios. Tudo aqui é assintoticamente justificado e nenhum
/// p-valor deve ser lido como probabilidade exata: são estatísticas de
/// **triagem**, calibradas para separar casos, não para inferência publicável.
/// Medido: com `n = 8`, o estimador HAC chegou a inflar `|t|` em 2,2 vezes,
/// porque monta a variância a partir de somas de 6 e 7 termos. É a razão de o
/// teste de tendência rodar sobre a série completa, e não sobre a janela do
/// ciclo.
library;

import 'dart:math' as math;

/// Saída de uma regressão linear simples `y = b0 + b1·x`.
class OlsFit {
  /// Inclinação estimada.
  final double slope;

  /// Intercepto estimado.
  final double intercept;

  /// Resíduos, alinhados posição a posição com a entrada.
  final List<double> residuals;

  /// Coeficiente de determinação.
  final double r2;

  /// Erro-padrão da inclinação, sob homocedasticidade.
  final double slopeStdError;

  /// `Σ(x − x̄)²`. Viaja porque o estimador HAC precisa dele.
  final double sxx;

  /// Erro-padrão da regressão, `√(Σê²/(n−2))`.
  final double residualStdError;

  /// Observações efetivamente usadas.
  final int n;

  const OlsFit({
    required this.slope,
    required this.intercept,
    required this.residuals,
    required this.r2,
    required this.slopeStdError,
    required this.sxx,
    required this.residualStdError,
    required this.n,
  });

  /// Graus de liberdade do teste da inclinação.
  int get degreesOfFreedom => n - 2;
}

/// Estatística descritiva e inferencial sem dependência externa.
abstract final class Inference {
  /// Mediana de [values]. Devolve `null` para lista vazia.
  ///
  /// Preferida à média em toda a cascata: o ponto de ruptura da média é `1/n`,
  /// e o exercício atípico que se quer conter é justamente o que a desloca.
  static double? median(List<double> values) {
    if (values.isEmpty) return null;
    final s = [...values]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// Desvio absoluto mediano escalado, estimador robusto de escala.
  ///
  /// O fator `1,4826 = 1/Φ⁻¹(0,75)` torna o MAD consistente com o desvio-padrão
  /// sob normalidade. Ponto de ruptura de 50%: metade da amostra pode estar
  /// contaminada sem mover o resultado.
  ///
  /// Devolve `null` quando a amostra é curta demais ou colapsa num ponto — caso
  /// em que não há escala a estimar, e o chamador deve tratar como ausência.
  static double? scaledMad(List<double> values) {
    if (values.length < 3) return null;
    final m = median(values);
    if (m == null) return null;
    final desvios = [for (final v in values) (v - m).abs()];
    final mad = median(desvios);
    if (mad == null || mad <= 0) return null;
    final s = 1.4826 * mad;
    return s.isFinite && s > 0 ? s : null;
  }

  /// Regressão linear simples por mínimos quadrados.
  ///
  /// Devolve `null` com menos de três pontos ou sem dispersão em `x`, casos em
  /// que a inclinação não é identificável.
  static OlsFit? ols(List<double> xs, List<double> ys) {
    final n = xs.length;
    if (n < 3 || ys.length != n) return null;

    var mx = 0.0, my = 0.0;
    for (var i = 0; i < n; i++) {
      mx += xs[i];
      my += ys[i];
    }
    mx /= n;
    my /= n;

    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx;
      final dy = ys[i] - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    if (sxx <= 0) return null;

    final b1 = sxy / sxx;
    final b0 = my - b1 * mx;
    final res = [for (var i = 0; i < n; i++) ys[i] - (b0 + b1 * xs[i])];

    var sse = 0.0;
    for (final e in res) {
      sse += e * e;
    }
    final s2 = sse / (n - 2);
    final syx = math.sqrt(s2);
    final seB1 = math.sqrt(s2 / sxx);
    final r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : 0.0;

    if (!b1.isFinite || !seB1.isFinite) return null;
    return OlsFit(
      slope: b1,
      intercept: b0,
      residuals: res,
      r2: r2,
      slopeStdError: seB1,
      sxx: sxx,
      residualStdError: syx,
      n: n,
    );
  }

  /// Erro-padrão da inclinação robusto a heterocedasticidade e autocorrelação.
  ///
  /// Estimador de Newey-West com núcleo de Bartlett:
  ///
  /// ```
  /// V̂(β̂₁) = S_xx⁻¹ · Ω̂ · S_xx⁻¹
  /// Ω̂ = Σ x_t² ê_t² + 2 Σ_{j=1}^{L} w_j Σ_t x_t ê_t x_{t−j} ê_{t−j}
  /// w_j = 1 − j/(L+1)
  /// ```
  ///
  /// A banda segue a regra `L = ⌊4(n/100)^{2/9}⌋`, e Ω̂ recebe a correção de
  /// amostra pequena `n/(n−2)`. Os pesos de Bartlett garantem `Ω̂ ≥ 0`, o que
  /// impede variância negativa — o motivo de o núcleo triangular ser o padrão.
  ///
  /// Devolve `null` quando a variância estimada não é utilizável.
  static double? hacSlopeStdError(List<double> xs, OlsFit fit) {
    final n = fit.n;
    if (xs.length != n || n < 4) return null;

    var mx = 0.0;
    for (final x in xs) {
      mx += x;
    }
    mx /= n;
    final x = [for (final v in xs) v - mx];
    final e = fit.residuals;

    final l = math.max(1, (4 * math.pow(n / 100.0, 2 / 9)).floor());

    var omega = 0.0;
    for (var t = 0; t < n; t++) {
      final xe = x[t] * e[t];
      omega += xe * xe;
    }
    for (var j = 1; j <= l && j < n; j++) {
      final w = 1.0 - j / (l + 1.0);
      var soma = 0.0;
      for (var t = j; t < n; t++) {
        soma += x[t] * e[t] * x[t - j] * e[t - j];
      }
      omega += 2.0 * w * soma;
    }
    omega *= n / (n - 2.0);

    if (omega <= 0 || !omega.isFinite) return null;
    final se = math.sqrt(omega) / fit.sxx;
    return se.isFinite && se > 0 ? se : null;
  }

  /// Quantil da distribuição t de Student com [df] graus de liberdade.
  ///
  /// Obtido invertendo a função beta incompleta regularizada por bissecção.
  /// Conferido contra tabela: `t(14; 0,975) = 2,1448`, `t(6; 0,975) = 2,4469`,
  /// `t(10; 0,95) = 1,8125`.
  ///
  /// - [p]: probabilidade acumulada, em `(0, 1)`.
  /// - [df]: graus de liberdade, ao menos 1.
  static double studentT(double p, int df) {
    if (df < 1 || p <= 0 || p >= 1) return double.nan;
    if (p < 0.5) return -studentT(1 - p, df);

    var lo = 0.0, hi = 1e3;
    for (var i = 0; i < 200; i++) {
      final mid = (lo + hi) / 2;
      if (_tCdf(mid, df) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  static double _tCdf(double t, int df) {
    final x = df / (df + t * t);
    final p = 0.5 * _incompleteBeta(df / 2.0, 0.5, x);
    return t > 0 ? 1.0 - p : p;
  }

  /// Beta incompleta regularizada `I_x(a, b)`, por fração continuada.
  static double _incompleteBeta(double a, double b, double x) {
    if (x <= 0) return 0.0;
    if (x >= 1) return 1.0;
    final lb = _lnGamma(a + b) -
        _lnGamma(a) -
        _lnGamma(b) +
        a * math.log(x) +
        b * math.log(1 - x);
    if (x < (a + 1) / (a + b + 2)) {
      return math.exp(lb) * _betaContinuedFraction(a, b, x) / a;
    }
    return 1.0 - math.exp(lb) * _betaContinuedFraction(b, a, 1 - x) / b;
  }

  static double _betaContinuedFraction(double a, double b, double x) {
    const maxIt = 200, eps = 3e-16, fpMin = 1e-300;
    final qab = a + b, qap = a + 1.0, qam = a - 1.0;
    var c = 1.0;
    var d = 1.0 - qab * x / qap;
    if (d.abs() < fpMin) d = fpMin;
    d = 1.0 / d;
    var h = d;
    for (var m = 1; m <= maxIt; m++) {
      final m2 = 2 * m;
      var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
      d = 1.0 + aa * d;
      if (d.abs() < fpMin) d = fpMin;
      c = 1.0 + aa / c;
      if (c.abs() < fpMin) c = fpMin;
      d = 1.0 / d;
      h *= d * c;
      aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
      d = 1.0 + aa * d;
      if (d.abs() < fpMin) d = fpMin;
      c = 1.0 + aa / c;
      if (c.abs() < fpMin) c = fpMin;
      d = 1.0 / d;
      final del = d * c;
      h *= del;
      if ((del - 1.0).abs() < eps) break;
    }
    return h;
  }

  /// Logaritmo da função gama, por aproximação de Lanczos.
  static double _lnGamma(double x) {
    const cof = <double>[
      76.18009172947146,
      -86.50532032941677,
      24.01409824083091,
      -1.231739572450155,
      0.1208650973866179e-2,
      -0.5395239384953e-5,
    ];
    var y = x;
    final tmp = x + 5.5 - (x + 0.5) * math.log(x + 5.5);
    var ser = 1.000000000190015;
    for (var j = 0; j < 6; j++) {
      ser += cof[j] / ++y;
    }
    return -tmp + math.log(2.5066282746310005 * ser / x);
  }

  /// R² crítico de uma regressão simples, ao nível [alpha].
  ///
  /// Da identidade `F = [R²/(1−R²)]·(n−2)` com um só regressor, `F = t²`, o que
  /// dá em forma fechada:
  ///
  /// ```
  /// R²_crit(n, α) = t² / (t² + n − 2),   t = t_{n−2, 1−α/2}
  /// ```
  ///
  /// Existe para tornar visível por que um limiar fixo não serve: com `n = 8` o
  /// valor é 0,50, e com `n = 16` é 0,25. Um corte único é simultaneamente laxo
  /// numa ponta e estrito na outra.
  static double criticalR2(int n, double alpha) {
    if (n < 3) return 1.0;
    final df = n - 2;
    final t = studentT(1 - alpha / 2, df);
    final t2 = t * t;
    return t2 / (t2 + df);
  }
}
