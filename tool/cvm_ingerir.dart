// Ingestão da CVM: dos CSVs anuais para a série de exercícios do motor.
//
// Junta as quatro peças que os itens A1.1 a A1.6 produziram:
//
//   A1.1  a ponte ticker -> CNPJ, por `CvmBridge`
//   A1.2  o layout do plano de contas, por `CvmChart`
//   A1.3  consolidado com recuo para individual
//   A1.4  publicidade pela `DT_RECEB`, e a versão mais recente de cada
//   A1.5  contagem de papéis líquida de tesouraria
//   A1.6  todos os anos, inclusive companhias que já não existem
//
// **A regra de versão é decisão, e está aqui.** A CVM republica documento
// reapresentado com `VERSAO` maior — 24,8% dos anuais têm mais de uma. Esta
// ingestão adota a **última versão**, que é o número correto conhecido hoje.
// Isso injeta conhecimento futuro numa avaliação datada, e é por isso que a
// data de recebimento de **cada versão** também é gravada: uma carga
// *point-in-time* estrita usaria a versão vigente na data da coorte, e o dado
// para fazê-lo fica disponível.
//
// Uso:
//   python tool/cvm_baixar.py --de 2010 --ate 2025
//   dart run tool/cvm_ingerir.dart data/cvm
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

// ------------------------------------------------------------------ leitura

