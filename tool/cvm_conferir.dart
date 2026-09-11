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
class _Linha {
  final String cnpj;
  final String denom;
  final String ordem;
  final CvmAccountLine conta;
  _Linha(this.cnpj, this.denom, this.ordem, this.conta);
}

/// Lê um CSV da CVM: `latin-1`, separador `;`, primeira linha de cabeçalho.
///
/// **Não usa divisão ingênua por `;`** — os campos podem vir entre aspas com
/// separador dentro, e `DENOM_CIA` traz vírgula e ponto e vírgula em razão
/// social. O analisador abaixo respeita aspas.
List<Map<String, String>> lerCsv(File f) {
  final texto = latin1.decode(f.readAsBytesSync());
  final linhas = const LineSplitter().convert(texto);
  if (linhas.isEmpty) return const [];
  final cab = _campos(linhas.first);
  final out = <Map<String, String>>[];
  for (var i = 1; i < linhas.length; i++) {
    if (linhas[i].trim().isEmpty) continue;
    final c = _campos(linhas[i]);
    if (c.length != cab.length) continue;
    out.add({for (var j = 0; j < cab.length; j++) cab[j]: c[j]});
  }
  return out;
}

List<String> _campos(String linha) {
  final out = <String>[];
  final atual = StringBuffer();
  var entreAspas = false;
  for (var i = 0; i < linha.length; i++) {
    final ch = linha[i];
    if (ch == '"') {
      entreAspas = !entreAspas;
    } else if (ch == ';' && !entreAspas) {
      out.add(atual.toString());
      atual.clear();
    } else {
      atual.write(ch);
    }
  }
  out.add(atual.toString());
  return out;
}

/// Fator da coluna `ESCALA_MOEDA`.
int _escala(String? e) => (e ?? '').toUpperCase() == 'MIL' ? 1000 : 1;

Map<String, List<_Linha>> _porCnpj(File f, {String? ordemDesejada}) {
  final out = <String, List<_Linha>>{};
  for (final r in lerCsv(f)) {
    final ordem = r['ORDEM_EXERC'] ?? '';
    if (ordemDesejada != null && !ordem.startsWith(ordemDesejada)) continue;
    final conta = CvmAccountLine.doTexto(
      code: r['CD_CONTA'] ?? '',
      label: r['DS_CONTA'] ?? '',
      valor: r['VL_CONTA'] ?? '',
      escala: _escala(r['ESCALA_MOEDA']),
    );
    if (conta == null) continue;
    out.putIfAbsent(r['CNPJ_CIA'] ?? '', () => []).add(
        _Linha(r['CNPJ_CIA'] ?? '', r['DENOM_CIA'] ?? '', ordem, conta));
  }
  return out;
}

List<CvmAccountLine> _paraChart(List<_Linha> l) => [for (final x in l) x.conta];

