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

final _hoje = DateTime(2026, 9, 4);

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final linhas = <Map<String, Object?>>[];

    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');

      final hist = await ctx.fundamentals.history(ticker);
      if (hist.isErr) continue;
      final view = PointInTimeView(_hoje);
      final pub = view.published(hist.unwrap());
      if (pub.isEmpty) continue;
      final latest = pub.last;

      final serie = await ctx.prices.daily(
        ticker,
        DateRange(_hoje.subtract(const Duration(days: 30)), _hoje),
      );
      if (serie.isErr || serie.unwrap().points.isEmpty) continue;
      final preco = serie.unwrap().points.last.close;

      final n = latest.sharesOutstanding;
      final vm = latest.marketCap;
      if (n == null || n <= 0 || vm == null || vm <= 0 || preco <= 0) continue;

      final bruto = n * preco / vm;
      if (!bruto.isFinite) continue;
      final inteiro = bruto.roundToDouble();
      final desvio = (bruto - inteiro).abs();

      linhas.add({
        'ticker': ticker.value,
        'bruto': bruto,
        'inteiro': inteiro,
        'desvioAbsoluto': desvio,
        'desvioRelativo': inteiro > 0 ? desvio / inteiro : null,
        'aceitoHoje': inteiro >= 1 &&
            inteiro <= ValuationCascade.maxSharesPerUnit &&
            desvio <= 0.12,
        'adotadoHoje': ValuationCascade.quotedUnitRatio(
          sharesOutstanding: n,
          marketCap: vm,
          marketPrice: preco,
        ),
      });
    }
    stderr.writeln('');

    linhas.sort((a, b) => (b['bruto']! as double).compareTo(a['bruto']! as double));

    stdout.writeln('== ${linhas.length} ativos com razão mensurável ==\n');
    stdout.writeln('  ticker    bruto   inteiro   desvio abs   desvio rel  adotado');
    for (final l in linhas) {
      final bruto = l['bruto']! as double;
      if (bruto < 1.5 && (l['desvioAbsoluto']! as double) < 0.12) continue;
      final rel = l['desvioRelativo'] as double?;
      stdout.writeln('  ${(l['ticker']! as String).padRight(8)} '
          '${bruto.toStringAsFixed(4).padLeft(8)} '
          '${(l['inteiro']! as double).toStringAsFixed(0).padLeft(7)} '
          '${(l['desvioAbsoluto']! as double).toStringAsFixed(4).padLeft(11)} '
          '${rel == null ? "     -" : "${(rel * 100).toStringAsFixed(2)}%".padLeft(11)} '
          '${(l['adotadoHoje']! as double).toStringAsFixed(0).padLeft(6)}');
    }

    // Quantos seriam recusados hoje mas aceitos por tolerância relativa?
    for (final tol in [0.02, 0.03, 0.05, 0.08]) {
      final vira = linhas.where((l) {
        final inteiro = l['inteiro']! as double;
        final rel = l['desvioRelativo'] as double?;
        return inteiro > 1 &&
            inteiro <= ValuationCascade.maxSharesPerUnit &&
            l['aceitoHoje'] == false &&
            rel != null &&
            rel <= tol;
      }).toList();
      stdout.writeln('\n  tolerância relativa de ${(tol * 100).toStringAsFixed(0)}%: '
          '${vira.length} unit(s) que hoje caem para 1 '
          '${vira.map((l) => l['ticker']).join(", ")}');
    }

    File('docs/validacao/unidade.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(linhas),
    );
    stdout.writeln('\n  gravado em docs/validacao/unidade.json');
  } finally {
    await ctx.dispose();
  }
}
