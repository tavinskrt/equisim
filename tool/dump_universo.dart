import 'dart:convert';
import 'dart:io';
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main(List<String> a) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final u = (await ctx.fundamentals.universe()).unwrap();
    final perfis = <Map<String, Object?>>[];
    for (final t in u) {
      final p = await ctx.fundamentals.profile(t);
      perfis.add({
        'ticker': t.value,
        'nome': p.isOk ? p.unwrap().name : null,
        'setor': p.isOk ? p.unwrap().sector.key : null,
      });
    }
    File('docs/validacao/universo.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(perfis));
    stdout.writeln('${perfis.length} tickers -> docs/validacao/universo.json');
  } finally {
    await ctx.dispose();
  }
}
