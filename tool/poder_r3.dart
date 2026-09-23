// O poder do teste do R3: que habilidade o critério da decisão 96 conseguiria
// ver com a amostra que há (itens C1 e C6).
//
// O R3 reprovou: nenhuma das cinco ordenações passa. Isso só diz algo sobre o
// motor se o teste **pudesse** ter passado — um teste que só detecta efeitos
// que nenhum preditor real tem reprova tudo, e a reprovação não distingue
// «não há habilidade» de «não dá para ver». Esta ferramenta mede a diferença.
//
// **O modelo.** A série de coeficientes de coorte é `μ + e_t`, com `e_t` a soma
// de `L + 1` choques normais independentes — a estrutura que a sobreposição de
// coortes trimestrais produz, e a mesma da nula de
// `Regression.overlapNull`. O desvio de `e_t` sai do observado em cada
// ordenação, **corrigido pela sobreposição**: sob ela `E[s²] = σ²·c`, e usar o
// `s` cru subestimaria o ruído e inflaria o poder. `μ` é o efeito verdadeiro. Para cada `μ`, o poder é a fração de
// séries simuladas em que o critério da decisão 96 passa: `t` corrigido acima
// do crítico simulado **e** Newey-West acima de 2.
//
// Três leituras por ordenação:
//
// - **efeito mínimo detectável** (80% de poder) com as coortes que há;
// - **limite superior** do efeito, unilateral, ao nível do próprio critério:
//   o maior `μ` que a amostra não consegue descartar;
// - **quantas coortes** o teste pediria para detectar, a 80%, um efeito igual à
//   média observada — e em que ano os retornos delas estariam disponíveis.
//
// Semente fixa: o mesmo número em toda execução.
//
// Uso:
//   dart run tool/regressao_condicional.dart --trimestral   # a série, se faltar
//   dart run tool/poder_r3.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'validation/regression.dart';

const _fonte = 'docs/validacao/habilidade_trimestral.json';
const _saida = 'docs/validacao/poder_r3.json';

/// Sorteios por avaliação de poder.
const _sorteios = 4000;
const _semente = 20260922;

/// Primeira coorte trimestral do backtest.
final _primeira = DateTime.utc(2018, 3, 31);

/// Ordenações medidas, com o campo por coorte em `habilidade_trimestral.json`.
const _ordenacoes = {
  'potencialDadoBm': 'coefPotencialDadoBm',
  'icPotencial': 'icPotencial',
  'icBookToMarket': 'icBookToMarket',
  'icEarningsYield': 'icEarningsYield',
  'icComposto': 'icComposto',
};

/// Normal padrão pelo gerador compartilhado com a nula.
class _Normal {
  _Normal(int seed) : _rng = SplitMix64(seed);
  final SplitMix64 _rng;
  double next() {
    final u = 1 - _rng.nextDouble();
    final v = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }
}

/// Fração de séries simuladas em que o critério do R3 passa.
double poder({
  required double mu,
  required double desvio,
  required int k,
  required int overlap,
  required double critico,
  int seed = _semente,
}) {
  final z = _Normal(seed);
  final escala = desvio / math.sqrt(overlap + 1);
  final choques = List<double>.filled(k + overlap, 0);
  var passa = 0;
  for (var s = 0; s < _sorteios; s++) {
    for (var i = 0; i < choques.length; i++) {
      choques[i] = z.next();
    }
    final serie = <double>[
      for (var t = 0; t < k; t++)
        mu +
            escala *
                [for (var m = t; m <= t + overlap; m++) choques[m]]
                    .fold<double>(0, (a, b) => a + b),
    ];
    final sob = Regression.overlapAdjustedT(serie, overlap);
    final nw = Regression.neweyWestMean(serie, overlap);
    if (sob != null && nw != null && sob.t > critico && nw.t > 2) passa++;
  }
  return passa / _sorteios;
}

/// O menor `μ` com poder de pelo menos [alvo], por bisseção. O poder é
/// monótono em `μ` porque a mesma semente reusa os mesmos choques.
double efeitoMinimo({
  required double desvio,
  required int k,
  required int overlap,
  required double critico,
  double alvo = 0.8,
}) {
  var lo = 0.0, hi = 4 * desvio;
  for (var i = 0; i < 30; i++) {
    final m = (lo + hi) / 2;
    final p = poder(
        mu: m, desvio: desvio, k: k, overlap: overlap, critico: critico);
    if (p < alvo) {
      lo = m;
    } else {
      hi = m;
    }
  }
  return hi;
}

/// Data em que a coorte de índice [k] (base 1) tem o retorno do horizonte.
DateTime disponivelEm(int k, int meses) {
  final trimestres = k - 1 + meses ~/ 3;
  final ano = _primeira.year + (_primeira.month - 1 + 3 * trimestres) ~/ 12;
  final mes = (_primeira.month - 1 + 3 * trimestres) % 12 + 1;
  return DateTime.utc(ano, mes + 1, 0);
}

