// A3 — COTAHIST da B3: eventos de ações e preço de quem deixou de existir.
//
// Lê os arquivos anuais do COTAHIST (fechamento bruto de todo papel negociado),
// infere os eventos de ações por `CorporateEvents`, ajusta a série, e confere
// contra o `close` da fonte de mercado — que já vem ajustado por desdobramento,
// grupamento e bonificação. **Depois do ajuste os dois têm de bater**; onde não
// batem, ou o evento não foi detectado, ou foi inventado.
//
// Uso:
//   curl -O https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A2024.ZIP
//   (descompactar em data/b3)
//   dart run tool/b3_cotahist.dart data/b3
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

/// Um papel no COTAHIST: ISIN, nome e fechamentos brutos.
class _Security {
  final String ticker;
  String isin = '';
  String name = '';
  final List<RawQuote> tradingDays = [];
  _Security(this.ticker);
}

/// Lê um arquivo anual em fluxo, só mercado à vista e lote padrão.
///
/// Layout do registro `01`, posições da B3 (base 1): data 3–10, BDI 11–12,
/// ticker 13–24, mercado 25–27, nome 28–39, fechamento 109–121 (duas casas
/// implícitas), ISIN 231–242, `DISMES` 243–245.
Future<void> _read(File f, Map<String, _Security> securities) async {
  final rows =
      f.openRead().transform(latin1.decoder).transform(const LineSplitter());
  await for (final l in rows) {
    if (l.length < 245 || !l.startsWith('01')) continue;
    if (l.substring(24, 27) != '010') continue; // à vista
    if (l.substring(10, 12) != '02') continue; // lote padrão
    final tk = l.substring(12, 24).trim();
    // Em UTC: data em hora local cruza o horário de verão e perde uma hora.
    final date = DateTime.tryParse(
        '${l.substring(2, 6)}-${l.substring(6, 8)}-${l.substring(8, 10)}T00:00:00Z');
    final cents = int.tryParse(l.substring(108, 121));
    final dismes = int.tryParse(l.substring(242, 245));
    if (date == null || cents == null || dismes == null) continue;
    final p = securities.putIfAbsent(tk, () => _Security(tk));
    p.isin = l.substring(230, 242).trim();
    p.name = l.substring(27, 39).trim();
    p.tradingDays.add(RawQuote(date, cents / 100.0, dismes));
  }
}