/// Lê um CSV da CVM: `latin-1`, separador `;`, aspas respeitadas.
///
/// Divisão ingênua por `;` não serve: `DENOM_CIA` traz razão social com
/// pontuação, e o arquivo cita esses campos.
List<Map<String, String>> lerCsv(File f) {
  final linhas = const LineSplitter().convert(latin1.decode(f.readAsBytesSync()));
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

List<String> _campos(String l) {
  final out = <String>[];
  final atual = StringBuffer();
  var aspas = false;
  for (var i = 0; i < l.length; i++) {
    final ch = l[i];
    if (ch == '"') {
      aspas = !aspas;
    } else if (ch == ';' && !aspas) {
      out.add(atual.toString());
      atual.clear();
    } else {
      atual.write(ch);
    }
  }
  out.add(atual.toString());
  return out;
}

int _escala(String? e) => (e ?? '').toUpperCase() == 'MIL' ? 1000 : 1;

DateTime? _data(String? s) {
  if (s == null || s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

/// Chave de um documento: companhia mais data de referência.
typedef _Doc = ({String cnpj, String refer});

// ------------------------------------------------------------------ modelo

/// Metadados de um documento entregue à CVM.
class _Meta {
  final String cnpj;
  final String denom;
  final String refer;
  final int versao;
  final DateTime? recebido;
  _Meta(this.cnpj, this.denom, this.refer, this.versao, this.recebido);
}

void main(List<String> args) {
  final dir = args.isEmpty ? 'data/cvm' : args.first;
  final d = Directory(dir);
  if (!d.existsSync()) {
    stderr.writeln('$dir não existe. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --de 2010 --ate 2025');
    exit(2);
  }
  final arquivos = d.listSync().whereType<File>().toList();
  File? achar(String padrao) {
    for (final f in arquivos) {
      if (f.path.replaceAll('\\', '/').split('/').last == padrao) return f;
    }
    return null;
  }

  final anos = <int>{};
  for (final f in arquivos) {
    final m = RegExp(r'_(\d{4})\.csv$').firstMatch(f.path);
    if (m != null) anos.add(int.parse(m.group(1)!));
  }
  final anosOrdenados = anos.toList()..sort();
  stdout.writeln('== Ingestão da CVM ==');
  stdout.writeln('  anos encontrados: ${anosOrdenados.join(", ")}\n');

  // --- A1.4: metadados, para data de recebimento e versão vigente ---------
  final meta = <_Doc, _Meta>{};
  for (final ano in anosOrdenados) {
    for (final doc in ['dfp', 'itr']) {
      final f = achar('${doc}_cia_aberta_$ano.csv');
      if (f == null) continue;
      for (final r in lerCsv(f)) {
        final cnpj = r['CNPJ_CIA'] ?? '';
        final refer = (r['DT_REFER'] ?? '').substring(0, 10);
        final v = int.tryParse(r['VERSAO'] ?? '') ?? 1;
        final k = (cnpj: cnpj, refer: refer);
        final atual = meta[k];
        if (atual == null || v > atual.versao) {
          meta[k] = _Meta(cnpj, r['DENOM_CIA'] ?? '', refer, v,
              _data(r['DT_RECEB']));
        }
      }
    }
  }
  stdout.writeln('  documentos (companhia × data de referência): ${meta.length}');
  final reapresentados = meta.values.where((m) => m.versao > 1).length;
  stdout.writeln('  reapresentados (VERSAO > 1): $reapresentados '
      '(${(100 * reapresentados / meta.length).toStringAsFixed(1)}%)');

  // --- A1.5: composição de capital, líquida de tesouraria -----------------
  final capital = <_Doc, ({double integralizadas, double tesouraria})>{};
  for (final ano in anosOrdenados) {
    for (final doc in ['dfp', 'itr']) {
      final f = achar('${doc}_cia_aberta_composicao_capital_$ano.csv');
      if (f == null) continue;
      for (final r in lerCsv(f)) {
        final k = (
          cnpj: r['CNPJ_CIA'] ?? '',
          refer: (r['DT_REFER'] ?? '').substring(0, 10)
        );
        final tot = double.tryParse(r['QT_ACAO_TOTAL_CAP_INTEGR'] ?? '');
        final tes = double.tryParse(r['QT_ACAO_TOTAL_TESOURO'] ?? '') ?? 0;
        if (tot == null || tot <= 0) continue;
        capital[k] = (integralizadas: tot, tesouraria: tes);
      }
    }
  }
  stdout.writeln('  composições de capital: ${capital.length}');

  // --- A1.2 + A1.3: as demonstrações, consolidado com recuo ---------------
  /// Linhas de cada documento, por (cnpj, refer), já na escala e só do
  /// exercício de referência.
  Map<_Doc, List<CvmAccountLine>> carregar(String sufixo) {
    final out = <_Doc, List<CvmAccountLine>>{};
    for (final ano in anosOrdenados) {
      for (final doc in ['dfp', 'itr']) {
        final f = achar('${doc}_cia_aberta_${sufixo}_$ano.csv');
        if (f == null) continue;
        for (final r in lerCsv(f)) {
          // "ÚLTIMO" é o exercício do documento; "PENÚLTIMO" é o comparativo,
          // que já vem no arquivo do ano anterior e duplicaria a série.
          if (!(r['ORDEM_EXERC'] ?? '').startsWith('Ú')) continue;
          // Do texto direto para centavos inteiros: converter para `double` e
          // de volta presumiria que o `double` está limpo, e a origem é texto.
          final linha = CvmAccountLine.doTexto(
            code: r['CD_CONTA'] ?? '',
            label: r['DS_CONTA'] ?? '',
            valor: r['VL_CONTA'] ?? '',
            escala: _escala(r['ESCALA_MOEDA']),
          );
          if (linha == null) continue;
          final k = (
            cnpj: r['CNPJ_CIA'] ?? '',
            refer: (r['DT_REFER'] ?? '').substring(0, 10)
          );
          out.putIfAbsent(k, () => []).add(linha);
        }
      }
    }
    return out;
  }

  final dreCon = carregar('DRE_con');
  final dreInd = carregar('DRE_ind');
  final bpaCon = carregar('BPA_con');
  final bpaInd = carregar('BPA_ind');
  final bppCon = carregar('BPP_con');
  final bppInd = carregar('BPP_ind');
  final dfcCon = carregar('DFC_MI_con');
  final dfcInd = carregar('DFC_MI_ind');

  // --- A1.1: a ponte, do arquivo que `cvm_ponte.dart` produziu ------------
  final pontePath = File('docs/validacao/ponte_cvm.json');
  if (!pontePath.existsSync()) {
    stderr.writeln('Rode antes: dart run tool/cvm_ponte.dart $dir');
    exit(2);
  }
  final ponte = ((jsonDecode(pontePath.readAsStringSync())
      as Map<String, dynamic>)['ponte'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  final porCnpj = <String, List<String>>{};
  for (final e in ponte.entries) {
    porCnpj.putIfAbsent(e.value, () => []).add(e.key);
  }

  // --- Montagem ------------------------------------------------------------
  final exercicios = <Map<String, Object?>>[];
  var comRecuo = 0, semDre = 0, comTesouraria = 0, balancoOk = 0, balancoN = 0;
  final layouts = <String, int>{};

  for (final k in meta.keys) {
    final m = meta[k]!;
    var dre = dreCon[k], bpa = bpaCon[k], bpp = bppCon[k], dfc = dfcCon[k];
    var origem = 'consolidado';
    if (dre == null || dre.isEmpty) {
      dre = dreInd[k];
      bpa = bpaInd[k];
      bpp = bppInd[k];
      dfc = dfcInd[k];
      origem = 'individual';
      if (dre != null && dre.isNotEmpty) comRecuo++;
    }
    if (dre == null || dre.isEmpty) {
      semDre++;
      continue;
    }

    final chartDre = CvmChart.of(dre);
    final chartBal = CvmChart.of([...?bpa, ...?bpp]);
    final chartDfc = CvmChart.of(dfc ?? const []);
    layouts[chartDre.layout.name] = (layouts[chartDre.layout.name] ?? 0) + 1;

    final cap = capital[k];
    final integralizadas = cap?.integralizadas;
    final tesouraria = cap?.tesouraria;
    if (tesouraria != null && tesouraria > 0) comTesouraria++;

    final at = chartBal.ativoTotal;
    final pt = chartBal.passivoTotal;
    // `at.abs() > 1` e não `at != 0`: um ativo total de 1e-14 —
    // resíduo de leitura, não companhia — faria a razão relativa
    // estourar e inventar um balanço que não fecha.
    if (at != null && pt != null && at.abs() > 1) {
      balancoN++;
      if (((at - pt).abs() / at.abs()) < 1e-6) balancoOk++;
    }

    exercicios.add({
      'cnpj': m.cnpj,
      'nome': m.denom,
      'tickers': porCnpj[m.cnpj] ?? const <String>[],
      'fimDoExercicio': m.refer,
      'recebidoEm': m.recebido?.toIso8601String().substring(0, 10),
      'versao': m.versao,
      'origem': origem,
      'layout': chartDre.layout.name,
      'receita': chartDre.receita,
      'ebit': chartDre.ebit,
      'resultadoAntesDosTributos': chartDre.resultadoAntesDosTributos,
      'tributos': chartDre.tributos,
      'lucroLiquido': chartDre.lucroLiquido,
      'lucroPorAcao': chartDre.lucroPorAcao,
      'ativoTotal': at,
      'ativoCirculante': chartBal.ativoCirculante,
      'passivoCirculante': chartBal.passivoCirculante,
      'patrimonioLiquido': chartBal.patrimonioLiquido,
      'naoControladores': chartBal.participacaoNaoControladores,
      'caixaOperacional': chartDfc.caixaOperacional,
      'caixaDeInvestimento': chartDfc.caixaDeInvestimento,
      'capex': chartDfc.capex,
      'acoesIntegralizadas': integralizadas,
      'acoesEmTesouraria': tesouraria,
      'acoesComDireitoAFluxo': integralizadas == null
          ? null
          : (tesouraria != null && tesouraria > 0 &&
                  tesouraria < integralizadas
              ? integralizadas - tesouraria
              : integralizadas),
    });
  }

  exercicios.sort((a, b) {
    final c = (a['cnpj']! as String).compareTo(b['cnpj']! as String);
    return c != 0
        ? c
        : (a['fimDoExercicio']! as String)
            .compareTo(b['fimDoExercicio']! as String);
  });

  final comTicker =
      exercicios.where((e) => (e['tickers']! as List).isNotEmpty).length;
  final companhias = exercicios.map((e) => e['cnpj']).toSet().length;

  stdout.writeln('');
  stdout.writeln('  exercícios montados : ${exercicios.length}');
  stdout.writeln('  companhias distintas: $companhias');
  stdout.writeln('  com ticker no universo de hoje: $comTicker '
      '(${(100 * comTicker / exercicios.length).toStringAsFixed(1)}%)');
  stdout.writeln('  DELISTADAS ou fora do universo: '
      '${exercicios.length - comTicker} — é o que remove o viés de '
      'sobrevivência');
  stdout.writeln('  recuo para individual: $comRecuo');
  stdout.writeln('  sem DRE em nenhuma versão: $semDre');
  stdout.writeln('  com ação em tesouraria: $comTesouraria');
  stdout.writeln('  layouts: $layouts');
  stdout.writeln('  IDENTIDADE ativo = passivo: $balancoOk / $balancoN'
      '${balancoN == 0 ? "" : "  ${(100 * balancoOk / balancoN).toStringAsFixed(2)}%"}');

  final saida = File('data/cvm_exercicios.json');
  saida.writeAsStringSync(jsonEncode(exercicios));
  stdout.writeln('\n  gravado ${saida.path} '
      '(${(saida.lengthSync() / 1e6).toStringAsFixed(1)} MB)');
}
