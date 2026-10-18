// B8 — o tamanho da reapresentação no *point-in-time*.
//
// **O defeito.** A ingestão adota a **última versão** de cada documento da CVM,
// e 24,8% dos anuais têm mais de uma. A data que viaja com o documento é a de
// recebimento **daquela** versão. Numa avaliação datada, o corte
// *point-in-time* compara essa data com a data da coorte: quando a última
// versão chegou depois, o exercício inteiro some, e a coorte recua para a fonte
// de mercado — embora a versão **original** estivesse pública na época.
//
// A evidência que abriu o item: a DFP de 2023 da USIM3 tem recebimento em
// 16/01/2025; em 04/09/2024 aquele ano ficava sem CVM.
//
// **Consertar exige a base bruta** — guardar cada versão com a data dela é
// trabalho de ingestão, e `data/cvm` não sobrevive ao clone (item C5). **Medir
// não exige**: o pacote versionado traz a data de recebimento de cada
// documento, e com ela dá para contar quantos exercícios cada coorte perde por
// chegarem tarde demais.
//
// **O atraso regulamentar é a régua.** A DFP vence três meses depois do fecho
// do exercício; o ITR, 45 dias depois do fecho do trimestre. Recebimento além
// disso é entrega atrasada ou reapresentação — o pacote não distingue as duas,
// e o documento diz isso.
//
// Este programa **não vai à rede** e não precisa da entrada congelada: ele lê
// só `assets/cvm/documentos.json`, que é versionado.
//
// Uso:
//   dart run tool/reapresentacao.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

const _package = 'assets/cvm/documentos.json';
const _output = 'docs/validacao/reapresentacao.json';

/// Prazo regulamentar de entrega, em dias corridos depois do fecho.
///
/// A DFP vence em três meses; o ITR, em 45 dias. Os números são de calendário,
/// e a folga de alguns dias não muda a leitura: o que este corte separa é
/// entrega no prazo de documento que chegou meses — ou anos — depois.
const _dfpDeadline = 92;
const _itrDeadline = 45;

/// As datas de coorte da validação trimestral (C1c): fim de cada trimestre de
/// 31/03/2018 a 30/09/2025.
List<DateTime> _cohorts() {
  final out = <DateTime>[];
  for (var year = 2018; year <= 2025; year++) {
    for (final month in [3, 6, 9, 12]) {
      final end = DateTime(year, month + 1, 0);
      if (end.isBefore(DateTime(2018, 3, 31))) continue;
      if (end.isAfter(DateTime(2025, 9, 30))) continue;
      out.add(end);
    }
  }
  return out;
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantile(List<double> v, double p) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round()];
}

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  final file = File(_package);
  if (!file.existsSync()) {
    stderr.writeln('$_package não existe. Rode antes:');
    stderr.writeln('  dart run tool/cvm_empacotar.dart');
    exitCode = 2;
    return;
  }
  final docs = CvmDocumentCodec.decodePackage(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);

  // --- O atraso de cada documento ------------------------------------------
  final dfpDelay = <double>[];
  final itrDelay = <double>[];
  var withoutDate = 0;
  var lateDfp = 0;
  var lateItr = 0;
  final worst = <({String ticker, String end, String received, int days})>[];

  for (final e in docs.entries) {
    for (final d in e.value) {
      final received = d.current.receiptDate;
      if (received == null) {
        withoutDate++;
        continue;
      }
      final days = received.difference(d.periodEnd).inDays;
      final dfp = d.kind == CvmDocumentKind.dfp;
      (dfp ? dfpDelay : itrDelay).add(days.toDouble());
      if (days > (dfp ? _dfpDeadline : _itrDeadline)) {
        if (dfp) {
          lateDfp++;
        } else {
          lateItr++;
        }
        worst.add((
          ticker: e.key,
          end: _day(d.periodEnd),
          received: _day(received),
          days: days,
        ));
      }
    }
  }
  worst.sort((a, b) => b.days.compareTo(a.days));

  // --- Quanto cada coorte perde --------------------------------------------
  //
  // Um exercício "devia estar público" na coorte quando o prazo regulamentar
  // dele já venceu antes dela. Some quando a **única** versão que o pacote tem
  // chegou depois — e é exatamente o que a versão original teria evitado.
  final byCohort = <Map<String, dynamic>>[];
  for (final date in _cohorts()) {
    var shouldBe = 0;
    var lost = 0;
    final lostTickers = <String>{};
    for (final e in docs.entries) {
      for (final d in e.value) {
        final received = d.current.receiptDate;
        if (received == null) continue;
        final term = d.periodEnd.add(Duration(
          days: d.kind == CvmDocumentKind.dfp ? _dfpDeadline : _itrDeadline,
        ));
        if (!term.isBefore(date)) continue;
        shouldBe++;
        if (received.isAfter(date)) {
          lost++;
          lostTickers.add(e.key);
        }
      }
    }
    byCohort.add({
      'coorte': _day(date),
      'deviamEstarPublicos': shouldBe,
      'perdidosPelaVersaoTardia': lost,
      'fracao': shouldBe == 0 ? null : lost / shouldBe,
      'tickersAtingidos': lostTickers.length,
    });
  }

  final result = {
    'medidoEm': _day(DateTime(2026, 9, 14)),
    'fonte': _package,
    'documentos': dfpDelay.length + itrDelay.length,
    'semDataDeRecebimento': withoutDate,
    'atrasoEmDias': {
      'dfp': {
        'n': dfpDelay.length,
        'p50': _median(dfpDelay),
        'p90': _quantile(dfpDelay, 0.9),
        'max': dfpDelay.isEmpty ? null : dfpDelay.reduce((a, b) => a > b ? a : b),
        'foraDoPrazo': lateDfp,
        'prazoEmDias': _dfpDeadline,
      },
      'itr': {
        'n': itrDelay.length,
        'p50': _median(itrDelay),
        'p90': _quantile(itrDelay, 0.9),
        'max': itrDelay.isEmpty ? null : itrDelay.reduce((a, b) => a > b ? a : b),
        'foraDoPrazo': lateItr,
        'prazoEmDias': _itrDeadline,
      },
    },
    'porCoorte': byCohort,
    'pioresAtrasos': [
      for (final p in worst.take(15))
        {
          'ticker': p.ticker,
          'fimDoExercicio': p.end,
          'recebidoEm': p.received,
          'diasDeAtraso': p.days,
        },
    ],
  };

  File(_output).writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(result),
  );
  _printReport(result);
  stderr.writeln('\nescrito $_output');
}