Future<void> main(List<String> args) async {
  final dir = Directory(args.isEmpty ? 'data/b3' : args.first);
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toUpperCase().endsWith('.TXT'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('nenhum COTAHIST_A*.TXT em ${dir.path}');
    exit(2);
  }

  final securities = <String, _Security>{};
  for (final f in files) {
    stderr.writeln('  lendo ${f.path}');
    await _read(f, securities);
  }

  final uni = (jsonDecode(File('docs/validacao/universo.json').readAsStringSync())
          as List)
      .map((e) => (e as Map<String, dynamic>)['ticker'] as String)
      .toSet();

  var events = 0;
  final perShare = <String, List<ShareEvent>>{};
  for (final p in securities.values) {
    final e = CorporateEvents.detect(p.tradingDays);
    if (e.isNotEmpty) perShare[p.ticker] = e;
    events += e.length;
  }

  stdout.writeln('== COTAHIST — ${files.length} arquivo(s) ==\n');
  stdout.writeln('  papéis à vista, lote padrão: ${securities.length}');
  stdout.writeln('  do universo de hoje presentes: '
      '${uni.where(securities.containsKey).length} de ${uni.length}');
  stdout.writeln('  fora do universo de hoje: '
      '${securities.keys.where((t) => !uni.contains(t)).length}');
  stdout.writeln('  eventos de ações detectados: $events em ${perShare.length} papéis');
  for (final e in perShare.entries.take(30)) {
    stdout.writeln('    ${e.key.padRight(7)} ${[
      for (final x in e.value)
        '${x.exDate.toIso8601String().substring(0, 10)} ×${x.factor.toStringAsFixed(3)}'
    ].join('  ')}');
  }

  // --- Conferência contra o close ajustado da fonte de mercado -------------
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    var days = 0, matching = 0, checkedSecurities = 0;
    final badDays = <String>[];
    final discordant = <String, ({int days, int bad, double worst})>{};
    for (final tk in uni) {
      final p = securities[tk];
      if (p == null || p.tradingDays.isEmpty) continue;
      final ini = p.tradingDays.map((q) => q.date).reduce((a, b) => a.isBefore(b) ? a : b);
      final end = p.tradingDays.map((q) => q.date).reduce((a, b) => a.isAfter(b) ? a : b);
      final r = await ctx.prices.daily(Ticker.parse(tk), DateRange(ini, end));
      if (r.isErr) continue;
      final market = {
        for (final pt in r.unwrap().points)
          DateTime.utc(pt.date.year, pt.date.month, pt.date.day): pt.close,
      };
      final adjusted = CorporateEvents.adjust(p.tradingDays, perShare[tk] ?? const []);
      // **Retorno diário, e não nível.** A fonte de mercado ajusta pelos
      // eventos até HOJE; com anos parciais do COTAHIST, um evento fora da
      // janela vira deslocamento constante em todo pregão — foi o que a
      // primeira conferência mediu (68%, com papéis discordando em 499 de 499
      // dias e zero eventos). No retorno o deslocamento some, e o que resta é
      // evento não detectado ou inventado.
      var d = 0, bad = 0;
      var worst = 0.0;
      for (var k = 1; k < adjusted.length; k++) {
        final a0 = adjusted[k - 1], a1 = adjusted[k];
        if (a1.date.difference(a0.date).inDays > 7) continue;
        final m0 = market[DateTime.utc(a0.date.year, a0.date.month, a0.date.day)];
        final m1 = market[DateTime.utc(a1.date.year, a1.date.month, a1.date.day)];
        if (m0 == null || m1 == null || m0 <= 0 || m1 <= 0 || a0.close <= 0) {
          continue;
        }
        d++;
        final deviation = ((a1.close / a0.close) / (m1 / m0) - 1).abs();
        if (deviation <= 0.01) {
          matching++;
        } else {
          bad++;
          if (deviation > worst) worst = deviation;
          badDays.add('$tk ${a1.date.toIso8601String().substring(0, 10)} '
              'cotahist ${(a1.close / a0.close).toStringAsFixed(4)} '
              'mercado ${(m1 / m0).toStringAsFixed(4)}');
        }
      }
      if (d == 0) continue;
      checkedSecurities++;
      days += d;
      if (bad > 0) discordant[tk] = (days: d, bad: bad, worst: worst);
    }
    stdout.writeln('\n== Conferência contra o close ajustado da fonte ==');
    stdout.writeln('  papéis conferidos: $checkedSecurities');
    stdout.writeln('  pares de pregões conferidos (retorno diário): $days');
    stdout.writeln('  retornos que batem a 1%: $matching '
        '(${days == 0 ? "—" : (100 * matching / days).toStringAsFixed(2)}%)');
    stdout.writeln('  papéis com algum pregão discordante: ${discordant.length}');
    final worst = discordant.entries.toList()
      ..sort((a, b) => b.value.bad.compareTo(a.value.bad));
    for (final e in worst.take(15)) {
      stdout.writeln('    ${e.key.padRight(7)} ${e.value.bad}/${e.value.days} '
          'retornos fora de 1%, pior ${(100 * e.value.worst).toStringAsFixed(1)}%'
          '   eventos: ${perShare[e.key]?.length ?? 0}');
    }

    stdout.writeln('');
    stdout.writeln('  amostra de retornos discordantes:');
    for (final x in badDays.take(25)) {
      stdout.writeln('    $x');
    }

    File('docs/validacao/b3_eventos.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        for (final e in perShare.entries)
          e.key: [
            for (final x in e.value)
              {
                'dataEx': x.exDate.toIso8601String().substring(0, 10),
                'fator': x.factor,
                'razaoObservada': x.observedRatio,
              }
          ],
      }),
    );
    stdout.writeln('\n  gravado docs/validacao/b3_eventos.json');
  } finally {
    await ctx.dispose();
  }
}
