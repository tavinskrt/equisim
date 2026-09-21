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

const _pacote = 'assets/cvm/documentos.json';
const _saida = 'docs/validacao/reapresentacao.json';

/// Prazo regulamentar de entrega, em dias corridos depois do fecho.
///
/// A DFP vence em três meses; o ITR, em 45 dias. Os números são de calendário,
/// e a folga de alguns dias não muda a leitura: o que este corte separa é
/// entrega no prazo de documento que chegou meses — ou anos — depois.
const _prazoDfp = 92;
const _prazoItr = 45;

/// As datas de coorte da validação trimestral (C1c): fim de cada trimestre de
/// 31/03/2018 a 30/09/2025.
List<DateTime> _coortes() {
  final out = <DateTime>[];
  for (var ano = 2018; ano <= 2025; ano++) {
    for (final mes in [3, 6, 9, 12]) {
      final fim = DateTime(ano, mes + 1, 0);
      if (fim.isBefore(DateTime(2018, 3, 31))) continue;
      if (fim.isAfter(DateTime(2025, 9, 30))) continue;
      out.add(fim);
    }
  }
  return out;
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantil(List<double> v, double p) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round()];
}

String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  final arquivo = File(_pacote);
  if (!arquivo.existsSync()) {
    stderr.writeln('$_pacote não existe. Rode antes:');
    stderr.writeln('  dart run tool/cvm_empacotar.dart');
    exitCode = 2;
    return;
  }
  final docs = CvmDocumentCodec.decodePackage(
      jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);

  // --- O atraso de cada documento ------------------------------------------
  final atrasoDfp = <double>[];
  final atrasoItr = <double>[];
  var semData = 0;
  var foraDoPrazoDfp = 0;
  var foraDoPrazoItr = 0;
  final piores = <({String ticker, String fim, String recebido, int dias})>[];

  for (final e in docs.entries) {
    for (final d in e.value) {
      final recebido = d.current.receiptDate;
      if (recebido == null) {
        semData++;
        continue;
      }
      final dias = recebido.difference(d.periodEnd).inDays;
      final dfp = d.kind == CvmDocumentKind.dfp;
      (dfp ? atrasoDfp : atrasoItr).add(dias.toDouble());
      if (dias > (dfp ? _prazoDfp : _prazoItr)) {
        if (dfp) {
          foraDoPrazoDfp++;
        } else {
          foraDoPrazoItr++;
        }
        piores.add((
          ticker: e.key,
          fim: _dia(d.periodEnd),
          recebido: _dia(recebido),
          dias: dias,
        ));
      }
    }
  }
  piores.sort((a, b) => b.dias.compareTo(a.dias));

  // --- Quanto cada coorte perde --------------------------------------------
  //
  // Um exercício "devia estar público" na coorte quando o prazo regulamentar
  // dele já venceu antes dela. Some quando a **única** versão que o pacote tem
  // chegou depois — e é exatamente o que a versão original teria evitado.
  final porCoorte = <Map<String, dynamic>>[];
  for (final data in _coortes()) {
    var deviaEstar = 0;
    var perdidos = 0;
    final tickersPerdidos = <String>{};
    for (final e in docs.entries) {
      for (final d in e.value) {
        final recebido = d.current.receiptDate;
        if (recebido == null) continue;
        final prazo = d.periodEnd.add(Duration(
          days: d.kind == CvmDocumentKind.dfp ? _prazoDfp : _prazoItr,
        ));
        if (!prazo.isBefore(data)) continue;
        deviaEstar++;
        if (recebido.isAfter(data)) {
          perdidos++;
          tickersPerdidos.add(e.key);
        }
      }
    }
    porCoorte.add({
      'coorte': _dia(data),
      'deviamEstarPublicos': deviaEstar,
      'perdidosPelaVersaoTardia': perdidos,
      'fracao': deviaEstar == 0 ? null : perdidos / deviaEstar,
      'tickersAtingidos': tickersPerdidos.length,
    });
  }

  final resultado = {
    'medidoEm': _dia(DateTime(2026, 9, 14)),
    'fonte': _pacote,
    'documentos': atrasoDfp.length + atrasoItr.length,
    'semDataDeRecebimento': semData,
    'atrasoEmDias': {
      'dfp': {
        'n': atrasoDfp.length,
        'p50': _mediana(atrasoDfp),
        'p90': _quantil(atrasoDfp, 0.9),
        'max': atrasoDfp.isEmpty ? null : atrasoDfp.reduce((a, b) => a > b ? a : b),
        'foraDoPrazo': foraDoPrazoDfp,
        'prazoEmDias': _prazoDfp,
      },
      'itr': {
        'n': atrasoItr.length,
        'p50': _mediana(atrasoItr),
        'p90': _quantil(atrasoItr, 0.9),
        'max': atrasoItr.isEmpty ? null : atrasoItr.reduce((a, b) => a > b ? a : b),
        'foraDoPrazo': foraDoPrazoItr,
        'prazoEmDias': _prazoItr,
      },
    },
    'porCoorte': porCoorte,
    'pioresAtrasos': [
      for (final p in piores.take(15))
        {
          'ticker': p.ticker,
          'fimDoExercicio': p.fim,
          'recebidoEm': p.recebido,
          'diasDeAtraso': p.dias,
        },
    ],
  };

  File(_saida).writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(resultado),
  );
  _imprimir(resultado);
  stderr.writeln('\nescrito $_saida');
}

void _imprimir(Map<String, dynamic> r) {
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