void _printReport(Map<String, dynamic> r) {
  String n(Object? v, [int c = 0]) =>
      v == null ? '—' : (v as num).toDouble().toStringAsFixed(c);

  stdout.writeln('\n=== B8 — O TAMANHO DA REAPRESENTAÇÃO ===');
  stdout.writeln('documentos no pacote: ${r['documentos']}   '
      'sem data de recebimento: ${r['semDataDeRecebimento']}');

  final a = r['atrasoEmDias'] as Map<String, dynamic>;
  stdout.writeln('\n-- atraso entre o fecho e o recebimento, em dias --');
  for (final k in ['dfp', 'itr']) {
    final m = a[k] as Map<String, dynamic>;
    stdout.writeln('  ${k.toUpperCase().padRight(4)} n=${m['n']}  '
        'p50 ${n(m['p50'])}  p90 ${n(m['p90'])}  máx ${n(m['max'])}   '
        'além do prazo de ${m['prazoEmDias']} dias: ${m['foraDoPrazo']}');
  }

  stdout.writeln('\n-- o que cada coorte perde por versão tardia --');
  stdout.writeln('  coorte       deviam estar   perdidos   fração   tickers');
  for (final c in (r['porCoorte'] as List).cast<Map>()) {
    final f = c['fracao'];
    stdout.writeln('  ${c['coorte']}   '
        '${c['deviamEstarPublicos'].toString().padLeft(10)}   '
        '${c['perdidosPelaVersaoTardia'].toString().padLeft(8)}   '
        '${f == null ? '   —' : '${((f as num) * 100).toStringAsFixed(1)}%'.padLeft(6)}   '
        '${c['tickersAtingidos'].toString().padLeft(6)}');
  }

  stdout.writeln('\n-- os piores atrasos --');
  for (final p in (r['pioresAtrasos'] as List).cast<Map>()) {
    stdout.writeln('  ${p['ticker'].toString().padRight(8)} '
        'fecho ${p['fimDoExercicio']}  recebido ${p['recebidoEm']}  '
        '${p['diasDeAtraso']} dias');
  }
}
