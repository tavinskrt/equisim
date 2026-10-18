// Leitor dos CSVs de dados abertos da CVM com campo aspado.
import 'dart:convert';
import 'dart:io';

/// CSV da CVM: `;`, aspas duplas, e quebra de linha dentro de campo aspado —
/// o quadro de intangíveis tem 24.543 linhas físicas e 24.540 registros.
List<Map<String, String>> readCvmCsv(File f) {
  final text = latin1.decode(f.readAsBytesSync());
  final records = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ';') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field = StringBuffer();
      if (row.length > 1 || row.first.isNotEmpty) records.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    records.add(row);
  }
  if (records.isEmpty) return const [];
  final header = records.first;
  return [
    for (final r in records.skip(1))
      {
        for (var k = 0; k < header.length && k < r.length; k++)
          header[k]: r[k],
      },
  ];
}
