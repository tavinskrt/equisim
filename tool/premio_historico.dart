// O prêmio de risco medido do Ibovespa, no lugar dos 5,5% fixos — medição, sem
// ligar nada no motor.
//
// **A pergunta.** O orientador perguntou se o prêmio de mercado pode ser
// capturado em vez de fixado. A forma mais direta é a histórica: o que o
// Ibovespa rendeu acima do CDI na mesma janela,
//
//     prêmio = (1 + CAGR do Ibovespa) ÷ (1 + CAGR do CDI) − 1
//
// com as duas pontas como as âncoras de mercado do aplicativo já as medem
// (`ResolveMarketAnchors`: o índice entre médias de 63 pregões nas pontas, o
// CDI composto). A decisão 116 mediu isso numa janela e o recusou por ruído;
// esta ferramenta mede o que faltava para decidir: quanto o prêmio muda com a
// janela, quanto ele muda de uma data para outra, e o que cada um faz ao preço
// justo, à cobertura e à ordenação.
//
// **Duas partes.**
//
//   1. Sobre a entrada congelada de 14/09/2026: o prêmio com janelas de 5, 10,
//      15 e 20 anos, e o universo reavaliado com cada um contra os 5,5%.
//   2. Nas datas das coortes trimestrais: o prêmio de cada data, só com dado
//      até ela, com janelas de 5 e 10 anos. O backtest com esse prêmio é
//      `tool/backtest_valuation.dart --premio-historico 10 --saida <arq>`.
//
// O índice antes de 23/09/2016 vem do SGS 7 do Banco Central
// (`tool/ibovespa_sgs_baixar.py`), emendado à fonte de mercado — ver
// `tool/validation/ibovespa_longo.dart`.
//
//   python tool/ibovespa_sgs_baixar.py
//   dart run tool/premio_historico.dart       # grava premio_historico.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/premio_historico.json';
const _windows = [5, 10, 15, 20];
const _cohortWindows = [5, 10];
const _reference = CapmInputs.defaultMarketPremium;
const _cases = ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3'];

String _pct(double v, [int decimals = 2]) =>
    '${(v * 100).toStringAsFixed(decimals)}%';

