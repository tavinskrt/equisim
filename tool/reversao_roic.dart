// B19 — a rentabilidade reverte à média? Em quanto tempo, e para onde?
//
// **A pergunta que o B12 deixou.** O terminal neutro mantém, para sempre, o
// retorno que o capital instalado alcança na projeção — e medido, esse retorno
// é de 0,71 vez o custo de capital na mediana
// ([terminal_excedente.md](../docs/validacao/terminal_excedente.md)). A
// [decisão 107](../docs/decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md)
// manteve o número por não haver medição de reversão à média; trocá-lo por
// `capital_N` move +14,1% do preço justo na mediana. Esta é a medição.
//
// **Duas perguntas, e só as duas juntas decidem.**
//
//   1. **Velocidade.** O quanto da vantagem — ou da desvantagem — de um ano
//      sobrevive ao seguinte? Persistência `φ` por AR(1) sobre o spread do
//      `ROIC` contra a mediana transversal do ano, no painel inteiro e ativo a
//      ativo, com a meia-vida que ela implica.
//   2. **Destino.** Reverter **para onde**? Converger o terminal ao custo de
//      capital supõe que a rentabilidade do mercado chega lá. Se a mediana do
//      `ROIC` do universo vive abaixo do custo de capital, convergir o terminal
//      a `r` não é reversão à média — é inventar uma rentabilidade que a seção
//      transversal nunca teve.
//
// **O `ROIC` é o do motor**, de `CapitalSeries.returns`: `lucro_t ÷ base_{t−1}`,
// na convenção da via da firma, sobre a mesma série limpa que a cascata usa.
//
// Uso:
//   dart run tool/gabarito_cascata.dart      # congela a entrada
//   dart run tool/reversao_roic.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/reversao_roic.json';

/// Mínimo de exercícios para um ativo entrar no AR(1) próprio.
///
/// Oito pares: abaixo disso o estimador de `φ` é dominado pelo viés de
/// pequena amostra, que é da ordem de `−(1 + 3φ)/n`.
const _minPeers = 8;

/// Horizontes em que o spread é seguido, em anos.
const _horizons = [1, 3, 5, 10];

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantile(List<double> v, double p) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round()];
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
String _n(double? v, [int c = 3]) => v == null ? '—' : v.toStringAsFixed(c);

/// Meia-vida implícita numa persistência anual: `ln(0,5) ÷ ln(φ)`.
///
/// `null` fora de `(0, 1)`: com `φ` não positivo não há decaimento a medir, e
/// com `φ ≥ 1` não há reversão.
double? _halfLife(double phi) {
  if (!(phi > 0 && phi < 1)) return null;
  const ln2 = 0.6931471805599453;
  return ln2 / -_ln(phi);
}

double _ln(double x) {
  // Série de Newton sobre `exp`, para não trazer `dart:math` só por um log —
  // o núcleo é puro e as ferramentas seguem a mesma economia.
  var y = 0.0;
  for (var i = 0; i < 80; i++) {
    final e = _exp(y);
    y += 2 * (x - e) / (x + e);
  }
  return y;
}

