import 'dart:convert';
import 'dart:io';
import 'validation/context.dart';

Future<void> main(List<String> a) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final u = (await ctx.fundamentals.universe()).unwrap();
    final profiles = <Map<String, Object?>>[];
    for (final t in u) {
      final p = await ctx.fundamentals.profile(t);
      profiles.add({
        'ticker': t.value,
        'nome': p.isOk ? p.unwrap().name : null,
        'setor': p.isOk ? p.unwrap().sector.key : null,
      });
    }
    File('docs/validacao/universo.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(profiles));
    stdout.writeln('${profiles.length} tickers -> docs/validacao/universo.json');
  } finally {
    await ctx.dispose();
  }
}
