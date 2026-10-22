// O grupamento que a regra do maior sempre ignora.
//
// `quotedShares` compara duas candidatas a divisor — a implícita no valor de
// mercado e a conciliada pelas demonstrações — e, na divergência, **adota a
// maior**, porque divisor pequeno demais infla o preço justo e produz sinal
// falso de barato.
//
// A regra tem um viés estrutural que ninguém escolheu: `reconciledShares` só
// pode confirmar a contagem **do exercício** — o árbitro `N = lucro ÷ LPA` usa
// dois campos das mesmas demonstrações. Um **grupamento** posterior reduz a
// contagem corrente sem tocar a do exercício, de modo que a candidata contábil
// fica maior **sempre**, e sempre vence. Um desdobramento faz o contrário e a
// regra o absorve bem. O viés é assimétrico, e só contra grupamento.
//
// Uso:
//   dart run tool/grupamento.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final rows = <Map<String, Object?>>[];

    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');

      final hist = await ctx.fundamentals.history(ticker);
      if (hist.isErr) continue;
      final pub = PointInTimeView(_today).published(hist.unwrap());
      if (pub.isEmpty) continue;
      final latest = pub.last;

      final series = await ctx.prices.daily(
        ticker, DateRange(_today.subtract(const Duration(days: 30)), _today));
      if (series.isErr || series.unwrap().points.isEmpty) continue;
      final price = series.unwrap().points.last.close;

      final u = ValuationCascade.quotedUnitRatio(
        sharesOutstanding: latest.sharesOutstanding,
        marketCap: latest.marketCap,
        marketPrice: price,
      );
      final q = ValuationCascade.quotedShares(
        latest: latest, marketPrice: price, sharesPerQuote: u, published: pub);
      if (q == null) continue;

      final current = latest.sharesOutstanding;
      final fiscalYearValue = latest.sharesOutstandingAsOf;
      final wasGrouped = current != null && fiscalYearValue != null &&
          current > 0 && fiscalYearValue > current * 1.5;

      rows.add({
        'ticker': ticker.value,
        'u': u,
        'fonte': q.source.name,
        'divisor': q.count,
        'mercado': q.fromMarketCap,
        'balanco': q.fromStatements,
        'diverge': q.diverge,
        'corrente': current,
        'doExercicio': fiscalYearValue,
        'grupamentoAparente': wasGrouped,
        'razaoDivisor': q.fromMarketCap != null && q.fromMarketCap! > 0
            ? q.count / q.fromMarketCap!
            : null,
      });
    }
    stderr.writeln('');

    final diverging = rows.where((l) => l['diverge'] == true).toList();
    final bookWins =
        diverging.where((l) => l['fonte'] == 'reconciled').toList();
    final grouped = rows.where((l) => l['grupamentoAparente'] == true).toList();
    final bookGrouped =
        grouped.where((l) => l['fonte'] == 'reconciled').toList();

    stdout.writeln('== ${rows.length} ativos com divisor apurado ==\n');
    stdout.writeln('  divergem além da banda:            ${diverging.length}');
    stdout.writeln('  ...e a contábil vence:             ${bookWins.length}');
    stdout.writeln('  grupamento aparente (exerc > 1,5x corrente): ${grouped.length}');
    stdout.writeln('  ...e a contábil vence:             ${bookGrouped.length}');

    grouped.sort((a, b) => ((b['doExercicio']! as double) / (b['corrente']! as double))
        .compareTo((a['doExercicio']! as double) / (a['corrente']! as double)));
    stdout.writeln('\n  ticker    exerc/corrente   fonte        divisor/mercado');
    for (final l in grouped) {
      final f = (l['doExercicio']! as double) / (l['corrente']! as double);
      final rd = l['razaoDivisor'] as double?;
      stdout.writeln('  ${(l['ticker']! as String).padRight(8)} '
          '${f.toStringAsFixed(2).padLeft(14)}x  '
          '${(l['fonte']! as String).padRight(12)} '
          '${rd == null ? "-" : "${rd.toStringAsFixed(2)}x"}');
    }

    File('docs/validacao/grupamento.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(rows),
    );
    stdout.writeln('\n  gravado em docs/validacao/grupamento.json');
  } finally {
    await ctx.dispose();
  }
}
