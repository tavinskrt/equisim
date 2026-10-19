// O beta e a negociação não síncrona.
//
// **O defeito apontado.** O beta sai de regressão de retorno **diário** contra
// o Ibovespa. Ativo que não negocia todo dia responde ao mercado com atraso: o
// retorno dele hoje carrega parte da informação de ontem, e a covariância
// contemporânea perde essa parte. O viés é conhecido e tem direção — **para
// baixo** —, e a correção clássica é a de Dimson: somar as inclinações contra
// o mercado defasado, contemporâneo e adiantado.
//
// **A outra metade do apontamento está bloqueada por dado.** Retorno sobre
// cotação "suja" — não ajustada por provento — só se corrige com a série de
// retorno total da fonte, e a [limitação 1.2](../docs/validacao/limitacoes.md)
// mediu que ela é inutilizável: desvio mediano de 9,1% contra o fluxo de
// proventos publicado, máximo de 38,5%.
//
// **O que isto mede.** Três estimadores no mesmo ativo, na mesma janela:
// diário contemporâneo (o de produção), semanal, e Dimson com uma defasagem e
// uma antecipação.
//
// Uso:
//   dart run tool/beta_sincronia.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';
import 'validation/regression.dart';

final _today = DateTime(2026, 9, 4);

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// Reduz a série ao **último pregão de cada semana**.
///
/// Semana pela data ISO — segunda a domingo —, de modo que feriado no meio não
/// desloca a contagem. O que interessa é ter um ponto por semana com o mesmo
/// corte nos dois lados da regressão.
List<({DateTime date, double close})> _weekly(
  List<DateTime> dates,
  List<double> closes,
) {
  final byWeek = <int, ({DateTime date, double close})>{};
  for (var i = 0; i < dates.length; i++) {
    final d = dates[i];
    // Chave da semana: dias desde a época, divididos por sete, alinhados à
    // segunda-feira. Em UTC, para não depender de horário de verão.
    final days = DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final week = (days + 3) ~/ 7; // 1970-01-01 foi quinta
    final current = byWeek[week];
    if (current == null || d.isAfter(current.date)) {
      byWeek[week] = (date: d, close: closes[i]);
    }
  }
  final keys = byWeek.keys.toList()..sort();
  return [for (final k in keys) byWeek[k]!];
}

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final window = DateRange(
      DateTime(_today.year - PrepareValuationInputs.betaWindowYears, _today.month,
          _today.day),
      _today,
    );
    final indexResult = await ctx.benchmark.ibovespa(window);
    if (indexResult.isErr) {
      stderr.writeln('sem índice: ${indexResult.failureOrNull?.message}');
      return;
    }
    final index = indexResult.unwrap();

    // **Só os que o motor avalia.** O universo cru tem ativo que negocia vinte
    // pregões por ano, e neles o beta diário não é estimador ruim — é ruído.
    // A Porta 0 já os barra, e medir o viés fora dela mede outra coisa.
    final evaluable = <String>{};
    final report = File('docs/validacao/fluxo_explicito.json');
    if (report.existsSync()) {
      for (final e in jsonDecode(report.readAsStringSync()) as List) {
        evaluable.add((e as Map<String, dynamic>)['ticker'] as String);
      }
    }
    stderr.writeln('avaliáveis: ${evaluable.length}');

    final output = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in universe) {
      if (evaluable.isNotEmpty && !evaluable.contains(ticker.value)) continue;
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final seriesResult = await ctx.prices.daily(ticker, window);
      if (seriesResult.isErr) continue;
      final points = seriesResult
          .unwrap()
          .points
          .where((p) => window.contains(p.date))
          .toList();
      if (points.length < 60) continue;

      // --- Diário contemporâneo: o estimador de produção -------------------
      final pair = BetaCalculator.alignReturns(
        assetDates: [for (final p in points) p.date],
        assetIndex: [for (final p in points) p.close],
        marketDates: index.dates,
        marketIndex: index.points.map((p) => p.close).toList(),
      );
      final daily = BetaCalculator.estimate(returns: pair);
      if (daily.isErr) continue;

      // --- Semanal ---------------------------------------------------------
      final assetWeekly = _weekly(
        [for (final p in points) p.date],
        [for (final p in points) p.close],
      );
      final marketWeekly = _weekly(
        index.dates,
        index.points.map((p) => p.close).toList(),
      );
      final weeklyPair = BetaCalculator.alignReturns(
        assetDates: [for (final p in assetWeekly) p.date],
        assetIndex: [for (final p in assetWeekly) p.close],
        marketDates: [for (final p in marketWeekly) p.date],
        marketIndex: [for (final p in marketWeekly) p.close],
      );
      final weekly = BetaCalculator.estimate(returns: weeklyPair);

      // --- Dimson: defasado, contemporâneo e adiantado ---------------------
      //
      // `β = β₋₁ + β₀ + β₊₁`, das inclinações de uma regressão múltipla. É a
      // correção clássica para negociação não síncrona.
      double? dimson;
      double? dimsonSe;
      final ra = pair.asset;
      final rm = pair.market;
      if (ra.length >= 40) {
        final n = ra.length;
        final y = <double>[];
        final x0 = <double>[];
        final xMinus = <double>[];
        final xPlus = <double>[];
        for (var t = 1; t < n - 1; t++) {
          y.add(ra[t]);
          x0.add(rm[t]);
          xMinus.add(rm[t - 1]);
          xPlus.add(rm[t + 1]);
        }
        final ols = Regression.ols([xMinus, x0, xPlus], y);
        if (ols != null) {
          dimson = ols.coefficients[1] + ols.coefficients[2] + ols.coefficients[3];
          // Erro-padrão da soma, ignorando a covariância entre coeficientes:
          // é cota inferior, e serve para ordem de grandeza.
          dimsonSe = 0.0;
          for (var k = 1; k <= 3; k++) {
            dimsonSe = dimsonSe! + ols.stdErrors[k] * ols.stdErrors[k];
          }
          dimsonSe = dimsonSe == null ? null : _root(dimsonSe);
        }
      }

      final d = daily.unwrap();
      output.add({
        'ticker': ticker.value,
        'pregoes': points.length,
        'pregoesPorAno': points.length / PrepareValuationInputs.betaWindowYears,
        'betaDiario': d.beta,
        'seDiario': d.standardError,
        'betaSemanal': weekly.isOk ? weekly.unwrap().beta : null,
        'seSemanal': weekly.isOk ? weekly.unwrap().standardError : null,
        'obsSemanal': weeklyPair.asset.length,
        'betaDimson': dimson,
        'seDimson': dimsonSe,
      });
    }
    stderr.writeln('');

    File('docs/validacao/beta_sincronia.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output);
    stderr.writeln('\nescrito docs/validacao/beta_sincronia.json '
        '(${output.length})');
  } finally {
    await ctx.dispose();
  }
}