double _median(List<double> v) {
  final o = [...v]..sort();
  if (o.isEmpty) return double.nan;
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

/// O prêmio de uma janela terminada em [end], com a barra de erro.
Future<Map<String, Object?>> _measure({
  required MacroRepository macro,
  required LongIbovespa index,
  required DateTime end,
  required int years,
}) async {
  final window = DateRange(DateTime(end.year - years, end.month, end.day), end);
  final anchors = (await ResolveMarketAnchors.call(
    macro: macro,
    benchmark: index,
    asOf: end,
    windowYears: years,
  ))
      .unwrap();
  // O CDI da janela precisa estar inteiro: sem ele, as âncoras recuam para o
  // valor de 2026 e o prêmio mediria outra coisa.
  final cdi = (await macro.riskFreeDaily(window)).unwrap();
  final cdiComplete = cdi.points.isNotEmpty &&
      cdi.points.first.date.difference(window.start).inDays.abs() <= 10;
  final points = (await index.ibovespa(window)).unwrap().points;
  final indexComplete = points.isNotEmpty &&
      points.first.date.difference(window.start).inDays.abs() <= 10;

  // Erro-padrão da média de um prêmio: `σ ÷ √T`, com a volatilidade anual dos
  // retornos diários do índice e `T` em anos. É a conta que diz quanto a
  // janela sabe.
  final returns = <double>[
    for (var i = 1; i < points.length; i++)
      if (points[i - 1].close > 0) points[i].close / points[i - 1].close - 1,
  ];
  double? error;
  if (returns.length > 1) {
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns
            .map((r) => (r - mean) * (r - mean))
            .reduce((a, b) => a + b) /
        (returns.length - 1);
    error = math.sqrt(variance) * math.sqrt(252.0) / math.sqrt(years.toDouble());
  }
  return {
    'fim': end.toIso8601String().substring(0, 10),
    'anos': years,
    'ibovespa': anchors.marketCagr,
    'cdi': anchors.riskFreeCagr,
    'premio': premiumOfAnchors(anchors),
    'erroPadrao': error,
    'completa': cdiComplete && indexComplete,
  };
}

/// As datas das coortes trimestrais do backtest: o último dia de cada
/// trimestre, de 31/03/2018 a 30/09/2025.
List<DateTime> _cohortDates() => [
      for (var year = 2018; year <= 2025; year++)
        for (final month in const [3, 6, 9, 12])
          if (!(year == 2025 && month == 12)) DateTime(year, month + 1, 0),
    ];

class _Reading {
  _Reading(this.label, this.premium);
  final String label;
  final double premium;
  final Map<String, int> fairValue = {};
  final Map<String, double> upside = {};
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    final today = frozenToday;
    final index = await LongIbovespa.build(
      c.ctx.benchmark,
      sourceWindow: DateRange(DateTime(today.year - 10, today.month, today.day), today),
    );
    stdout.writeln('-- Ibovespa emendado: SGS 7 até '
        '${index.sourceStart.toIso8601String().substring(0, 10)}, fonte de '
        'mercado depois; razão mediana na sobreposição '
        '${index.overlapRatio.toStringAsFixed(6)} --');

    // -------------------------------------------------------------------
    // 1) Sobre a entrada congelada
    // -------------------------------------------------------------------
    final fromApp = premiumOfAnchors(c.anchors);
    stdout.writeln('');
    stdout.writeln('-- o prêmio histórico em 14/09/2026, por janela --');
    stdout.writeln('  o do aplicativo (âncoras congeladas, dez anos): '
        '${_pct(fromApp)} = (1 + ${_pct(c.anchors.marketCagr)}) ÷ '
        '(1 + ${_pct(c.anchors.riskFreeCagr)}) − 1');
    final byWindow = <Map<String, Object?>>[];
    for (final years in _windows) {
      final m = await _measure(
          macro: c.ctx.macro, index: index, end: today, years: years);
      byWindow.add(m);
      final e = m['erroPadrao'] as double?;
      final p = m['premio'] as double;
      stdout.writeln('  ${years.toString().padLeft(2)} anos   Ibovespa '
          '${_pct(m['ibovespa'] as double)}   CDI ${_pct(m['cdi'] as double)}   '
          'prêmio ${_pct(p)}   erro-padrão ${e == null ? '—' : _pct(e)}   '
          '95%: ${e == null ? '—' : '${_pct(p - 1.96 * e)} a ${_pct(p + 1.96 * e)}'}'
          '${m['completa'] == true ? '' : '   (JANELA INCOMPLETA)'}');
    }

    // O universo reavaliado com cada prêmio.
    final candidates = <(String, double)>[
      ('5,5% fixo', _reference),
      for (final m in byWindow)
        ('${m['anos']} anos', m['premio'] as double),
    ];
    final readings = <_Reading>[];
    for (final (label, premium) in candidates) {
      final l = _Reading(label, premium);
      final evaluated = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universe) {
        i++;
        if (i % 50 == 0) stderr.write('  $label: $i/${c.universe.length}   \r');
        final prep = await c.prepare(t, premium: premium);
        if (prep.isErr) continue;
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (identical(label, candidates.first.$1)) evaluated[t] = r.valueOrNull;
        if (r.isErr) continue;
        l.fairValue[t.value] = r.unwrap().fairValue.cents;
        l.upside[t.value] = r.unwrap().upside;
      }
      if (identical(label, candidates.first.$1)) {
        final div = await c.checkAgainstAnswerKey(evaluated);
        if (div == null) {
          stderr.writeln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (div.isNotEmpty) {
          stderr.writeln('ERRO: a montagem de 5,5% diverge do gabarito em '
              '${div.length}: ${div.take(8).join(', ')}');
          exitCode = 1;
          return;
        }
      }
      readings.add(l);
    }
    stderr.write('                                        \r');

    final base = readings.first;
    final effects = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o universo reavaliado --');
    stdout.writeln('  prêmio              avaliados   potencial mediano   acima '
        'de zero   preço justo vs 5,5%   postos');
    for (final l in readings) {
      final upsideValues = l.upside.values.toList();
      final common = l.fairValue.keys.where(base.fairValue.containsKey).toList()..sort();
      final changeList = <double>[
        for (final k in common)
          if (base.fairValue[k]! != 0) l.fairValue[k]! / base.fairValue[k]! - 1,
      ];
      final rho = common.length < 3
          ? null
          : Regression.spearman(
              [for (final k in common) base.upside[k]!],
              [for (final k in common) l.upside[k]!],
            );
      final above = upsideValues.where((p) => p > 0).length;
      final medianUpside = _median(upsideValues);
      final medVar = changeList.isEmpty ? null : _median(changeList);
      stdout.writeln('  ${'${l.label} (${_pct(l.premium)})'.padRight(20)}'
          '${l.fairValue.length.toString().padLeft(9)}   '
          '${_pct(medianUpside).padLeft(17)}   '
          '${'$above de ${upsideValues.length}'.padLeft(13)}   '
          '${(medVar == null ? '—' : _pct(medVar)).padLeft(19)}   '
          '${rho == null ? '—' : rho.toStringAsFixed(3)}');
      effects.add({
        'rotulo': l.label,
        'premio': l.premium,
        'avaliados': l.fairValue.length,
        'potencialMediano': medianUpside,
        'acimaDeZero': above,
        'precoJustoMedianoContraReferencia': medVar,
        'spearmanContraReferencia': rho,
        'casos': {
          for (final t in _cases)
            t: {
              'justoCentavos': l.fairValue[t],
              'potencial': l.upside[t],
            },
        },
      });
    }

    // -------------------------------------------------------------------
    // 2) O prêmio em cada data de coorte
    // -------------------------------------------------------------------
    stdout.writeln('');
    stdout.writeln('-- o prêmio histórico em cada data de coorte --');
    stdout.writeln('  data          5 anos (erro)         10 anos (erro)');
    final byCohort = <Map<String, Object?>>[];
    for (final t in _cohortDates()) {
      final row = <String, Object?>{'data': t.toIso8601String().substring(0, 10)};
      final parts = <String>[];
      for (final years in _cohortWindows) {
        final m =
            await _measure(macro: c.ctx.macro, index: index, end: t, years: years);
        row['janela$years'] = m;
        final e = m['erroPadrao'] as double?;
        parts.add('${_pct(m['premio'] as double).padLeft(7)} '
            '(${e == null ? '—' : _pct(e, 1)})'
            '${m['completa'] == true ? '' : '*'}');
      }
      byCohort.add(row);
      stdout.writeln('  ${row['data']}    ${parts.join('      ')}');
    }
    final p10 = [
      for (final l in byCohort)
        ((l['janela10'] as Map)['premio'] as double),
    ];
    final p5 = [
      for (final l in byCohort) ((l['janela5'] as Map)['premio'] as double),
    ];
    stdout.writeln('  10 anos: de ${_pct(p10.reduce(math.min))} a '
        '${_pct(p10.reduce(math.max))}, mediana ${_pct(_median(p10))}; '
        'negativos: ${p10.where((p) => p <= 0).length} de ${p10.length}');
    stdout.writeln('   5 anos: de ${_pct(p5.reduce(math.min))} a '
        '${_pct(p5.reduce(math.max))}, mediana ${_pct(_median(p5))}; '
        'negativos: ${p5.where((p) => p <= 0).length} de ${p5.length}');

    File(_output).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'geradoPor': 'tool/premio_historico.dart',
      'dataDaEntrada': today.toIso8601String().substring(0, 10),
      'emenda': {
        'inicioDaFonteDeMercado':
            index.sourceStart.toIso8601String().substring(0, 10),
        'razaoMedianaNaSobreposicao': index.overlapRatio,
      },
      'premioDoAplicativoDezAnos': fromApp,
      'porJanela': byWindow,
      'efeitos': effects,
      'porCoorte': byCohort,
    }));
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}
