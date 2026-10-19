// A2.1 — empacota as cotações recentes do Tesouro para o aplicativo.
//
// No nativo, o aplicativo busca a curva do dia em tempo de execução, lendo só o
// começo do arquivo do Tesouro, e o pacote é o recuo sem rede. **Na web o pacote
// é a única fonte** (decisão 86): rode os dois comandos abaixo antes de cada
// `flutter build web`. Com mais de `TreasuryCurve.fallbackDays` dias, o pacote
// não serve, e a avaliação recua para os dois pontos, declarando por quê.
//
// Uso:
//   python tool/tesouro_baixar.py
//   dart run tool/curva_empacotar.dart

import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'curva_ligar.dart' show readTreasury;

const _output = 'assets/tesouro/curva.json';

/// Datas-base guardadas: as dez mais recentes cobrem duas semanas de pregão.
const _baseDates = 10;

void main() {
  final allRows = readTreasury('data/tesouro/precotaxatesourodireto.csv');
  final bases = {for (final q in allRows) q.baseDate}.toList()
    ..sort((a, b) => b.compareTo(a));
  final store = bases.take(_baseDates).toSet();
  final quotes = [for (final q in allRows) if (store.contains(q.baseDate)) q];
  final package = TreasuryQuotesCodec.encode(quotes, generatedAt: bases.first);
  File(_output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(package));
  stdout.writeln('  datas-base: ${store.length}, de '
      '${store.reduce((a, b) => a.isBefore(b) ? a : b).toIso8601String().substring(0, 10)} a '
      '${bases.first.toIso8601String().substring(0, 10)}');
  stdout.writeln('  cotações: ${quotes.length}');
  stdout.writeln('  gravado $_output');
}