double _root(double x) {
  if (x <= 0) return 0;
  var r = x;
  for (var i = 0; i < 60; i++) {
    r = 0.5 * (r + x / r);
  }
  return r;
}

void _printReport(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== BETA E NEGOCIAÇÃO NÃO SÍNCRONA — ${l.length} ===\n');

  List<double> col(String k) => [
        for (final e in l)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble()
      ];

  for (final pair in [
    ('semanal ÷ diário', 'betaSemanal'),
    ('Dimson ÷ diário', 'betaDimson'),
  ]) {
    final ratios = <double>[];
    for (final e in l) {
      final a = (e['betaDiario'] as num?)?.toDouble();
      final b = (e[pair.$2] as num?)?.toDouble();
      if (a == null || b == null || a.abs() < 1e-9) continue;
      ratios.add(b / a);
    }
    if (ratios.isEmpty) continue;
    ratios.sort();
    stdout.writeln('-- ${pair.$1} --');
    stdout.writeln('  p10=${ratios[(ratios.length * 0.1).floor()]
        .toStringAsFixed(3)}  '
        'mediana=${_median(ratios)!.toStringAsFixed(3)}  '
        'p90=${ratios[(ratios.length * 0.9).floor()].toStringAsFixed(3)}');
    stdout.writeln('  maior que o diário em '
        '${ratios.where((x) => x > 1).length} de ${ratios.length}  '
        '(acima de 1,10: ${ratios.where((x) => x > 1.10).length})');
  }

  final seDaily = col('seDiario');
  final seWeekly = col('seSemanal');
  final seDimson = col('seDimson');
  stdout.writeln('\n-- erro-padrão de cada estimador --');
  if (seDaily.isNotEmpty) {
    stdout.writeln('  diário:  mediana=${_median(seDaily)!.toStringAsFixed(4)}');
  }
  if (seWeekly.isNotEmpty) {
    stdout.writeln('  semanal: mediana=${_median(seWeekly)!.toStringAsFixed(4)}');
  }
  if (seDimson.isNotEmpty) {
    stdout.writeln('  Dimson:  mediana=${_median(seDimson)!.toStringAsFixed(4)}');
  }

  // A hipótese: o viés é dos que negociam menos.
  final byLiquidity = [...l]
    ..sort((a, b) => (a['pregoesPorAno'] as num)
        .compareTo(b['pregoesPorAno'] as num));
  stdout.writeln('\n-- o viés é dos que negociam menos? --');
  final half = byLiquidity.length ~/ 2;
  for (final group in [
    ('menos pregões', byLiquidity.take(half).toList()),
    ('mais pregões', byLiquidity.skip(half).toList()),
  ]) {
    final ratios = <double>[];
    for (final e in group.$2) {
      final a = (e['betaDiario'] as num?)?.toDouble();
      final b = (e['betaDimson'] as num?)?.toDouble();
      if (a == null || b == null || a.abs() < 1e-9) continue;
      ratios.add(b / a);
    }
    if (ratios.isEmpty) continue;
    final tradingDays = [
      for (final e in group.$2) (e['pregoesPorAno'] as num).toDouble()
    ];
    stdout.writeln('  ${group.$1.padRight(16)} '
        'pregões/ano mediano=${_median(tradingDays)!.toStringAsFixed(0)}  '
        'Dimson÷diário mediano=${_median(ratios)!.toStringAsFixed(3)}');
  }

  final ord = [...l]..sort((a, b) {
      final x = (a['betaDimson'] as num?)?.toDouble();
      final y = (b['betaDimson'] as num?)?.toDouble();
      final ax = (a['betaDiario'] as num?)?.toDouble() ?? 1;
      final by = (b['betaDiario'] as num?)?.toDouble() ?? 1;
      return ((y ?? 0) / by).compareTo((x ?? 0) / ax);
    });
  stdout.writeln('\n-- onde Dimson mais eleva o beta --');
  stdout.writeln('  ${"ativo".padRight(8)}${"diário".padLeft(9)}'
      '${"semanal".padLeft(9)}${"Dimson".padLeft(9)}${"pregões".padLeft(9)}');
  for (final e in ord.take(8)) {
    String f(String k) {
      final v = (e[k] as num?)?.toDouble();
      return v == null ? '—' : v.toStringAsFixed(3);
    }

    stdout.writeln('  ${(e['ticker'] as String).padRight(8)}'
        '${f('betaDiario').padLeft(9)}${f('betaSemanal').padLeft(9)}'
        '${f('betaDimson').padLeft(9)}'
        '${(e['pregoesPorAno'] as num).toStringAsFixed(0).padLeft(9)}');
  }
  stdout.writeln('\n  (a metade "cotação suja" do apontamento está bloqueada '
      'pela limitação 1.2: ${_pc(0.091)} de desvio mediano na série de retorno '
      'total da fonte)');
}
