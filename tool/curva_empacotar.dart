// A2.1 — empacota as cotações recentes do Tesouro para o aplicativo.
//
// O aplicativo busca a curva do dia em tempo de execução — lendo só o começo do
// arquivo do Tesouro, ou pela função `tesouro` na web. O pacote é o recuo:
// sem rede, ou antes de a função ser publicada, a avaliação ainda tem a curva
// das últimas datas-base do build. Com mais de `TreasuryCurve.diasDeRecuo`
// dias, nem ele serve, e a avaliação recua para os dois pontos, declarando.
//
// Uso:
//   python tool/tesouro_baixar.py
//   dart run tool/curva_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'curva_ligar.dart' show lerTesouro;

const _saida = 'assets/tesouro/curva.json';

/// Datas-base guardadas: as dez mais recentes cobrem duas semanas de pregão.
const _datasBase = 10;

void main() {
  final todas = lerTesouro('data/tesouro/precotaxatesourodireto.csv');
  final bases = {for (final q in todas) q.baseDate}.toList()
    ..sort((a, b) => b.compareTo(a));
  final guardar = bases.take(_datasBase).toSet();
  final cotacoes = [for (final q in todas) if (guardar.contains(q.baseDate)) q];
  final pacote = TreasuryQuotesCodec.encode(cotacoes, geradoEm: bases.first);
  File(_saida)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(pacote));
  stdout.writeln('  datas-base: ${guardar.length}, de '
      '${guardar.reduce((a, b) => a.isBefore(b) ? a : b).toIso8601String().substring(0, 10)} a '
      '${bases.first.toIso8601String().substring(0, 10)}');
  stdout.writeln('  cotações: ${cotacoes.length}');
  stdout.writeln('  gravado $_saida');
}
