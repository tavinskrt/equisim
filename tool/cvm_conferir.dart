// Roda o leitor do plano de contas da CVM sobre os arquivos REAIS.
//
// O `cvm_chart_test.dart` prova a lógica sobre linhas sintéticas. Isto prova
// que ela sobrevive aos 286 CNPJs do universo — que é onde a conferência de
// campos achou os quatro layouts e a armadilha do `3.11`.
//
// Duas verificações que só o dado real permite:
//
// 1. **Identidade de balanço.** `Ativo Total = Passivo Total` tem de valer em
//    todo documento. É a conferência analítica que a §2.17 dizia não existir.
// 2. **Identidade da DRE.** `antes dos tributos + tributos = lucro`, dentro do
//    arredondamento da fonte.
//
// Uso:
//   dart run tool/cvm_conferir.dart <diretorio-com-os-csv-extraidos>
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

/// Uma linha crua do CSV, antes de virar [CvmAccountLine].
class _Row {
  final String denom;
  final CvmAccountLine account;
  _Row(this.denom, this.account);
}

/// Lê um CSV da CVM: `latin-1`, separador `;`, primeira linha de cabeçalho.
///
/// **Não usa divisão ingênua por `;`** — os campos podem vir entre aspas com
/// separador dentro, e `DENOM_CIA` traz vírgula e ponto e vírgula em razão
/// social. O analisador abaixo respeita aspas.
List<Map<String, String>> readCsv(File f) {
  final text = latin1.decode(f.readAsBytesSync());
  final rows = const LineSplitter().convert(text);
  if (rows.isEmpty) return const [];
  final headerRow = _fields(rows.first);
  final out = <Map<String, String>>[];
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].trim().isEmpty) continue;
    final c = _fields(rows[i]);
    if (c.length != headerRow.length) continue;
    out.add({for (var j = 0; j < headerRow.length; j++) headerRow[j]: c[j]});
  }
  return out;
}

