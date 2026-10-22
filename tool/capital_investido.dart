// As duas rotas do capital investido, que nunca se conferem.
//
// `FundamentalsSnapshot.investedCapital` apura pelo **financiamento**:
// `PL + dívida bruta − caixa`. `investedCapitalOperating` apura pelo lado
// **operacional**: `imobilizado + intangível + capital de giro`. A
// documentação da primeira diz que a concordância com a segunda "serve de
// teste de qualidade" — e **nada no motor faz esse teste**. A rota operacional
// só aparece num despejo de auditoria.
//
// O capital investido é o denominador do ROIC, que é o freio de reinvestimento
// `b = g/ROIC` e o veredito de fosso. Errá-lo move o preço.
//
// Uso:
//   dart run tool/capital_investido.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

double? _p(List<double> v, double q) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final i = ((s.length - 1) * q).round();
  return s[i];
}

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
      for (final s in PointInTimeView(_today).published(hist.unwrap())) {
        final fin = s.investedCapital;
        final operating = s.investedCapitalOperating;
        if (fin == null || operating == null || fin <= 0 || operating <= 0) continue;
        rows.add({
          'ticker': ticker.value,
          'exercicio': s.fiscalPeriodEnd.year,
          'financiamento': fin,
          'operacional': operating,
          'razao': fin / operating,
          'distancia': fin >= operating ? fin / operating : operating / fin,
        });
      }
    }
    stderr.writeln('');

    final d = [for (final l in rows) l['distancia']! as double];
    stdout.writeln('== ${rows.length} exercícios com as duas rotas apuradas '
        '(${rows.map((l) => l['ticker']).toSet().length} ativos) ==\n');
    stdout.writeln('  distância multiplicativa entre as rotas');
    for (final q in [0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 1.00]) {
      stdout.writeln('    p${(q * 100).toStringAsFixed(0).padLeft(3)}: '
          '${_p(d, q)!.toStringAsFixed(3)}x');
    }
    for (final lim in [1.05, 1.10, 1.25, 1.50, 2.0, 5.0]) {
      final n = d.where((x) => x > lim).length;
      stdout.writeln('  acima de ${lim.toStringAsFixed(2)}x: $n '
          '(${(100 * n / d.length).toStringAsFixed(1)}%)');
    }

    rows.sort((a, b) =>
        (b['distancia']! as double).compareTo(a['distancia']! as double));
    stdout.writeln('\n  os 15 mais distantes');
    stdout.writeln('  ticker   exerc   financiamento   operacional   distância');
    for (final l in rows.take(15)) {
      String inBillions(Object? v) => ((v! as double) / 1e9).toStringAsFixed(3);
      stdout.writeln('  ${(l['ticker']! as String).padRight(8)} '
          '${l['exercicio']}   ${inBillions(l['financiamento']).padLeft(13)}   '
          '${inBillions(l['operacional']).padLeft(11)}   '
          '${(l['distancia']! as double).toStringAsFixed(2).padLeft(9)}x');
    }

    // Viés: a rota do financiamento é sistematicamente maior ou menor?
    final logs = [for (final l in rows) math.log(l['razao']! as double)];
    final mean = logs.reduce((a, b) => a + b) / logs.length;
    stdout.writeln('\n  viés (média do log da razão fin/oper): '
        '${math.exp(mean).toStringAsFixed(4)}x');

    File('docs/validacao/capital_investido.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(rows),
    );
    stdout.writeln('  gravado em docs/validacao/capital_investido.json');
  } finally {
    await ctx.dispose();
  }
}
