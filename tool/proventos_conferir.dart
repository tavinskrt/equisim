// A4 — os proventos da B3 conferidos, e o retorno total nas coortes.
//
// Quatro perguntas, sobre os 297 emissores do universo:
//
//   1. unidade e data  o fechamento com direito que a B3 publica bate com o
//                      COTAHIST no mesmo dia?
//   2. data ex         o preço cai na data ex, e cai na ordem do provento?
//   3. adjustedClose   o ajuste da fonte de preços corresponde aos proventos da
//                      B3? É a medição da §1.2 das limitações — desvio de 9,1%
//                      em 2026-08 contra o fluxo da própria fonte —, agora com
//                      fonte independente.
//   4. coortes         quanto o retorno total difere do de preço nas coortes de
//                      `backtest_valuation.json`, e o que muda na habilidade.
//
// Grava `docs/validacao/proventos.json` e, para a regressão condicional, uma
// cópia das coortes com `ret12tot` e `ret36tot` em
// `docs/validacao/backtest_valuation_total.json`.
//
// Uso:
//   python tool/b3_complemento_baixar.py
//   dart run tool/proventos_conferir.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'validation/context.dart';

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantile(List<double> v, double q) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

String _pc(double? v, [int decimals = 1]) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(decimals)}%';

Future<void> main() async {
  final dividends = readDividends();
  final universe = (jsonDecode(File('docs/validacao/universo.json')
          .readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .map((e) => e['ticker'] as String)
      .toSet();
  final raw = readRawCotahist(universe);
  stderr.writeln('proventos de ${dividends.length} emissores; COTAHIST de '
      '${raw.length} tickers');

  // ---- 1 e 2: unidade, data-com e queda na data ex ----------------------
  var withPrice = 0, priceMatches = 0, withExSession = 0;
  final drops = <double>[];
  final priceDeviations = <double>[];
  for (final t in universe) {
    final series = raw[t];
    if (series == null) continue;
    for (final p in dividendsOf(dividends, t)) {
      if (p.exDate.year < 2010) continue;
      final withInput = tradingDayUntil(series, p.lastDateWithRights, marginDays: 0);
      final ex = tradingDayFrom(series, p.exDate, marginDays: 5);
      if (p.closeWithRights != null && withInput != null) {
        withPrice++;
        final d = (p.closeWithRights! / withInput.close - 1).abs();
        priceDeviations.add(d);
        if (d <= 0.01) priceMatches++;
      }
      if (withInput != null && ex != null) {
        withExSession++;
        // Só provento que pesa: abaixo de 0,5% do preço, o ruído do dia manda.
        if (p.amount / withInput.close >= 0.005) {
          drops.add((withInput.close - ex.close) / p.amount);
        }
      }
    }
  }

  // ---- 3: adjustedClose da fonte contra os proventos da B3 ---------------
  final end = DateTime(2026, 9, 14);
  final start = DateTime(2016, 9, 14);
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final adjustments = <Map<String, Object?>>[];
  try {
    for (final t in universe.toList()..sort()) {
      final list = dividendsOf(dividends, t);
      final series = raw[t];
      if (list.isEmpty || series == null) continue;
      final r = await ctx.prices.daily(Ticker.parse(t), DateRange(start, end));
      if (r.isErr) continue;
      final points = [
        for (final p in r.unwrap().points)
          if (p.adjustedClose != null && p.adjustedClose! > 0 && p.close > 0) p,
      ];
      if (points.length < 500) continue;
      final a = points.first, b = points.last;
      // Convenção de ajuste para trás: cada provento multiplica os preços
      // anteriores por `1 − D/P_com`. A razão ajustado ÷ bruto entre as pontas
      // é o produto desses fatores.
      final observed =
          (a.adjustedClose! / a.close) / (b.adjustedClose! / b.close);
      var implied = 1.0;
      var used = 0, withoutPrice = 0;
      for (final p in list) {
        if (!p.exDate.isAfter(a.date) || p.exDate.isAfter(b.date)) continue;
        final withInput = tradingDayUntil(series, p.lastDateWithRights, marginDays: 5);
        final price = p.closeWithRights ?? withInput?.close;
        if (price == null || price <= p.amount) {
          withoutPrice++;
          continue;
        }
        implied *= 1 - p.amount / price;
        used++;
      }
      if (used == 0) continue;
      adjustments.add({
        'ticker': t,
        'proventos': used,
        'semPreco': withoutPrice,
        'observado': observed,
        'implicitoB3': implied,
        'desvio': (observed / implied - 1).abs(),
      });
    }
  } finally {
    await ctx.dispose();
  }
  final deviations = [for (final x in adjustments) x['desvio']! as double];

  // ---- 4: retorno total nas coortes -------------------------------------
  final cohortsFile = File('docs/validacao/backtest_valuation.json');
  final cohorts = cohortsFile.existsSync()
      ? (jsonDecode(cohortsFile.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];
  final byCohort = <int, List<double>>{};
  var withoutPriceCohorts = 0, approximatedCohorts = 0;
  for (final l in cohorts) {
    final t = l['ticker'] as String;
    final year = l['coorte'] as int;
    final base = DateTime.utc(year, 9, 30);
    final series = raw[t];
    final list = dividendsOf(dividends, t);
    for (final (months, field) in [(12, 'ret12'), (36, 'ret36')]) {
      final price = (l[field] as num?)?.toDouble();
      if (price == null) continue;
      if (series == null) {
        l['${field}tot'] = null;
        continue;
      }
      final r = TotalReturn.factor(
        dividends: list,
        from: base,
        until: DateTime.utc(year + months ~/ 12, 9, 30),
        closeOnExDate: (d) => tradingDayFrom(series, d, marginDays: 5)?.close,
      );
      withoutPriceCohorts += r.withoutPrice;
      approximatedCohorts += r.approximated;
      final total = (1 + price) * r.factor - 1;
      l['${field}tot'] = total;
      if (months == 36) (byCohort[year] ??= []).add(total - price);
    }
  }
  if (cohorts.isNotEmpty) {
    File('docs/validacao/backtest_valuation_total.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(cohorts));
  }

  final result = {
    'medidoEm': '2026-09-14',
    'dataCom': {
      'comPrecoDaB3': withPrice,
      'batemA1pct': priceMatches,
      'desvioMediano': _median(priceDeviations),
    },
    'dataEx': {
      'comPregaoNasDuasDatas': withExSession,
      'quedaSobreProventoMediana': _median(drops),
      'quedaSobreProventoP25': _quantile(drops, 0.25),
      'quedaSobreProventoP75': _quantile(drops, 0.75),
      'n': drops.length,
    },
    'adjustedClose': {
      'ativos': adjustments.length,
      'desvioMediano': _median(deviations),
      'desvioP90': _quantile(deviations, 0.9),
      'acimaDe5pct': deviations.where((d) => d > 0.05).length,
      'porAtivo': adjustments,
    },
    'coortes': {
      'linhas': cohorts.length,
      'proventosSemPreco': withoutPriceCohorts,
      'proventosPeloPrecoComDireito': approximatedCohorts,
      'totalMenosPreco36m': {
        for (final e in byCohort.entries) '${e.key}': _median(e.value),
      },
    },
  };
  File('docs/validacao/proventos.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(result));

  stdout.writeln('== 1. Fechamento com direito: B3 contra COTAHIST ==');
  stdout.writeln('  $priceMatches de $withPrice a 1% '
      '(${_pc(withPrice == 0 ? null : priceMatches / withPrice)}); desvio mediano '
      '${_pc(_median(priceDeviations), 2)}');
  stdout.writeln('\n== 2. Queda na data ex ÷ provento ==');
  stdout.writeln('  mediana ${_median(drops)?.toStringAsFixed(3)}  '
      'p25 ${_quantile(drops, 0.25)?.toStringAsFixed(3)}  '
      'p75 ${_quantile(drops, 0.75)?.toStringAsFixed(3)}  (n = ${drops.length})');
  stdout.writeln('\n== 3. adjustedClose da fonte contra os proventos da B3, '
      '2016-09 a 2026-09 ==');
  stdout.writeln('  ativos: ${adjustments.length}  desvio mediano '
      '${_pc(_median(deviations))}  p90 ${_pc(_quantile(deviations, 0.9))}  '
      'acima de 5%: ${deviations.where((d) => d > 0.05).length}');
  adjustments.sort((a, b) =>
      (b['desvio']! as double).compareTo(a['desvio']! as double));
  for (final x in adjustments.take(10)) {
    stdout.writeln('    ${(x['ticker']! as String).padRight(7)} '
        'desvio ${_pc(x['desvio'] as double?)}  '
        '${x['proventos']} proventos');
  }
  stdout.writeln('\n== 4. Coortes: retorno total − de preço, 36 meses, '
      'mediana por coorte ==');
  for (final e in byCohort.entries) {
    stdout.writeln('  ${e.key}: ${_pc(_median(e.value))}  (n = ${e.value.length})');
  }
  stdout.writeln('  proventos pelo preço com direito da B3, sem pregão no '
      'COTAHIST: $approximatedCohorts; sem preço nenhum: $withoutPriceCohorts');
  stdout.writeln('\n  gravado docs/validacao/proventos.json e '
      'docs/validacao/backtest_valuation_total.json');
}
