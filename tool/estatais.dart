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

import 'curva_ligar.dart' show lerTesouro;
import 'validation/congelado.dart';

const _saida = 'docs/validacao/estatais.json';

/// Prêmios a mais no custo do capital próprio das estatais, em fração.
const _grade = [0.005, 0.01, 0.02, 0.03];

/// Mínimo de semanas com retorno para a regressão valer.
const _minimoDeSemanas = 150;

/// Uma regressão por mínimos quadrados, com intercepto.
({List<double> coef, List<double> erro, int n})? _mqo(
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
    final linha = [1.0, for (final x in xs) x[i]];
    for (var a = 0; a < k; a++) {
      xty[a] += linha[a] * y[i];
      for (var b = 0; b < k; b++) {
        xtx[a][b] += linha[a] * linha[b];
      }
    }
  }
  final inv = _inversa(xtx);
  if (inv == null) return null;
  final coef = [
    for (var a = 0; a < k; a++)
      [for (var b = 0; b < k; b++) inv[a][b] * xty[b]].reduce((p, q) => p + q),
  ];
  var sqr = 0.0;
  for (var i = 0; i < n; i++) {
    var previsto = coef[0];
    for (var j = 0; j < xs.length; j++) {
      previsto += coef[j + 1] * xs[j][i];
    }
    sqr += math.pow(y[i] - previsto, 2);
  }
  final s2 = sqr / (n - k);
  return (
    coef: coef.sublist(1),
    erro: [for (var a = 1; a < k; a++) math.sqrt(s2 * inv[a][a])],
    n: n,
  );
}

