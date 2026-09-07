import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

import 'context.dart';

/// Exporta as primitivas estatísticas do núcleo para conferência externa.
///
/// **Por que existe.** O argumento que sustenta a estatística deste trabalho é
/// que o Dart não tem NumPy nem SciPy, e por isso tudo que foi implementado à
/// mão é recalculado em Python e comparado — ver
/// [`cross_validation.py`](../../docs/validacao/cross_validation.py).
///
/// Esse argumento tinha um buraco: `inference.dart` chegou com a decisão 25
/// trazendo OLS, erro-padrão Newey-West com núcleo de Bartlett, quantil da t de
/// Student e R² crítico, e **nenhum deles** era conferido por fora. Os quantis
/// da t e o R² crítico batiam contra tabela publicada nos testes; o HAC não
/// tinha conferência alguma.
///
/// Este exportador fecha o buraco. Ele gera séries sintéticas **determinísticas**
/// — sem relógio, sem gerador do sistema — roda as primitivas sobre elas e grava
/// os dados **junto** dos resultados. O Python lê os mesmos números e recalcula
/// com `statsmodels` e `scipy.stats`.
///
/// Gravar o dado junto do resultado é deliberado: se cada lado gerasse a própria
/// amostra, a comparação dependeria de dois geradores pseudoaleatórios
/// produzirem a mesma sequência, o que é frágil e não tem nada a ver com o que
/// se quer provar.
abstract final class InferenceExport {
  /// Executa a exportação e escreve o arquivo.
  ///
  /// - [outputDir]: destino do arquivo.
  static void run({required String outputDir}) {
    final casos = <Map<String, dynamic>>[];

    // Regressões: da quase determinística à quase pura de ruído, mais uma com
    // autocorrelação forte nos resíduos, que é o caso que o HAC existe para
    // tratar. Os tamanhos cobrem a faixa real da série de exercícios (8 a 16).
    final desenhos = <_Design>[
      const _Design('tendencia limpa', n: 16, slope: 0.08, noise: 0.01, rho: 0.0),
      const _Design('tendencia ruidosa', n: 16, slope: 0.08, noise: 0.12, rho: 0.0),
      const _Design('serie curta', n: 8, slope: 0.05, noise: 0.06, rho: 0.0),
      const _Design('residuo autocorrelacionado',
          n: 16, slope: 0.06, noise: 0.08, rho: 0.7),
      const _Design('sem tendencia', n: 14, slope: 0.0, noise: 0.10, rho: 0.0),
      const _Design('inclinacao negativa',
          n: 12, slope: -0.04, noise: 0.05, rho: 0.3),
    ];

    for (final d in desenhos) {
      final xs = [for (var i = 0; i < d.n; i++) i.toDouble()];
      final ys = d.build();
      final fit = Inference.ols(xs, ys);
      if (fit == null) continue;
      casos.add({
        'nome': d.name,
        'x': xs,
        'y': ys,
        'dart': {
          'slope': fit.slope,
          'intercept': fit.intercept,
          'r2': fit.r2,
          'slopeStdError': fit.slopeStdError,
          'residualStdError': fit.residualStdError,
          'sxx': fit.sxx,
          'hacSlopeStdError': Inference.hacSlopeStdError(xs, fit),
        },
      });
    }

    // Mediana e MAD escalado, incluindo amostra contaminada — que é o motivo de
    // o MAD existir no lugar do desvio-padrão.
    final amostras = <String, List<double>>{
      'simetrica': [0.10, 0.12, 0.14, 0.16, 0.18],
      'par': [0.10, 0.12, 0.14, 0.16],
      'contaminada': [0.10, 0.12, 0.14, 0.16, 9.90],
      'com negativos': [-0.30, -0.05, 0.02, 0.11, 0.40, 0.55],
      'constante': [0.07, 0.07, 0.07, 0.07],
    };
    final robustez = <Map<String, dynamic>>[
      for (final e in amostras.entries)
        {
          'nome': e.key,
          'valores': e.value,
          'dart': {
            'mediana': Inference.median(e.value),
            'madEscalado': Inference.scaledMad(e.value),
          },
        }
    ];

    // Quantis da t e R² crítico na faixa que as guardas usam.
    final quantis = <Map<String, dynamic>>[
      for (final p in [0.90, 0.95, 0.975, 0.995])
        for (final df in [4, 6, 10, 14, 20, 30])
          {'p': p, 'df': df, 'dart': Inference.studentT(p, df)}
    ];
    final r2crit = <Map<String, dynamic>>[
      for (final alpha in [0.01, 0.05, 0.10, 0.20])
        for (final n in [6, 8, 10, 12, 14, 16])
          {'n': n, 'alpha': alpha, 'dart': Inference.criticalR2(n, alpha)}
    ];

    final payload = {
      'gerado_por': 'tool/validation/inference_export.dart',
      'observacao': 'Dados e resultados do Dart. O Python recalcula sobre os '
          'MESMOS dados — nenhum gerador aleatório é compartilhado.',
      'regressoes': casos,
      'robustez': robustez,
      'quantis_t': quantis,
      'r2_critico': r2crit,
      'bartlett_lag_formula': 'L = floor(4 * (n/100)^(2/9))',
    };

    writeReport(
      '$outputDir/inferencia_nucleo.json',
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}

/// Desenho de uma série sintética, gerada sem qualquer fonte de aleatoriedade
/// do sistema.
class _Design {
  final String name;
  final int n;
  final double slope;
  final double noise;

  /// Autocorrelação de primeira ordem imposta ao resíduo.
  final double rho;

  const _Design(
    this.name, {
    required this.n,
    required this.slope,
    required this.noise,
    required this.rho,
  });

  /// Constrói a série em log-nível: `y_i = 1 + slope·i + e_i`.
  ///
  /// O resíduo vem de um gerador congruencial escrito aqui, com semente fixa:
  /// `dart:math` tem `Random(seed)`, mas sua sequência é detalhe de
  /// implementação da plataforma e não é contrato entre versões. Um gerador de
  /// quatro linhas, escrito no arquivo, torna a série reproduzível para sempre —
  /// e o que se quer provar não tem nada a ver com a qualidade do ruído.
  List<double> build() {
    var estado = 20260907;
    double proximo() {
      estado = (estado * 1103515245 + 12345) & 0x7FFFFFFF;
      return estado / 0x7FFFFFFF * 2 - 1; // em [-1, 1]
    }

    final ys = <double>[];
    var anterior = 0.0;
    for (var i = 0; i < n; i++) {
      final choque = proximo() * noise;
      final e = rho * anterior + choque;
      anterior = e;
      ys.add(1.0 + slope * i + e);
    }
    return ys;
  }
}