String _pc(int n, int d) => d == 0 ? '—' : '${(100 * n / d).toStringAsFixed(1)}%';

Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? '.' : args.first;
  File f(String n) => File('$dir/$n');

  // "ÚLTIMO" é o exercício de referência do documento; "PENÚLTIMO" é o
  // comparativo do ano anterior, que já virá no arquivo daquele ano.
  const ultimo = 'Ú';

  final dre = _porCnpj(f('dfp_cia_aberta_DRE_con_2024.csv'), ordemDesejada: ultimo);
  final dreInd = _porCnpj(f('dfp_cia_aberta_DRE_ind_2024.csv'), ordemDesejada: ultimo);
  final bpa = _porCnpj(f('dfp_cia_aberta_BPA_con_2024.csv'), ordemDesejada: ultimo);
  final bpaInd = _porCnpj(f('dfp_cia_aberta_BPA_ind_2024.csv'), ordemDesejada: ultimo);
  final bpp = _porCnpj(f('dfp_cia_aberta_BPP_con_2024.csv'), ordemDesejada: ultimo);
  final bppInd = _porCnpj(f('dfp_cia_aberta_BPP_ind_2024.csv'), ordemDesejada: ultimo);

  final ponte = jsonDecode(
    File('docs/validacao/ponte_cvm.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cnpjs = {
    ...(ponte['ponte'] as Map<String, dynamic>).values.map((e) => e as String),
  };

  stdout.writeln('== Leitor do plano de contas sobre o DFP 2024 real ==');
  stdout.writeln('   ${cnpjs.length} CNPJs do universo\n');

  final porLayout = <CvmLayout, int>{};
  var comLucro = 0, comEbit = 0, comPl = 0, comAtivo = 0, recuouInd = 0;
  var balancoOk = 0, balancoTestado = 0, dreOk = 0, dreTestado = 0;
  final falhas = <String>[];
  final saida = <Map<String, Object?>>[];

  for (final cnpj in cnpjs) {
    // Consolidado, com recuo para individual — a conferência mostrou que
    // Sanepar, Comgás, Coelba e afins só arquivam individual.
    var linhasDre = dre[cnpj];
    var linhasBpa = bpa[cnpj];
    var linhasBpp = bpp[cnpj];
    var origem = 'consolidado';
    if (linhasDre == null || linhasDre.isEmpty) {
      linhasDre = dreInd[cnpj];
      linhasBpa = bpaInd[cnpj];
      linhasBpp = bppInd[cnpj];
      origem = 'individual';
      if (linhasDre != null && linhasDre.isNotEmpty) recuouInd++;
    }
    if (linhasDre == null || linhasDre.isEmpty) continue;

    final chartDre = CvmChart.of(_paraChart(linhasDre));
    final chartBal = CvmChart.of([
      ..._paraChart(linhasBpa ?? const []),
      ..._paraChart(linhasBpp ?? const []),
    ]);

    porLayout[chartDre.layout] = (porLayout[chartDre.layout] ?? 0) + 1;
    final lucro = chartDre.lucroLiquido;
    final ebit = chartDre.ebit;
    final pl = chartBal.patrimonioLiquido;
    final at = chartBal.ativoTotal;
    final pt = chartBal.passivoTotal;
    if (lucro != null) comLucro++;
    if (ebit != null) comEbit++;
    if (pl != null) comPl++;
    if (at != null) comAtivo++;

    // (1) Identidade de balanço.
    // `at.abs() > 1` e não `at != 0`: um ativo total de 1e-14 —
    // resíduo de leitura, não companhia — faria a razão relativa
    // estourar e inventar um balanço que não fecha.
    if (at != null && pt != null && at.abs() > 1) {
      balancoTestado++;
      if (((at - pt).abs() / at.abs()) < 1e-6) {
        balancoOk++;
      } else {
        falhas.add('${linhasDre.first.denom}: ativo $at != passivo $pt');
      }
    }

    // (2) Identidade da DRE.
    final antes = chartDre.resultadoAntesDosTributos;
    final trib = chartDre.tributos;
    if (antes != null && trib != null && lucro != null && lucro.abs() > 1) {
      dreTestado++;
      if (((antes + trib - lucro).abs() / lucro.abs()) < 0.02) dreOk++;
    }

    saida.add({
      'cnpj': cnpj,
      'nome': linhasDre.first.denom,
      'origem': origem,
      'layout': chartDre.layout.name,
      'receita': chartDre.receita,
      'ebit': ebit,
      'lucro': lucro,
      'lpa': chartDre.lucroPorAcao,
      'ativoTotal': at,
      'patrimonioLiquido': pl,
      'naoControladores': chartBal.participacaoNaoControladores,
    });
  }

  final n = saida.length;
  stdout.writeln('  companhias lidas: $n   (recuo para individual: $recuouInd)');
  stdout.writeln('  layouts detectados:');
  for (final e in porLayout.entries) {
    stdout.writeln('    ${e.value.toString().padLeft(4)}  ${e.key.label}');
  }
  stdout.writeln('');
  stdout.writeln('  lucro líquido resolvido : $comLucro / $n  ${_pc(comLucro, n)}');
  stdout.writeln('  patrimônio líquido      : $comPl / $n  ${_pc(comPl, n)}');
  stdout.writeln('  ativo total             : $comAtivo / $n  ${_pc(comAtivo, n)}');
  stdout.writeln('  EBIT (só não financeira): $comEbit / $n  ${_pc(comEbit, n)}');
  stdout.writeln('');
  stdout.writeln('  IDENTIDADE ativo = passivo : $balancoOk / $balancoTestado  '
      '${_pc(balancoOk, balancoTestado)}');
  stdout.writeln('  IDENTIDADE antes+trib=lucro: $dreOk / $dreTestado  '
      '${_pc(dreOk, dreTestado)}');
  if (falhas.isNotEmpty) {
    stdout.writeln('\n  balanços que não fecham:');
    for (final x in falhas.take(10)) {
      stdout.writeln('    $x');
    }
  }

  File('docs/validacao/cvm_leitura.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(saida),
  );
  stdout.writeln('\n  gravado docs/validacao/cvm_leitura.json');
}
