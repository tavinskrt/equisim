// A razão de unidade e a tolerância que aperta onde deveria afrouxar.
//
// `ValuationCascade.quotedUnitRatio` mede `ações × preço ÷ valor de mercado` e
// arredonda, recusando o resultado quando ele fica a mais de **0,12 absoluto**
// de um inteiro. A tolerância é absoluta, e a razão não é: para a ação comum
// ela vale 12% de folga; para uma unit de dez ações, 1,2%. O aperto cresce
// exatamente onde o fator errado custa mais.
//
// Uso:
//   dart run tool/unidade.dart
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
      final view = PointInTimeView(_today);
      final pub = view.published(hist.unwrap());
      if (pub.isEmpty) continue;
      final latest = pub.last;

      final series = await ctx.prices.daily(
        ticker,
        DateRange(_today.subtract(const Duration(days: 30)), _today),
      );
      if (series.isErr || series.unwrap().points.isEmpty) continue;
      final price = series.unwrap().points.last.close;

      final n = latest.sharesOutstanding;
      final marketValue = latest.marketCap;
      if (n == null || n <= 0 || marketValue == null || marketValue <= 0 || price <= 0) continue;

      final raw = n * price / marketValue;
      if (!raw.isFinite) continue;
      final whole = raw.roundToDouble();
      final deviation = (raw - whole).abs();

      rows.add({
        'ticker': ticker.value,
        'bruto': raw,
        'inteiro': whole,
        'desvioAbsoluto': deviation,
        'desvioRelativo': whole > 0 ? deviation / whole : null,
        'aceitoHoje': whole >= 1 &&
            whole <= ValuationCascade.maxSharesPerUnit &&
            deviation <= 0.12,
        'adotadoHoje': ValuationCascade.quotedUnitRatio(
          sharesOutstanding: n,
          marketCap: marketValue,
          marketPrice: price,
        ),
      });
    }
    stderr.writeln('');

    rows.sort((a, b) => (b['bruto']! as double).compareTo(a['bruto']! as double));

    stdout.writeln('== ${rows.length} ativos com razão mensurável ==\n');
    stdout.writeln('  ticker    bruto   inteiro   desvio abs   desvio rel  adotado');
    for (final l in rows) {
      final raw = l['bruto']! as double;
      if (raw < 1.5 && (l['desvioAbsoluto']! as double) < 0.12) continue;
      final rel = l['desvioRelativo'] as double?;
      stdout.writeln('  ${(l['ticker']! as String).padRight(8)} '
          '${raw.toStringAsFixed(4).padLeft(8)} '
          '${(l['inteiro']! as double).toStringAsFixed(0).padLeft(7)} '
          '${(l['desvioAbsoluto']! as double).toStringAsFixed(4).padLeft(11)} '
          '${rel == null ? "     -" : "${(rel * 100).toStringAsFixed(2)}%".padLeft(11)} '
          '${(l['adotadoHoje']! as double).toStringAsFixed(0).padLeft(6)}');
    }

    // Quantos seriam recusados hoje mas aceitos por tolerância relativa?
    for (final tol in [0.02, 0.03, 0.05, 0.08]) {
      final flips = rows.where((l) {
        final whole = l['inteiro']! as double;
        final rel = l['desvioRelativo'] as double?;
        return whole > 1 &&
            whole <= ValuationCascade.maxSharesPerUnit &&
            l['aceitoHoje'] == false &&
            rel != null &&
            rel <= tol;
      }).toList();
      stdout.writeln('\n  tolerância relativa de ${(tol * 100).toStringAsFixed(0)}%: '
          '${flips.length} unit(s) que hoje caem para 1 '
          '${flips.map((l) => l['ticker']).join(", ")}');
    }

    File('docs/validacao/unidade.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(rows),
    );
    stdout.writeln('\n  gravado em docs/validacao/unidade.json');
  } finally {
    await ctx.dispose();
  }
}
