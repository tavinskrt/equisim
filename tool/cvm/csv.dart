// Leitor dos CSVs de dados abertos da CVM com campo aspado.
import 'dart:convert';
import 'dart:io';

/// CSV da CVM: `;`, aspas duplas, e quebra de linha dentro de campo aspado —
/// o quadro de intangíveis tem 24.543 linhas físicas e 24.540 registros.
List<Map<String, String>> lerCsvCvm(File f) {
  final texto = latin1.decode(f.readAsBytesSync());
  final registros = <List<String>>[];
  var campo = StringBuffer();
  var linha = <String>[];
  var aspas = false;
  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (aspas) {
      if (c == '"') {
        if (i + 1 < texto.length && texto[i + 1] == '"') {
          campo.write('"');
          i++;
        } else {
          aspas = false;
        }
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      aspas = true;
    } else if (c == ';') {
      linha.add(campo.toString());
      campo = StringBuffer();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < texto.length && texto[i + 1] == '\n') i++;
      linha.add(campo.toString());
      campo = StringBuffer();
      if (linha.length > 1 || linha.first.isNotEmpty) registros.add(linha);
      linha = <String>[];
    } else {
      campo.write(c);
    }
  }
  if (campo.isNotEmpty || linha.isNotEmpty) {
    linha.add(campo.toString());
    registros.add(linha);
  }
  if (registros.isEmpty) return const [];
  final cabecalho = registros.first;
  return [
    for (final r in registros.skip(1))
      {
        for (var k = 0; k < cabecalho.length && k < r.length; k++)
          cabecalho[k]: r[k],
      },
  ];
}