double _exp(double x) {
  var term = 1.0, sum = 1.0;
  for (var i = 1; i < 60; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

Future<void> main() async {
  final c = await Frozen.build();
  try {
    // --- O painel de ROIC, do mesmo jeito que a cascata o lê ---------------
    final seriesOf = <String, Map<int, double>>{};
    final costOf = <String, double>{};
    final evaluated = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final r = ValuationCascade.evaluate(inputs);
      evaluated[t] = r.valueOrNull;
      final cost = r.valueOrNull?.diagnostics?.terminalDiscountRate;
      if (cost != null) costOf[t.value] = cost;

      final published =
          PointInTimeView(frozenToday).published(inputs.fundamentals);
      final series = CapitalSeries.build(published, ValuationLane.firm);
      final returns = series.returns;
      if (returns.length < 3) continue;
      seriesOf[t.value] = {for (final x in returns) x.year: x.value};
    }
    stderr.writeln('');

    final divergent = await c.checkAgainstAnswerKey(evaluated);

    // --- A mediana transversal de cada ano ---------------------------------
    final years = <int>{for (final s in seriesOf.values) ...s.keys}.toList()
      ..sort();
    final yearMedian = <int, double>{};
    final yearCount = <int, int>{};
    for (final year in years) {
      final xs = [
        for (final s in seriesOf.values)
          if (s[year] != null) s[year]!,
      ];
      yearCount[year] = xs.length;
      // Anos de ponta têm poucos papéis, e uma mediana de cinco ativos não é
      // a do mercado: eles entram no painel mas não definem referência.
      if (xs.length >= 20) yearMedian[year] = _median(xs)!;
    }

    // --- O spread contra a mediana do ano ----------------------------------
    final spread = <String, Map<int, double>>{};
    for (final e in seriesOf.entries) {
      final m = <int, double>{};
      for (final x in e.value.entries) {
        final med = yearMedian[x.key];
        if (med == null) continue;
        m[x.key] = x.value - med;
      }
      if (m.length >= 3) spread[e.key] = m;
    }

    // --- 1. AR(1) no painel inteiro ----------------------------------------
    final x0 = <double>[];
    final x1 = <double>[];
    for (final s in spread.values) {
      for (final e in s.entries) {
        final next = s[e.key + 1];
        if (next == null) continue;
        x0.add(e.value);
        x1.add(next);
      }
    }
    final panel = Regression.ols([x0], x1);

    // --- 2. AR(1) ativo a ativo --------------------------------------------
    final phis = <double>[];
    final pairsPerAsset = <int>[];
    for (final s in spread.entries) {
      final a = <double>[];
      final b = <double>[];
      for (final e in s.value.entries) {
        final next = s.value[e.key + 1];
        if (next == null) continue;
        a.add(e.value);
        b.add(next);
      }
      if (a.length < _minPeers) continue;
      final ols = Regression.ols([a], b);
      if (ols == null) continue;
      phis.add(ols.coefficients[1]);
      pairsPerAsset.add(a.length);
    }

    // --- 3. O que sobra do spread depois de h anos, sem supor AR(1) --------
    //
    // A leitura direta: dos que estavam no quinto superior, quanto do spread
    // deles restava h anos depois? Não supõe forma funcional nenhuma.
    final survival = <int, Map<String, double>>{};
    for (final h in _horizons) {
      final pairs = <({double from, double to})>[];
      for (final s in spread.entries) {
        for (final e in s.value.entries) {
          final after = s.value[e.key + h];
          if (after == null) continue;
          pairs.add((from: e.value, to: after));
        }
      }
      if (pairs.length < 30) continue;
      final sortedRows = [for (final p in pairs) p.from]..sort();
      final highCut = _quantile(sortedRows, 0.8)!;
      final lowCut = _quantile(sortedRows, 0.2)!;
      final highs = [for (final p in pairs) if (p.from >= highCut) p];
      final lows = [for (final p in pairs) if (p.from <= lowCut) p];
      double? ratio(List<({double from, double to})> xs) {
        final from = _median([for (final x in xs) x.from]);
        final to = _median([for (final x in xs) x.to]);
        if (from == null || to == null || from.abs() < 1e-9) return null;
        return to / from;
      }

      survival[h] = {
        'pares': pairs.length.toDouble(),
        'spreadInicialAlto': _median([for (final x in highs) x.from])!,
        'spreadFinalAlto': _median([for (final x in highs) x.to])!,
        'sobraAlto': ratio(highs) ?? double.nan,
        'spreadInicialBaixo': _median([for (final x in lows) x.from])!,
        'spreadFinalBaixo': _median([for (final x in lows) x.to])!,
        'sobraBaixo': ratio(lows) ?? double.nan,
      };
    }

    // --- 4. O destino: o nível do mercado contra o custo de capital --------
    final costs = costOf.values.toList();
    final level = <Map<String, dynamic>>[
      for (final year in years)
        if (yearMedian[year] != null)
          {
            'ano': year,
            'medianaRoic': yearMedian[year],
            'ativos': yearCount[year],
          },
    ];

    final result = {
      'medidoEm': frozenToday.toIso8601String().substring(0, 10),
      'conferidoContraOGabarito': divergent?.length,
      'ativosComSerie': seriesOf.length,
      'painel': {
        'pares': x0.length,
        'phi': panel?.coefficients[1],
        't': panel?.tStats[1],
        'r2': panel?.r2,
        'meiaVidaAnos':
            panel == null ? null : _halfLife(panel.coefficients[1]),
      },
      'porAtivo': {
        'ativos': phis.length,
        'paresMedianos': _median([for (final x in pairsPerAsset) x.toDouble()]),
        'phiP25': _quantile(phis, 0.25),
        'phiMediano': _median(phis),
        'phiP75': _quantile(phis, 0.75),
      },
      // Chave em texto: o `JsonEncoder` não serializa mapa de chave inteira.
      'sobrevivenciaDoSpread': {
        for (final e in survival.entries) '${e.key}': e.value,
      },
      'nivelDoMercado': {
        'medianaRoicPorAno': level,
        'medianaRoicDoPeriodo':
            _median([for (final e in yearMedian.entries) e.value]),
        'medianaCustoDeCapital': _median(costs),
        'ativosComCusto': costs.length,
      },
    };

    File(_output).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(result),
    );
    _printReport(result, divergent);
    stderr.writeln('\nescrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

void _printReport(Map<String, dynamic> r, List<String>? divergent) {
  if (divergent == null) {
    stdout.writeln('\n!! sem gabarito para conferir');
  } else if (divergent.isNotEmpty) {
    stdout.writeln('\n!! a montagem DIVERGE do gabarito em '
        '${divergent.length} ativo(s) — os números abaixo não valem');
  } else {
    stdout.writeln('\nmontagem idêntica à do gabarito.');
  }

  double? d(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble();

  stdout.writeln('\n=== B19 — A REVERSÃO DA RENTABILIDADE À MÉDIA ===');
  stdout.writeln('ativos com série de ROIC: ${r['ativosComSerie']}');

  final p = r['painel'] as Map<String, dynamic>;
  stdout.writeln('\n-- 1. velocidade: AR(1) do spread contra a mediana do ano --');
  stdout.writeln('  painel:  φ = ${_n(d(p, 'phi'))}  t = ${_n(d(p, 't'), 1)}  '
      'R² = ${_n(d(p, 'r2'))}  pares = ${p['pares']}  '
      'meia-vida = ${_n(d(p, 'meiaVidaAnos'), 1)} anos');
  final a = r['porAtivo'] as Map<String, dynamic>;
  stdout.writeln('  por ativo (${a['ativos']} com ≥ $_minPeers pares, '
      'mediana de ${_n(d(a, 'paresMedianos'), 0)}): '
      'φ p25 ${_n(d(a, 'phiP25'))}  mediana ${_n(d(a, 'phiMediano'))}  '
      'p75 ${_n(d(a, 'phiP75'))}');
  final panelPhi = d(p, 'phi');
  final pairs = (p['pares'] as num).toDouble();
  if (panelPhi != null && pairs > 0) {
    // Viés de Kendall do AR(1): `−(1 + 3φ)/n`. No painel ele é desprezível; no
    // estimador por ativo, com dez pares, é da ordem de −0,3.
    stdout.writeln('  viés de Kendall: painel '
        '${_n(-(1 + 3 * panelPhi) / pairs, 4)}  '
        'por ativo com 10 pares ${_n(-(1 + 3 * panelPhi) / 10, 3)}');
  }

  stdout.writeln('\n-- 2. o que sobra do spread, sem supor forma funcional --');
  final s = r['sobrevivenciaDoSpread'] as Map;
  for (final h in _horizons) {
    final m = s['$h'] ?? s[h];
    if (m == null) continue;
    final mm = (m as Map).cast<String, dynamic>();
    stdout.writeln('  $h ano(s): quinto superior '
        '${_pc(d(mm, 'spreadInicialAlto'))} → ${_pc(d(mm, 'spreadFinalAlto'))} '
        '(sobra ${_n(d(mm, 'sobraAlto'), 2)})   quinto inferior '
        '${_pc(d(mm, 'spreadInicialBaixo'))} → '
        '${_pc(d(mm, 'spreadFinalBaixo'))} '
        '(sobra ${_n(d(mm, 'sobraBaixo'), 2)})   n = ${d(mm, 'pares')?.toInt()}');
  }

  final nv = r['nivelDoMercado'] as Map<String, dynamic>;
  stdout.writeln('\n-- 3. destino: reverter para onde? --');
  stdout.writeln('  ROIC mediano do universo, mediana dos anos: '
      '${_pc(d(nv, 'medianaRoicDoPeriodo'))}');
  stdout.writeln('  custo de capital de equilíbrio mediano: '
      '${_pc(d(nv, 'medianaCustoDeCapital'))} '
      '(${nv['ativosComCusto']} avaliados)');
  stdout.writeln('  por ano:');
  for (final x in (nv['medianaRoicPorAno'] as List).cast<Map>()) {
    stdout.writeln('    ${x['ano']}  ${_pc((x['medianaRoic'] as num).toDouble())}'
        '   (${x['ativos']} ativos)');
  }
}