Map<String, Object?> horizonte(
    Map<String, dynamic> amostra, int meses, int overlap) {
  final porCoorte =
      (amostra['porCoorte'] as List).cast<Map<String, dynamic>>();
  final out = <String, Object?>{};
  for (final e in _ordenacoes.entries) {
    final serie = [
      for (final c in porCoorte)
        if (c[e.value] is num) (c[e.value] as num).toDouble(),
    ];
    final base = Regression.summarize(serie);
    final sob = Regression.overlapAdjustedT(serie, overlap);
    if (base == null || sob == null) continue;
    final k = base.n;
    final critico = Regression.overlapCritical(k, overlap);
    // Erro da média corrigido pela sobreposição: t_corrigido = média ÷ erro.
    final erro = base.sd / math.sqrt(k) * math.sqrt(sob.f / sob.c);
    // σ da série sob a sobreposição: o `s` observado tem esperança `σ·√c`.
    final sigma = base.sd / math.sqrt(sob.c);
    final mde =
        efeitoMinimo(desvio: sigma, k: k, overlap: overlap, critico: critico);

    // Quantas coortes para ver, a 80%, um efeito igual à média observada.
    int? coortesNecessarias;
    if (base.mean > 0) {
      for (var kk = k; kk <= k + 4 * 40; kk += 4) {
        final c = Regression.overlapCritical(kk, overlap);
        final p = poder(
            mu: base.mean,
            desvio: sigma,
            k: kk,
            overlap: overlap,
            critico: c);
        if (p >= 0.8) {
          coortesNecessarias = kk;
          break;
        }
      }
    }
    out[e.key] = {
      'coortes': k,
      'media': base.mean,
      'desvioPorCoorte': base.sd,
      'erroCorrigido': erro,
      'tCorrigido': sob.t,
      'critico': critico,
      'sigmaCorrigido': sigma,
      // Conferência: com efeito zero o poder é o nível do teste.
      'poderSemEfeito': poder(
          mu: 0, desvio: sigma, k: k, overlap: overlap, critico: critico),
      'poderNoEfeitoObservado': poder(
          mu: base.mean,
          desvio: sigma,
          k: k,
          overlap: overlap,
          critico: critico),
      'efeitoMinimoDetectavel80': mde,
      'limiteSuperior': base.mean + critico * erro,
      'coortesPara80NoEfeitoObservado': coortesNecessarias,
      'retornosDisponiveisEm': coortesNecessarias == null
          ? null
          : disponivelEm(coortesNecessarias, meses)
              .toIso8601String()
              .substring(0, 10),
    };
  }
  return out;
}

void main() {
  final f = File(_fonte);
  if (!f.existsSync()) {
    stderr.writeln('Falta $_fonte. Rode antes: dart run '
        'tool/regressao_condicional.dart --trimestral');
    exit(2);
  }
  final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> amostra(String h) =>
      ((d[h] as Map<String, dynamic>)['trimestral']
          as Map<String, dynamic>)['comDeslistadas'] as Map<String, dynamic>;

  final resultado = {
    'fonte': _fonte,
    'sorteios': _sorteios,
    'semente': _semente,
    'modelo': 'série de coorte = μ + soma de L+1 choques normais iid, desvio '
        'observado; poder = P(t corrigido > crítico e Newey-West > 2)',
    'h36': horizonte(amostra('h36'), 36, 11),
    'h12': horizonte(amostra('h12'), 12, 3),
  };
  File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(resultado));

  String n(Object? v, [int casas = 3]) =>
      v == null ? '—' : (v as num).toStringAsFixed(casas);
  for (final h in ['h36', 'h12']) {
    stdout.writeln('\n== $h ==');
    stdout.writeln('ordenação          média  σ      erro   nível  poder  '
        'MDE80  lim.sup  coortes  disponível');
    final r = resultado[h] as Map<String, Object?>;
    for (final e in r.entries) {
      final v = e.value as Map<String, Object?>;
      stdout.writeln('${e.key.padRight(17)}  ${n(v['media'])}  '
          '${n(v['sigmaCorrigido'])}  ${n(v['erroCorrigido'])}  '
          '${n(v['poderSemEfeito'], 3)}  ${n(v['poderNoEfeitoObservado'], 2)}   ${n(v['efeitoMinimoDetectavel80'])}  '
          '${n(v['limiteSuperior'])}   ${v['coortesPara80NoEfeitoObservado'] ?? '—'}'
          '      ${v['retornosDisponiveisEm'] ?? '—'}');
    }
  }
  stderr.writeln('\nescrito $_saida');
}
