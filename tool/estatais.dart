// B46 — o risco do controle estatal: o beta, o lambda e o efeito no preço.
//
// **A pergunta.** O motor dá às estatais potencial muito maior que às privadas.
// Parte disso pode ser risco que o CAPM do motor não cobra: o controlador
// público persegue objetivos além do lucro, e o minoritário paga. A medição
// confere três caminhos, sobre a entrada congelada de 14/09/2026:
//
// 1. **O beta.** O motor encolhe o beta medido em direção à mediana do setor,
//    e o setor é quase todo de privadas. Se o beta medido das estatais for
//    maior que o encolhido, a correção cabe no CAPM puro.
// 2. **O lambda de Damodaran** (2003): a exposição de cada companhia ao risco
//    do país, `Ke = Rf + β × prêmio + λ × prêmio-país`. Medido pela
//    sensibilidade do retorno semanal da ação à variação do risco soberano, por
//    duas séries independentes — o EMBI+ Risco-Brasil (até 30/07/2024, quando o
//    J.P. Morgan o descontinuou) e o prefixado de dez anos do Tesouro (até a
//    data congelada) —, sozinha e junto com o Ibovespa. O lambda de cada
//    companhia é a sensibilidade dela dividida pela mediana do universo.
// 3. **O efeito no preço de hoje** de cobrar das estatais um prêmio a mais no
//    custo do capital próprio, e o de tirar o encolhimento do beta delas.
//
// O controle é o do Formulário Cadastral da CVM (`assets/cvm/controle.json`,
// de `tool/controle_empacotar.dart`). Na medição do lambda, a companhia entra
// no grupo da espécie que teve a janela inteira; quem mudou de controle no meio
// fica de fora.
//
// Uso:
//   python tool/risco_pais_baixar.py
//   dart run tool/controle_empacotar.dart
//   dart run tool/estatais.dart
//
// Grava docs/validacao/estatais.json.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'curva_ligar.dart' show readTreasury;
import 'validation/congelado.dart';

const _output = 'docs/validacao/estatais.json';

/// Prêmios a mais no custo do capital próprio das estatais, em fração.
const _grid = [0.005, 0.01, 0.02, 0.03];

/// Mínimo de semanas com retorno para a regressão valer.
const _minWeeks = 150;

/// Uma regressão por mínimos quadrados, com intercepto.
({List<double> coef, List<double> error, int n})? _ols(
  List<double> y,
  List<List<double>> xs,
) {
  final n = y.length;
  final k = xs.length + 1;
  if (n <= k + 2) return null;
  // X'X e X'y, com a coluna do intercepto.
  final xtx = List.generate(k, (_) => List.filled(k, 0.0));
  final xty = List.filled(k, 0.0);
  for (var i = 0; i < n; i++) {
    final row = [1.0, for (final x in xs) x[i]];
    for (var a = 0; a < k; a++) {
      xty[a] += row[a] * y[i];
      for (var b = 0; b < k; b++) {
        xtx[a][b] += row[a] * row[b];
      }
    }
  }
  final inv = _inverse(xtx);
  if (inv == null) return null;
  final coef = [
    for (var a = 0; a < k; a++)
      [for (var b = 0; b < k; b++) inv[a][b] * xty[b]].reduce((p, q) => p + q),
  ];
  var sqr = 0.0;
  for (var i = 0; i < n; i++) {
    var predicted = coef[0];
    for (var j = 0; j < xs.length; j++) {
      predicted += coef[j + 1] * xs[j][i];
    }
    sqr += math.pow(y[i] - predicted, 2);
  }
  final s2 = sqr / (n - k);
  return (
    coef: coef.sublist(1),
    error: [for (var a = 1; a < k; a++) math.sqrt(s2 * inv[a][a])],
    n: n,
  );
}