List<List<double>>? _inversa(List<List<double>> m) {
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

double _mediana(Iterable<double> v) {
  final s = v.toList()..sort();
  if (s.isEmpty) return double.nan;
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _media(Iterable<double> v) {
  final l = v.toList();
  return l.isEmpty ? double.nan : l.reduce((a, b) => a + b) / l.length;
}

/// `t` de Welch para a diferença de médias de dois grupos.
double _welch(List<double> a, List<double> b) {
  double variancia(List<double> x) {
    final m = _media(x);
    return x.map((v) => math.pow(v - m, 2)).reduce((p, q) => p + q) /
        (x.length - 1);
  }

  if (a.length < 2 || b.length < 2) return double.nan;
  return (_media(a) - _media(b)) /
      math.sqrt(variancia(a) / a.length + variancia(b) / b.length);
}

/// O último valor da série em ou antes de [dia].
double? _naData(List<(DateTime, double)> serie, DateTime dia) {
  var lo = 0, hi = serie.length - 1;
  double? achado;
  while (lo <= hi) {
    final m = (lo + hi) ~/ 2;
    if (serie[m].$1.isAfter(dia)) {
      hi = m - 1;
    } else {
      achado = serie[m].$2;
      lo = m + 1;
    }
  }
  return achado;
}

/// O prefixado de dez anos da curva: a média geométrica dos forwards anuais,
/// como em `tool/premio_implicito.dart`.
double? _prefixado10(YieldCurve? curva) {
  if (curva == null) return null;
  final fw = curva.annualForwards(10);
  if (fw.isEmpty) return null;
  var fator = 1.0;
  for (final f in fw) {
    fator *= 1 + f;
  }
  return math.pow(fator, 1 / fw.length).toDouble() - 1;
}

String _pct(double v, [int casas = 2]) =>
    '${(v * 100).toStringAsFixed(casas).replaceAll('.', ',')}%';

String _num(double v, [int casas = 2]) =>
    v.toStringAsFixed(casas).replaceAll('.', ',');

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final controle = ShareholderControlHistory.decode(
        jsonDecode(File('assets/cvm/controle.json').readAsStringSync())
            as Map<String, dynamic>);
    if (controle == null) {
      stderr.writeln('assets/cvm/controle.json ilegível: rode '
          'dart run tool/controle_empacotar.dart');
      exitCode = 2;
      return;
    }
    final embiBruto = File('data/indices/embi_brasil.json');
    if (!embiBruto.existsSync()) {
      stderr.writeln('sem data/indices/embi_brasil.json: rode '
          'python tool/risco_pais_baixar.py');
      exitCode = 2;
      return;
    }
    final embi = <(DateTime, double)>[
      for (final p in (jsonDecode(embiBruto.readAsStringSync()) as List)
          .cast<List>())
        (DateTime.parse(p[0] as String), (p[1] as num).toDouble() / 10000),
    ];

    final hoje = hojeCongelado;
    ShareholderControl? controleDe(Ticker t, DateTime d) {
      final p = controle.porEmissor[t.value.substring(0, 4)];
      return p == null ? null : ShareholderControlHistory.at(p, d);
    }

    // -----------------------------------------------------------------------
    // As séries semanais: o Ibovespa gravado pelo gabarito, de dez anos, e as
    // duas medidas do risco soberano.
    // -----------------------------------------------------------------------
    final dezAnos = DateRange(DateTime(2016, 9, 14), hoje);
    final ibov = (await c.ctx.benchmark.ibovespa(dezAnos)).unwrap();
    final ibovSerie = [for (final p in ibov.points) (p.date, p.close)];
    final quartas = [
      for (final p in ibov.points)
        if (p.date.weekday == DateTime.wednesday) p.date,
    ];
    final quotes = lerTesouro('data/tesouro/precotaxatesourodireto.csv');

    // As duas janelas de cinco anos, cada uma com a sua medida do risco.
    final janelas = <String, ({DateTime de, DateTime ate, List<(DateTime, double)> risco})>{};
    {
      final ateEmbi = embi.last.$1;
      janelas['embi'] = (
        de: DateTime(ateEmbi.year - 5, ateEmbi.month, ateEmbi.day),
        ate: ateEmbi,
        risco: embi,
      );
      final de = DateTime(hoje.year - 5, hoje.month, hoje.day);
      final pref = <(DateTime, double)>[];
      for (final q in quartas) {
        if (q.isBefore(de)) continue;
        final y = _prefixado10(TreasuryCurve.at(quotes, q));
        if (y != null) pref.add((q, y));
      }
      janelas['prefixado10'] = (de: de, ate: hoje, risco: pref);
    }

    // -----------------------------------------------------------------------
    // O universo: beta medido e encolhido, avaliação e séries de preço.
    // -----------------------------------------------------------------------
    final linhas = <Map<String, Object?>>[];
    final porRaiz = <String, Map<String, Object?>>{};
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final comPrior = await c.preparar(t);
      if (comPrior.isErr) continue;
      final semPrior = await c.preparar(t, comPrior: false);
      final inputs = comPrior.unwrap();
      final r = ValuationCascade.evaluate(inputs);
      final serie = (await c.ctx.prices.daily(t, dezAnos)).valueOrNull;
      final precos = [
        for (final p in serie?.points ?? const <PricePoint>[]) (p.date, p.close),
      ];
      final volumes = [
        for (final p in serie?.points ?? const <PricePoint>[])
          if (p.date.isAfter(DateTime(hoje.year - 1, hoje.month, hoje.day)))
            (p.volume ?? 0).toDouble(),
      ];
      final linha = <String, Object?>{
        'ticker': t.value,
        'raiz': t.value.substring(0, 4),
        'controle': controleDe(t, hoje)?.name,
        'setor': inputs.sectorKey,
        'betaMedido': semPrior.valueOrNull?.capm.beta,
        'betaEncolhido': inputs.capm.beta,
        'origemBeta': inputs.capm.betaSource.name,
        'avaliado': r.isOk,
        'potencial': r.valueOrNull?.upside,
        'volumeMediano': volumes.isEmpty ? 0.0 : _mediana(volumes),
      };
      // Lambda nas duas janelas.
      for (final j in janelas.entries) {
        final ctl0 = controleDe(t, j.value.de);
        final ctl1 = controleDe(t, j.value.ate);
        final ys = <double>[], xm = <double>[], xs = <double>[];
        DateTime? antes;
        for (final q in quartas) {
          if (q.isBefore(j.value.de) || q.isAfter(j.value.ate)) continue;
          if (antes != null) {
            final p0 = _naData(precos, antes), p1 = _naData(precos, q);
            final m0 = _naData(ibovSerie, antes), m1 = _naData(ibovSerie, q);
            final s0 = _naData(j.value.risco, antes);
            final s1 = _naData(j.value.risco, q);
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
          antes = q;
        }
        final uma = ys.length >= _minimoDeSemanas ? _mqo(ys, [xs]) : null;
        final duas = ys.length >= _minimoDeSemanas ? _mqo(ys, [xm, xs]) : null;
        linha[j.key] = {
          'semanas': ys.length,
          'controleNoInicio': ctl0?.name,
          'controleNoFim': ctl1?.name,
          'sensibilidade': uma?.coef.first,
          'erro': uma?.erro.first,
          'alemDoMercado': duas?.coef.last,
          'erroAlemDoMercado': duas?.erro.last,
          'betaNaRegressao': duas?.coef.first,
        };
      }
      linhas.add(linha);
      // Uma linha por companhia nas estatísticas de grupo: a classe mais
      // negociada no último ano.
      final atual = porRaiz[linha['raiz'] as String];
      if (atual == null ||
          (linha['volumeMediano'] as double) >
              (atual['volumeMediano'] as double)) {
        porRaiz[linha['raiz'] as String] = linha;
      }
    }
    stderr.write('                                \r');

    final resumo = <String, Object?>{};
    stdout.writeln('== 1. O beta: medido contra encolhido, uma linha por companhia');
    {
      final grupos = <String, List<Map<String, Object?>>>{};
      for (final l in porRaiz.values) {
        if (l['betaMedido'] == null) continue;
        grupos
            .putIfAbsent(l['controle'] == 'state' ? 'estatal' : 'privada', () => [])
            .add(l);
      }
      for (final g in grupos.entries) {
        final medido = [for (final l in g.value) l['betaMedido'] as double];
        final encolhido = [for (final l in g.value) l['betaEncolhido'] as double];
        final dif = [
          for (final l in g.value)
            (l['betaEncolhido'] as double) - (l['betaMedido'] as double),
        ];
        stdout.writeln('  ${g.key}: ${g.value.length} companhias; beta medido '
            'mediano ${_num(_mediana(medido))}, encolhido ${_num(_mediana(encolhido))}; '
            'encolhido − medido: mediana ${_num(_mediana(dif), 3)}, '
            'média ${_num(_media(dif), 3)}');
        resumo['beta_${g.key}'] = {
          'companhias': g.value.length,
          'medidoMediano': _mediana(medido),
          'encolhidoMediano': _mediana(encolhido),
          'difMediana': _mediana(dif),
          'difMedia': _media(dif),
        };
      }
      final est = [
        for (final l in porRaiz.values)
          if (l['controle'] == 'state' && l['betaMedido'] != null) l,
      ]..sort((a, b) => (a['ticker'] as String).compareTo(b['ticker'] as String));
      stdout.writeln('  estatais: ${[
        for (final l in est)
          '${l['ticker']} ${_num(l['betaMedido'] as double)}→${_num(l['betaEncolhido'] as double)}'
      ].join('; ')}');
      // Contra as privadas do mesmo setor.
      final porSetor = <String, List<double>>{};
      for (final l in porRaiz.values) {
        if (l['controle'] == 'state' || l['betaMedido'] == null) continue;
        porSetor.putIfAbsent('${l['setor']}', () => []).add(l['betaMedido'] as double);
      }
      final contraSetor = <double>[];
      for (final l in est) {
        final pares = porSetor['${l['setor']}'];
        if (pares == null || pares.length < 3) continue;
        contraSetor.add((l['betaMedido'] as double) - _mediana(pares));
      }
      stdout.writeln('  beta medido da estatal − mediana das privadas do mesmo '
          'setor (setores com 3+ privadas): mediana ${_num(_mediana(contraSetor), 3)} '
          'em ${contraSetor.length} estatais');
      resumo['beta_contraSetor'] = {
        'estatais': contraSetor.length,
        'difMediana': _mediana(contraSetor),
      };
    }

    stdout.writeln('');
    stdout.writeln('== 2. O lambda: sensibilidade à queda do risco soberano');
    for (final j in janelas.keys) {
      final grupos = <String, List<Map<String, Object?>>>{};
      for (final l in porRaiz.values) {
        final m = l[j] as Map<String, Object?>;
        if (m['sensibilidade'] == null) continue;
        final ini = m['controleNoInicio'], fim = m['controleNoFim'];
        if (ini == null || ini != fim) continue;
        grupos.putIfAbsent(ini == 'state' ? 'estatal' : 'privada', () => []).add(m);
      }
      final todas = [
        for (final g in grupos.values)
          for (final m in g) m['sensibilidade'] as double,
      ];
      final referencia = _mediana(todas);
      final saida = <String, Object?>{'medianaDoUniverso': referencia};
      final janela = janelas[j]!;
      stdout.writeln('  ${j == 'embi' ? 'EMBI+ Risco-Brasil' : 'prefixado de dez anos'}, '
          '${janela.de.toIso8601String().substring(0, 10)} a '
          '${janela.ate.toIso8601String().substring(0, 10)}, semanal; '
          'mediana do universo ${_num(referencia)}');
      final sens = <String, List<double>>{};
      final alem = <String, List<double>>{};
      for (final g in grupos.entries) {
        sens[g.key] = [for (final m in g.value) m['sensibilidade'] as double];
        alem[g.key] = [for (final m in g.value) m['alemDoMercado'] as double];
        final lambda = _mediana(sens[g.key]!) / referencia;
        stdout.writeln('    ${g.key}: ${g.value.length} companhias; sensibilidade '
            'mediana ${_num(_mediana(sens[g.key]!))} (lambda ${_num(lambda)}); '
            'além do Ibovespa: mediana ${_num(_mediana(alem[g.key]!))}, '
            'média ${_num(_media(alem[g.key]!))}');
        saida[g.key] = {
          'companhias': g.value.length,
          'sensibilidadeMediana': _mediana(sens[g.key]!),
          'lambda': lambda,
          'alemDoMercadoMediana': _mediana(alem[g.key]!),
          'alemDoMercadoMedia': _media(alem[g.key]!),
        };
      }
      final tSens = _welch(sens['estatal'] ?? [], sens['privada'] ?? []);
      final tAlem = _welch(alem['estatal'] ?? [], alem['privada'] ?? []);
      stdout.writeln('    diferença estatal − privada: t de Welch '
          '${_num(tSens)} na sensibilidade, ${_num(tAlem)} além do Ibovespa');
      saida['tWelchSensibilidade'] = tSens;
      saida['tWelchAlemDoMercado'] = tAlem;
      resumo['lambda_$j'] = saida;
    }
    final premioPais = embi.last.$2;
    stdout.writeln('  prêmio-país no último EMBI+ (${embi.last.$1.toIso8601String().substring(0, 10)}): '
        '${_pct(premioPais)}');
    resumo['premioPais'] = {
      'data': embi.last.$1.toIso8601String().substring(0, 10),
      'valor': premioPais,
    };
    for (final j in janelas.keys) {
      final l = ((resumo['lambda_$j'] as Map)['estatal'] as Map?)?['lambda'] as double?;
      if (l == null) continue;
      stdout.writeln('  (λ − 1) × prêmio-país, pela janela $j: '
          '${_pct((l - 1) * premioPais)}');
    }

    stdout.writeln('');
    stdout.writeln('== 3. O efeito no preço de hoje, nas estatais avaliadas');
    final efeitos = <Map<String, Object?>>[];
    final estatais = [
      for (final l in linhas)
        if (l['controle'] == 'state' && l['avaliado'] == true) l,
    ];
    final base = c.premio.valor;
    for (final variante in [
      ('base', null as double?, true),
      for (final x in _grade) ('+${_pct(x, 1)} no Ke', x, true),
      ('beta sem encolhimento', null, false),
    ]) {
      final potenciais = <String, double?>{};
      for (final l in estatais) {
        final t = Ticker.parse(l['ticker'] as String);
        double? premio;
        if (variante.$2 != null) {
          // O prêmio a mais entra somado ao do mercado na proporção do beta:
          // `β × (prêmio + x ÷ β) = β × prêmio + x`. Exato no Ke de hoje; no
          // caminho realavancado, o acréscimo anda com `β_t ÷ β`.
          final beta = l['betaEncolhido'] as double;
          if (beta.abs() <= 0.01) {
            potenciais[t.value] = null;
            continue;
          }
          premio = base + variante.$2! / beta;
        }
        final prep = await c.preparar(t, premio: premio, comPrior: variante.$3);
        final r = prep.isErr ? null : ValuationCascade.evaluate(prep.unwrap());
        potenciais[t.value] = r?.valueOrNull?.upside;
      }
      final validos = [for (final v in potenciais.values) ?v];
      stdout.writeln('  ${variante.$1}: ${validos.length} de ${estatais.length} '
          'avaliadas, potencial mediano '
          '${validos.isEmpty ? '—' : _pct(_mediana(validos), 1)}');
      efeitos.add({
        'variante': variante.$1,
        'premioAMais': variante.$2,
        'comEncolhimento': variante.$3,
        'avaliadas': validos.length,
        'potencialMediano': _mediana(validos),
        'potenciais': potenciais,
      });
    }
    final privadas = [
      for (final l in linhas)
        if (l['controle'] != 'state' && l['avaliado'] == true)
          l['potencial'] as double,
    ];
    stdout.writeln('  (privadas: ${privadas.length} avaliadas, potencial mediano '
        '${_pct(_mediana(privadas), 1)})');
    resumo['potencialPrivadas'] = {
      'avaliadas': privadas.length,
      'mediano': _mediana(privadas),
    };

    File(_saida).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'geradoPor': 'tool/estatais.dart',
      'dataDaEntrada': hoje.toIso8601String().substring(0, 10),
      'premioDeMercado': base,
      'resumo': resumo,
      'efeitos': efeitos,
      'ativos': linhas,
    }));
    stdout.writeln('\nescrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}
