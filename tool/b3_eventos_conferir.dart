// A3.1 — o registro oficial da B3 contra a inferência pelo preço.
//
// `CorporateEvents` infere desdobramento, grupamento e bonificação da razão
// entre pregões (decisão 75). O registro da B3 declara o fator (decisão 83).
// Aqui os dois se encontram, papel a papel, de 2010 em diante, para os
// emissores do universo:
//
//   cobertura  evento oficial que a inferência encontrou (mesma data ex, a três
//              dias, e fator a 6%)
//   precisão   evento inferido que o registro confirma
//
// Uso:
//   python tool/b3_baixar.py
//   python tool/b3_companhias_baixar.py
//   dart run tool/b3_eventos_conferir.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

Future<void> main() async {
  // Emissores oficiais e seus eventos, por ISIN.
  final oficiais = <String, List<OfficialShareEvent>>{};
  for (final f in Directory('data/b3/companhias').listSync().whereType<File>()) {
    final bruto = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final consulta = DateTime.parse(bruto['consultadoEm'] as String);
    for (final c in (bruto['resposta'] as List).cast<Map<String, dynamic>>()) {
      final e = B3Registry.issuer(c, consultedOn: consulta);
      if (e == null) continue;
      for (final ev in e.events) {
        if (ev.exDate.year < 2010) continue;
        oficiais.putIfAbsent(ev.isin, () => []).add(ev);
      }
    }
  }

  // Séries brutas do COTAHIST, só dos ISINs que o registro cobre.
  final series = <String, List<RawQuote>>{};
  final arquivos = Directory('data/b3')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'avista_\d{4}\.csv$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final isinsDoRegistro = <String>{
    for (final f in Directory('data/b3/companhias').listSync().whereType<File>())
      for (final c in ((jsonDecode(f.readAsStringSync())
              as Map<String, dynamic>)['resposta'] as List)
          .cast<Map<String, dynamic>>())
        for (final e in (c['stockDividends'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
          e['isinCode'] as String,
  };
  for (final f in arquivos) {
    await for (final l in f
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .skip(1)) {
      final c = l.split(';');
      if (c.length < 9) continue;
      final isin = c[2];
      // Só papéis com algum evento declarado no registro. A precisão é medida
      // sobre eles: papel sem evento declarado nunca entra, e um falso
      // positivo nele não é contado.
      if (!isinsDoRegistro.contains(isin)) continue;
      // Em UTC: data em hora local cruza o horário de verão e perde uma hora.
      final data = DateTime.tryParse('${c[0]}T00:00:00Z');
      final fech = int.tryParse(c[5]);
      final fator = int.tryParse(c[6]);
      final dis = int.tryParse(c[7]);
      if (data == null || fech == null || fator == null || dis == null) continue;
      series.putIfAbsent(isin, () => []).add(
          RawQuote(data, fech / 100 / (fator == 0 ? 1 : fator), dis));
    }
  }

  bool casa(ShareEvent inferido, OfficialShareEvent oficial) =>
      inferido.exDate.difference(oficial.exDate).inDays.abs() <= 3 &&
      (math.log(inferido.factor / oficial.factor)).abs() <= math.log(1.06);

  var oficiaisComPreco = 0, encontrados = 0, inferidos = 0, confirmados = 0;
  final perdidosPorTamanho = <String, int>{};
  final encontradosPorTamanho = <String, int>{};
  final falsos = <String>[];
  String faixa(double f) {
    final a = f >= 1 ? f : 1 / f;
    if (a < 1.21) return 'até 20% (bonificação pequena)';
    if (a < 1.6) return '21% a 60%';
    if (a < 2.5) return '1,6x a 2,5x';
    return 'acima de 2,5x';
  }

  for (final e in series.entries) {
    final quotes = e.value..sort((a, b) => a.date.compareTo(b.date));
    final primeiro = quotes.first.date, ultimo = quotes.last.date;
    final doIsin = [
      for (final o in oficiais[e.key] ?? const <OfficialShareEvent>[])
        if (!o.exDate.isBefore(primeiro) && !o.exDate.isAfter(ultimo)) o,
    ];
    final detectados = CorporateEvents.detect(quotes);
    inferidos += detectados.length;
    for (final d in detectados) {
      if (doIsin.any((o) => casa(d, o))) {
        confirmados++;
      } else if (falsos.length < 25) {
        falsos.add('${e.key} ${d.exDate.toIso8601String().substring(0, 10)} '
            '×${d.factor.toStringAsFixed(3)} (razão ${d.observedRatio.toStringAsFixed(3)})');
      }
    }
    for (final o in doIsin) {
      oficiaisComPreco++;
      final k = faixa(o.factor);
      if (detectados.any((d) => casa(d, o))) {
        encontrados++;
        encontradosPorTamanho[k] = (encontradosPorTamanho[k] ?? 0) + 1;
      } else {
        perdidosPorTamanho[k] = (perdidosPorTamanho[k] ?? 0) + 1;
      }
    }
  }

  String pc(int a, int b) => b == 0 ? '—' : '${(100 * a / b).toStringAsFixed(1)}%';
  stdout.writeln('== Registro da B3 × inferência pelo preço, 2010 em diante ==\n');
  stdout.writeln('  ISINs com evento declarado e pregão: ${series.length}');
  stdout.writeln('  eventos oficiais dentro da série de preço: $oficiaisComPreco');
  stdout.writeln('  cobertura — oficiais que a inferência encontrou: '
      '$encontrados (${pc(encontrados, oficiaisComPreco)})');
  stdout.writeln('  precisão — inferidos que o registro confirma: '
      '$confirmados de $inferidos (${pc(confirmados, inferidos)})');
  stdout.writeln('\n  cobertura por tamanho do fator:');
  for (final k in [
    'até 20% (bonificação pequena)',
    '21% a 60%',
    '1,6x a 2,5x',
    'acima de 2,5x',
  ]) {
    final a = encontradosPorTamanho[k] ?? 0, p = perdidosPorTamanho[k] ?? 0;
    stdout.writeln('    ${k.padRight(32)} ${pc(a, a + p).padLeft(6)}  ($a de ${a + p})');
  }
  stdout.writeln('\n  inferidos sem evento oficial (amostra):');
  for (final f in falsos) {
    stdout.writeln('    $f');
  }
}