List<List<double>>? _inverse(List<List<double>> m) {
  final k = m.length;
  final a = [
    for (var i = 0; i < k; i++)
      [...m[i], for (var j = 0; j < k; j++) i == j ? 1.0 : 0.0],
  ];
  for (var c = 0; c < k; c++) {
    var piv = c;
    for (var r = c + 1; r < k; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    if (a[piv][c].abs() < 1e-14) return null;
    final t = a[c];
    a[c] = a[piv];
    a[piv] = t;
    final d = a[c][c];
    for (var j = 0; j < 2 * k; j++) {
      a[c][j] /= d;
    }
    for (var r = 0; r < k; r++) {
      if (r == c) continue;
      final f = a[r][c];
      for (var j = 0; j < 2 * k; j++) {
        a[r][j] -= f * a[c][j];
      }
    }
  }
  return [for (final l in a) l.sublist(k)];
}

double _median(Iterable<double> v) {
  final s = v.toList()..sort();
  if (s.isEmpty) return double.nan;
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _mean(Iterable<double> v) {
  final l = v.toList();
  return l.isEmpty ? double.nan : l.reduce((a, b) => a + b) / l.length;
}

/// `t` de Welch para a diferença de médias de dois grupos.
double _welch(List<double> a, List<double> b) {
  double variance(List<double> x) {
    final m = _mean(x);
    return x.map((v) => math.pow(v - m, 2)).reduce((p, q) => p + q) /
        (x.length - 1);
  }

  if (a.length < 2 || b.length < 2) return double.nan;
  return (_mean(a) - _mean(b)) /
      math.sqrt(variance(a) / a.length + variance(b) / b.length);
}

/// O último valor da série em ou antes de [day].
double? _atDate(List<(DateTime, double)> series, DateTime day) {
  var lo = 0, hi = series.length - 1;
  double? foundValue;
  while (lo <= hi) {
    final m = (lo + hi) ~/ 2;
    if (series[m].$1.isAfter(day)) {
      hi = m - 1;
    } else {
      foundValue = series[m].$2;
      lo = m + 1;
    }
  }
  return foundValue;
}

/// O prefixado de dez anos da curva: a média geométrica dos forwards anuais,
/// como em `tool/premio_implicito.dart`.
double? _fixedRate10(YieldCurve? curve) {
  if (curve == null) return null;
  final fw = curve.annualForwards(10);
  if (fw.isEmpty) return null;
  var factor = 1.0;
  for (final f in fw) {
    factor *= 1 + f;
  }
  return math.pow(factor, 1 / fw.length).toDouble() - 1;
}

String _pct(double v, [int decimals = 2]) =>
    '${(v * 100).toStringAsFixed(decimals).replaceAll('.', ',')}%';

String _num(double v, [int decimals = 2]) =>
    v.toStringAsFixed(decimals).replaceAll('.', ',');

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final control = ShareholderControlHistory.decode(
        jsonDecode(File('assets/cvm/controle.json').readAsStringSync())
            as Map<String, dynamic>);
    if (control == null) {
      stderr.writeln('assets/cvm/controle.json ilegível: rode '
          'dart run tool/controle_empacotar.dart');
      exitCode = 2;
      return;
    }
    final rawEmbi = File('data/indices/embi_brasil.json');
    if (!rawEmbi.existsSync()) {
      stderr.writeln('sem data/indices/embi_brasil.json: rode '
          'python tool/risco_pais_baixar.py');
      exitCode = 2;
      return;
    }
    final embi = <(DateTime, double)>[
      for (final p in (jsonDecode(rawEmbi.readAsStringSync()) as List)
          .cast<List>())
        (DateTime.parse(p[0] as String), (p[1] as num).toDouble() / 10000),
    ];

    final today = frozenToday;
    ShareholderControl? controlOf(Ticker t, DateTime d) {
      final p = control.byIssuer[t.value.substring(0, 4)];
      return p == null ? null : ShareholderControlHistory.at(p, d);
    }

    // -----------------------------------------------------------------------
    // As séries semanais: o Ibovespa gravado pelo gabarito, de dez anos, e as
    // duas medidas do risco soberano.
    // -----------------------------------------------------------------------
    final tenYears = DateRange(DateTime(2016, 9, 14), today);
    final ibov = (await c.ctx.benchmark.ibovespa(tenYears)).unwrap();
    final ibovSeries = [for (final p in ibov.points) (p.date, p.close)];
    final wednesdays = [
      for (final p in ibov.points)
        if (p.date.weekday == DateTime.wednesday) p.date,
    ];
    final quotes = readTreasury('data/tesouro/precotaxatesourodireto.csv');

    // As duas janelas de cinco anos, cada uma com a sua medida do risco.
    final windows = <String, ({DateTime from, DateTime until, List<(DateTime, double)> risk})>{};
    {
      final embiEnd = embi.last.$1;
      windows['embi'] = (
        from: DateTime(embiEnd.year - 5, embiEnd.month, embiEnd.day),
        until: embiEnd,
        risk: embi,
      );
      final from = DateTime(today.year - 5, today.month, today.day);
      final pref = <(DateTime, double)>[];
      for (final q in wednesdays) {
        if (q.isBefore(from)) continue;
        final y = _fixedRate10(TreasuryCurve.at(quotes, q));
        if (y != null) pref.add((q, y));
      }
      windows['prefixado10'] = (from: from, until: today, risk: pref);
    }

    // -----------------------------------------------------------------------
    // O universo: beta medido e encolhido, avaliação e séries de preço.
    // -----------------------------------------------------------------------
    final rows = <Map<String, Object?>>[];
    final byRoot = <String, Map<String, Object?>>{};
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final withPrior = await c.prepare(t);
      if (withPrior.isErr) continue;
      final withoutPrior = await c.prepare(t, withPrior: false);
      final inputs = withPrior.unwrap();
      final r = ValuationCascade.evaluate(inputs);
      final series = (await c.ctx.prices.daily(t, tenYears)).valueOrNull;
      final prices = [
        for (final p in series?.points ?? const <PricePoint>[]) (p.date, p.close),
      ];
      final volumes = [
        for (final p in series?.points ?? const <PricePoint>[])
          if (p.date.isAfter(DateTime(today.year - 1, today.month, today.day)))
            (p.volume ?? 0).toDouble(),
      ];
      final row = <String, Object?>{
        'ticker': t.value,
        'raiz': t.value.substring(0, 4),
        'controle': controlOf(t, today)?.name,
        'setor': inputs.sectorKey,
        'betaMedido': withoutPrior.valueOrNull?.capm.beta,
        'betaEncolhido': inputs.capm.beta,
        'origemBeta': inputs.capm.betaSource.name,
        'avaliado': r.isOk,
        'potencial': r.valueOrNull?.upside,
        'volumeMediano': volumes.isEmpty ? 0.0 : _median(volumes),
      };
      // Lambda nas duas janelas.
      for (final j in windows.entries) {
        final ctl0 = controlOf(t, j.value.from);
        final ctl1 = controlOf(t, j.value.until);
        final ys = <double>[], xm = <double>[], xs = <double>[];
        DateTime? before;
        for (final q in wednesdays) {
          if (q.isBefore(j.value.from) || q.isAfter(j.value.until)) continue;
          if (before != null) {
            final p0 = _atDate(prices, before), p1 = _atDate(prices, q);
            final m0 = _atDate(ibovSeries, before), m1 = _atDate(ibovSeries, q);
            final s0 = _atDate(j.value.risk, before);
            final s1 = _atDate(j.value.risk, q);
            // A semana sem negócio — preço igual ao da anterior — fica fora:
            // é falta de pregão, e não retorno zero.
            if (p0 != null && p1 != null && p0 > 0 && m0 != null &&
                m0 > 0 && m1 != null && s0 != null && s1 != null &&
                (p1 - p0).abs() > 1e-9 * p0) {
              ys.add(p1 / p0 - 1);
              xm.add(m1 / m0 - 1);
              // Sinal trocado: risco que cai é retorno que sobe, e a
              // sensibilidade positiva é a exposição.
              xs.add(-(s1 - s0));
            }
          }
          before = q;
        }
        final oneFactor = ys.length >= _minWeeks ? _ols(ys, [xs]) : null;
        final twoFactor = ys.length >= _minWeeks ? _ols(ys, [xm, xs]) : null;
        row[j.key] = {
          'semanas': ys.length,
          'controleNoInicio': ctl0?.name,
          'controleNoFim': ctl1?.name,
          'sensibilidade': oneFactor?.coef.first,
          'erro': oneFactor?.error.first,
          'alemDoMercado': twoFactor?.coef.last,
          'erroAlemDoMercado': twoFactor?.error.last,
          'betaNaRegressao': twoFactor?.coef.first,
        };
      }
      rows.add(row);
      // Uma linha por companhia nas estatísticas de grupo: a classe mais
      // negociada no último ano.
      final current = byRoot[row['raiz'] as String];
      if (current == null ||
          (row['volumeMediano'] as double) >
              (current['volumeMediano'] as double)) {
        byRoot[row['raiz'] as String] = row;
      }
    }
    stderr.write('                                \r');

    final summary = <String, Object?>{};
    stdout.writeln('== 1. O beta: medido contra encolhido, uma linha por companhia');
    {
      final groups = <String, List<Map<String, Object?>>>{};
      for (final l in byRoot.values) {
        if (l['betaMedido'] == null) continue;
        groups
            .putIfAbsent(l['controle'] == 'state' ? 'estatal' : 'privada', () => [])
            .add(l);
      }
      for (final g in groups.entries) {
        final measured = [for (final l in g.value) l['betaMedido'] as double];
        final shrunk = [for (final l in g.value) l['betaEncolhido'] as double];
        final diff = [
          for (final l in g.value)
            (l['betaEncolhido'] as double) - (l['betaMedido'] as double),
        ];
        stdout.writeln('  ${g.key}: ${g.value.length} companhias; beta medido '
            'mediano ${_num(_median(measured))}, encolhido ${_num(_median(shrunk))}; '
            'encolhido − medido: mediana ${_num(_median(diff), 3)}, '
            'média ${_num(_mean(diff), 3)}');
        summary['beta_${g.key}'] = {
          'companhias': g.value.length,
          'medidoMediano': _median(measured),
          'encolhidoMediano': _median(shrunk),
          'difMediana': _median(diff),
          'difMedia': _mean(diff),
        };
      }
      final est = [
        for (final l in byRoot.values)
          if (l['controle'] == 'state' && l['betaMedido'] != null) l,
      ]..sort((a, b) => (a['ticker'] as String).compareTo(b['ticker'] as String));
      stdout.writeln('  estatais: ${[
        for (final l in est)
          '${l['ticker']} ${_num(l['betaMedido'] as double)}→${_num(l['betaEncolhido'] as double)}'
      ].join('; ')}');
      // Contra as privadas do mesmo setor.
      final bySector = <String, List<double>>{};
      for (final l in byRoot.values) {
        if (l['controle'] == 'state' || l['betaMedido'] == null) continue;
        bySector.putIfAbsent('${l['setor']}', () => []).add(l['betaMedido'] as double);
      }
      final againstSector = <double>[];
      for (final l in est) {
        final pairs = bySector['${l['setor']}'];
        if (pairs == null || pairs.length < 3) continue;
        againstSector.add((l['betaMedido'] as double) - _median(pairs));
      }
      stdout.writeln('  beta medido da estatal − mediana das privadas do mesmo '
          'setor (setores com 3+ privadas): mediana ${_num(_median(againstSector), 3)} '
          'em ${againstSector.length} estatais');
      summary['beta_contraSetor'] = {
        'estatais': againstSector.length,
        'difMediana': _median(againstSector),
      };
    }

    stdout.writeln('');
    stdout.writeln('== 2. O lambda: sensibilidade à queda do risco soberano');
    for (final j in windows.keys) {
      final groups = <String, List<Map<String, Object?>>>{};
      for (final l in byRoot.values) {
        final m = l[j] as Map<String, Object?>;
        if (m['sensibilidade'] == null) continue;
        final ini = m['controleNoInicio'], end = m['controleNoFim'];
        if (ini == null || ini != end) continue;
        groups.putIfAbsent(ini == 'state' ? 'estatal' : 'privada', () => []).add(m);
      }
      final allRows = [
        for (final g in groups.values)
          for (final m in g) m['sensibilidade'] as double,
      ];
      final reference = _median(allRows);
      final output = <String, Object?>{'medianaDoUniverso': reference};
      final window = windows[j]!;
      stdout.writeln('  ${j == 'embi' ? 'EMBI+ Risco-Brasil' : 'prefixado de dez anos'}, '
          '${window.from.toIso8601String().substring(0, 10)} a '
          '${window.until.toIso8601String().substring(0, 10)}, semanal; '
          'mediana do universo ${_num(reference)}');
      final sens = <String, List<double>>{};
      final beyond = <String, List<double>>{};
      for (final g in groups.entries) {
        sens[g.key] = [for (final m in g.value) m['sensibilidade'] as double];
        beyond[g.key] = [for (final m in g.value) m['alemDoMercado'] as double];
        final lambda = _median(sens[g.key]!) / reference;
        stdout.writeln('    ${g.key}: ${g.value.length} companhias; sensibilidade '
            'mediana ${_num(_median(sens[g.key]!))} (lambda ${_num(lambda)}); '
            'além do Ibovespa: mediana ${_num(_median(beyond[g.key]!))}, '
            'média ${_num(_mean(beyond[g.key]!))}');
        output[g.key] = {
          'companhias': g.value.length,
          'sensibilidadeMediana': _median(sens[g.key]!),
          'lambda': lambda,
          'alemDoMercadoMediana': _median(beyond[g.key]!),
          'alemDoMercadoMedia': _mean(beyond[g.key]!),
        };
      }
      final tSens = _welch(sens['estatal'] ?? [], sens['privada'] ?? []);
      final tBeyond = _welch(beyond['estatal'] ?? [], beyond['privada'] ?? []);
      stdout.writeln('    diferença estatal − privada: t de Welch '
          '${_num(tSens)} na sensibilidade, ${_num(tBeyond)} além do Ibovespa');
      output['tWelchSensibilidade'] = tSens;
      output['tWelchAlemDoMercado'] = tBeyond;
      summary['lambda_$j'] = output;
    }
    final countryPremium = embi.last.$2;
    stdout.writeln('  prêmio-país no último EMBI+ (${embi.last.$1.toIso8601String().substring(0, 10)}): '
        '${_pct(countryPremium)}');
    summary['premioPais'] = {
      'data': embi.last.$1.toIso8601String().substring(0, 10),
      'valor': countryPremium,
    };
    for (final j in windows.keys) {
      final l = ((summary['lambda_$j'] as Map)['estatal'] as Map?)?['lambda'] as double?;
      if (l == null) continue;
      stdout.writeln('  (λ − 1) × prêmio-país, pela janela $j: '
          '${_pct((l - 1) * countryPremium)}');
    }

    stdout.writeln('');
    stdout.writeln('== 3. O efeito no preço de hoje, nas estatais avaliadas');
    final effects = <Map<String, Object?>>[];
    final stateOwnedTickers = [
      for (final l in rows)
        if (l['controle'] == 'state' && l['avaliado'] == true) l,
    ];
    final base = c.premium.value;
    for (final variant in [
      ('base', null as double?, true),
      for (final x in _grid) ('+${_pct(x, 1)} no Ke', x, true),
      ('beta sem encolhimento', null, false),
    ]) {
      final upsideByTicker = <String, double?>{};
      for (final l in stateOwnedTickers) {
        final t = Ticker.parse(l['ticker'] as String);
        double? premium;
        if (variant.$2 != null) {
          // O prêmio a mais entra somado ao do mercado na proporção do beta:
          // `β × (prêmio + x ÷ β) = β × prêmio + x`. Exato no Ke de hoje; no
          // caminho realavancado, o acréscimo anda com `β_t ÷ β`.
          final beta = l['betaEncolhido'] as double;
          if (beta.abs() <= 0.01) {
            upsideByTicker[t.value] = null;
            continue;
          }
          premium = base + variant.$2! / beta;
        }
        final prep = await c.prepare(t, premium: premium, withPrior: variant.$3);
        final r = prep.isErr ? null : ValuationCascade.evaluate(prep.unwrap());
        upsideByTicker[t.value] = r?.valueOrNull?.upside;
      }
      final validValues = [for (final v in upsideByTicker.values) ?v];
      stdout.writeln('  ${variant.$1}: ${validValues.length} de ${stateOwnedTickers.length} '
          'avaliadas, potencial mediano '
          '${validValues.isEmpty ? '—' : _pct(_median(validValues), 1)}');
      effects.add({
        'variante': variant.$1,
        'premioAMais': variant.$2,
        'comEncolhimento': variant.$3,
        'avaliadas': validValues.length,
        'potencialMediano': _median(validValues),
        'potenciais': upsideByTicker,
      });
    }
    final privateTickers = [
      for (final l in rows)
        if (l['controle'] != 'state' && l['avaliado'] == true)
          l['potencial'] as double,
    ];
    stdout.writeln('  (privadas: ${privateTickers.length} avaliadas, potencial mediano '
        '${_pct(_median(privateTickers), 1)})');
    summary['potencialPrivadas'] = {
      'avaliadas': privateTickers.length,
      'mediano': _median(privateTickers),
    };

    File(_output).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'geradoPor': 'tool/estatais.dart',
      'dataDaEntrada': today.toIso8601String().substring(0, 10),
      'premioDeMercado': base,
      'resumo': summary,
      'efeitos': effects,
      'ativos': rows,
    }));
    stdout.writeln('\nescrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}