List<String> _fields(String row) {
  final out = <String>[];
  final current = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < row.length; i++) {
    final ch = row[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ';' && !inQuotes) {
      out.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  out.add(current.toString());
  return out;
}

/// Fator da coluna `ESCALA_MOEDA`.
int _scale(String? e) => (e ?? '').toUpperCase() == 'MIL' ? 1000 : 1;

Map<String, List<_Row>> _byCnpj(File f, {String? desiredOrder}) {
  final out = <String, List<_Row>>{};
  for (final r in readCsv(f)) {
    final order = r['ORDEM_EXERC'] ?? '';
    if (desiredOrder != null && !order.startsWith(desiredOrder)) continue;
    final account = CvmAccountLine.fromText(
      code: r['CD_CONTA'] ?? '',
      label: r['DS_CONTA'] ?? '',
      value: r['VL_CONTA'] ?? '',
      scale: _scale(r['ESCALA_MOEDA']),
    );
    if (account == null) continue;
    out.putIfAbsent(r['CNPJ_CIA'] ?? '', () => []).add(
        _Row(r['DENOM_CIA'] ?? '', account));
  }
  return out;
}

List<CvmAccountLine> _toChart(List<_Row> l) => [for (final x in l) x.account];

String _pc(int n, int d) => d == 0 ? '—' : '${(100 * n / d).toStringAsFixed(1)}%';

Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? '.' : args.first;
  File f(String n) => File('$dir/$n');

  // "ÚLTIMO" é o exercício de referência do documento; "PENÚLTIMO" é o
  // comparativo do ano anterior, que já virá no arquivo daquele ano.
  const last = 'Ú';

  final dre = _byCnpj(f('dfp_cia_aberta_DRE_con_2024.csv'), desiredOrder: last);
  final dreInd = _byCnpj(f('dfp_cia_aberta_DRE_ind_2024.csv'), desiredOrder: last);
  final bpa = _byCnpj(f('dfp_cia_aberta_BPA_con_2024.csv'), desiredOrder: last);
  final bpaInd = _byCnpj(f('dfp_cia_aberta_BPA_ind_2024.csv'), desiredOrder: last);
  final bpp = _byCnpj(f('dfp_cia_aberta_BPP_con_2024.csv'), desiredOrder: last);
  final bppInd = _byCnpj(f('dfp_cia_aberta_BPP_ind_2024.csv'), desiredOrder: last);

  final bridge = jsonDecode(
    File('docs/validacao/ponte_cvm.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cnpjs = {
    ...(bridge['ponte'] as Map<String, dynamic>).values.map((e) => e as String),
  };

  stdout.writeln('== Leitor do plano de contas sobre o DFP 2024 real ==');
  stdout.writeln('   ${cnpjs.length} CNPJs do universo\n');

  final byLayout = <CvmLayout, int>{};
  var withProfit = 0, withEbit = 0, withEquity = 0, withAsset = 0, fellBackToInd = 0;
  var balanceOk = 0, balanceTested = 0, dreOk = 0, dreTested = 0;
  final failures = <String>[];
  final output = <Map<String, Object?>>[];

  for (final cnpj in cnpjs) {
    // Consolidado, com recuo para individual — a conferência mostrou que
    // Sanepar, Comgás, Coelba e afins só arquivam individual.
    var dreRows = dre[cnpj];
    var bpaRows = bpa[cnpj];
    var bppRows = bpp[cnpj];
    var origin = 'consolidado';
    if (dreRows == null || dreRows.isEmpty) {
      dreRows = dreInd[cnpj];
      bpaRows = bpaInd[cnpj];
      bppRows = bppInd[cnpj];
      origin = 'individual';
      if (dreRows != null && dreRows.isNotEmpty) fellBackToInd++;
    }
    if (dreRows == null || dreRows.isEmpty) continue;

    final chartDre = CvmChart.of(_toChart(dreRows));
    final chartBal = CvmChart.of([
      ..._toChart(bpaRows ?? const []),
      ..._toChart(bppRows ?? const []),
    ]);

    byLayout[chartDre.layout] = (byLayout[chartDre.layout] ?? 0) + 1;
    final profit = chartDre.netIncome;
    final ebit = chartDre.ebit;
    final pl = chartBal.equity;
    final at = chartBal.totalAssets;
    final totalLiab = chartBal.totalLiabilities;
    if (profit != null) withProfit++;
    if (ebit != null) withEbit++;
    if (pl != null) withEquity++;
    if (at != null) withAsset++;

    // (1) Identidade de balanço.
    // `at.abs() > 1` e não `at != 0`: um ativo total de 1e-14 —
    // resíduo de leitura, não companhia — faria a razão relativa
    // estourar e inventar um balanço que não fecha.
    if (at != null && totalLiab != null && at.abs() > 1) {
      balanceTested++;
      if (((at - totalLiab).abs() / at.abs()) < 1e-6) {
        balanceOk++;
      } else {
        failures.add('${dreRows.first.denom}: ativo $at != passivo $totalLiab');
      }
    }

    // (2) Identidade da DRE.
    final before = chartDre.incomeBeforeTaxes;
    final taxes = chartDre.taxes;
    if (before != null && taxes != null && profit != null && profit.abs() > 1) {
      dreTested++;
      if (((before + taxes - profit).abs() / profit.abs()) < 0.02) dreOk++;
    }

    output.add({
      'cnpj': cnpj,
      'nome': dreRows.first.denom,
      'origem': origin,
      'layout': chartDre.layout.key,
      'receita': chartDre.revenue,
      'ebit': ebit,
      'lucro': profit,
      'lpa': chartDre.earningsPerShare,
      'ativoTotal': at,
      'patrimonioLiquido': pl,
      'naoControladores': chartBal.nonControllingInterests,
    });
  }

  final n = output.length;
  stdout.writeln('  companhias lidas: $n   (recuo para individual: $fellBackToInd)');
  stdout.writeln('  layouts detectados:');
  for (final e in byLayout.entries) {
    stdout.writeln('    ${e.value.toString().padLeft(4)}  ${e.key.key}');
  }
  stdout.writeln('');
  stdout.writeln('  lucro líquido resolvido : $withProfit / $n  ${_pc(withProfit, n)}');
  stdout.writeln('  patrimônio líquido      : $withEquity / $n  ${_pc(withEquity, n)}');
  stdout.writeln('  ativo total             : $withAsset / $n  ${_pc(withAsset, n)}');
  stdout.writeln('  EBIT (só não financeira): $withEbit / $n  ${_pc(withEbit, n)}');
  stdout.writeln('');
  stdout.writeln('  IDENTIDADE ativo = passivo : $balanceOk / $balanceTested  '
      '${_pc(balanceOk, balanceTested)}');
  stdout.writeln('  IDENTIDADE antes+trib=lucro: $dreOk / $dreTested  '
      '${_pc(dreOk, dreTested)}');
  if (failures.isNotEmpty) {
    stdout.writeln('\n  balanços que não fecham:');
    for (final x in failures.take(10)) {
      stdout.writeln('    $x');
    }
  }

  File('docs/validacao/cvm_leitura.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(output),
  );
  stdout.writeln('\n  gravado docs/validacao/cvm_leitura.json');
}
