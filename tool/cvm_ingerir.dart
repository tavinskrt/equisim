// Ingestão da CVM: dos CSVs anuais para a série de documentos do motor.
//
// Junta as peças dos itens A1.1 a A1.8:
//
//   A1.1  a ponte ticker -> CNPJ, por `CvmBridge`
//   A1.2  o layout do plano de contas, por `CvmChart`
//   A1.3  consolidado com recuo para individual
//   A1.4  publicidade pela `DT_RECEB`, e a versão mais recente de cada
//   A1.5  fração de tesouraria
//   A1.6  todos os anos, inclusive companhias que já não existem
//   A1.8  o acumulado do ano anterior, para os últimos doze meses
//
// **Dois defeitos da primeira versão, corrigidos aqui** (decisão 72):
//
// 1. **A DRE do ITR traz duas linhas por conta** no 2º e no 3º trimestre: o
//    trimestre isolado (`DT_INI_EXERC` no início do trimestre) e o acumulado
//    do exercício (`DT_INI_EXERC` no início do exercício). A versão anterior
//    filtrava só por `ÚLTIMO`, e o leitor recebia as duas com o mesmo código —
//    a receita do 2T23 da WEG chegava como R$ 15,87 bi **e** R$ 8,17 bi. A
//    seleção agora fica com a de **menor `DT_INI_EXERC`**, que é o acumulado, e
//    que funciona também em exercício que não começa em janeiro.
// 2. **O tipo de documento entra na chave e na saída.** A série anual é a DFP,
//    não "o que termina em dezembro": cinco companhias do universo têm
//    exercício social fora do calendário, e para elas o ITR de dezembro é um
//    acumulado de nove meses.
//
// **A regra de versão é decisão, e está aqui.** A CVM republica documento
// reapresentado com `VERSAO` maior. Esta ingestão adota a **última versão**,
// que é o número correto conhecido hoje — o que injeta conhecimento futuro numa
// avaliação datada. É o item B8 do plano.
//
// Uso:
//   python tool/cvm_baixar.py --de 2010 --ate 2026 --docs DFP,ITR,FCA
//   dart run tool/cvm_ingerir.dart data/cvm
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

// ------------------------------------------------------------------ leitura

/// Lê um CSV da CVM: `latin-1`, separador `;`, aspas respeitadas.
List<Map<String, String>> lerCsv(File f) {
  final linhas =
      const LineSplitter().convert(latin1.decode(f.readAsBytesSync()));
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

String _dia(String? s) => (s == null || s.length < 10) ? '' : s.substring(0, 10);

/// Chave de um documento: companhia, data de referência e tipo.
typedef _Doc = ({String cnpj, String refer, String doc});

/// Metadados de um documento entregue à CVM.
class _Meta {
  final String denom;
  final int versao;
  final String? recebido;
  _Meta(this.denom, this.versao, this.recebido);
}

/// Linhas de uma demonstração, com o início do período das contas de fluxo.
class _Demonstracao {
  final Map<String, ({String ini, CvmAccountLine linha})> porConta = {};

  /// Quantas contas chegaram com mais de uma linha — o trimestre e o
  /// acumulado, na DRE do ITR.
  int duplicadas = 0;

  /// Fica com a linha de **menor** início de período para cada conta — o
  /// acumulado do exercício. Balanço não tem início, e passa direto.
  void acrescentar(String ini, CvmAccountLine linha) {
    final atual = porConta[linha.code];
    if (atual != null) duplicadas++;
    if (atual == null || (ini.isNotEmpty && ini.compareTo(atual.ini) < 0)) {
      porConta[linha.code] = (ini: ini, linha: linha);
    }
  }

  List<CvmAccountLine> get linhas =>
      [for (final v in porConta.values) v.linha];

  /// Início do período acumulado, pela receita ou pelo lucro.
  String? get inicio {
    for (final c in const ['3.01', '3.11', '3.09', '3.13', '6.01']) {
      final v = porConta[c];
      if (v != null && v.ini.isNotEmpty) return v.ini;
    }
    return null;
  }
}

void main(List<String> args) {
  final dir = args.isEmpty ? 'data/cvm' : args.first;
  final d = Directory(dir);
  if (!d.existsSync()) {
    stderr.writeln('$dir não existe. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --de 2010 --ate 2026');
    exit(2);
  }
  final porNome = <String, File>{
    for (final f in d.listSync().whereType<File>())
      f.path.replaceAll('\\', '/').split('/').last: f,
  };

  final anos = <int>{};
  for (final n in porNome.keys) {
    final m = RegExp(r'_(\d{4})\.csv$').firstMatch(n);
    if (m != null) anos.add(int.parse(m.group(1)!));
  }
  final anosOrdenados = anos.toList()..sort();
  stdout.writeln('== Ingestão da CVM ==');
  stdout.writeln('  anos encontrados: ${anosOrdenados.first}–'
      '${anosOrdenados.last}\n');

  // --- Metadados: recebimento e versão vigente -----------------------------
  final meta = <_Doc, _Meta>{};
  for (final ano in anosOrdenados) {
    for (final doc in ['dfp', 'itr']) {
      final f = porNome['${doc}_cia_aberta_$ano.csv'];
      if (f == null) continue;
      for (final r in lerCsv(f)) {
        final k = (
          cnpj: r['CNPJ_CIA'] ?? '',
          refer: _dia(r['DT_REFER']),
          doc: doc.toUpperCase(),
        );
        final v = int.tryParse(r['VERSAO'] ?? '') ?? 1;
        final atual = meta[k];
        if (atual == null || v > atual.versao) {
          meta[k] = _Meta(r['DENOM_CIA'] ?? '', v, _dia(r['DT_RECEB']));
        }
      }
    }
  }
  final porTipo = <String, int>{};
  for (final k in meta.keys) {
    porTipo[k.doc] = (porTipo[k.doc] ?? 0) + 1;
  }
  stdout.writeln('  documentos: ${meta.length} $porTipo');
  final reapresentados = meta.values.where((m) => m.versao > 1).length;
  stdout.writeln('  reapresentados (VERSAO > 1): $reapresentados '
      '(${(100 * reapresentados / meta.length).toStringAsFixed(1)}%)');

  // --- Composição de capital -----------------------------------------------
  final capital = <_Doc, ({double integralizadas, double tesouraria})>{};
  for (final ano in anosOrdenados) {
    for (final doc in ['dfp', 'itr']) {
      final f = porNome['${doc}_cia_aberta_composicao_capital_$ano.csv'];
      if (f == null) continue;
      for (final r in lerCsv(f)) {
        final tot = double.tryParse(r['QT_ACAO_TOTAL_CAP_INTEGR'] ?? '');
        final tes = double.tryParse(r['QT_ACAO_TOTAL_TESOURO'] ?? '') ?? 0;
        if (tot == null || tot <= 0) continue;
        capital[(
          cnpj: r['CNPJ_CIA'] ?? '',
          refer: _dia(r['DT_REFER']),
          doc: doc.toUpperCase(),
        )] = (integralizadas: tot, tesouraria: tes);
      }
    }
  }

  // --- Demonstrações --------------------------------------------------------
  /// Lê uma demonstração de todos os anos. [ordem] é `Ú` (exercício do
  /// documento) ou `P` (o comparativo que o acompanha).
  Map<_Doc, _Demonstracao> carregar(String sufixo, String ordem) {
    final out = <_Doc, _Demonstracao>{};
    for (final ano in anosOrdenados) {
      for (final doc in ['dfp', 'itr']) {
        final f = porNome['${doc}_cia_aberta_${sufixo}_$ano.csv'];
        if (f == null) continue;
        for (final r in lerCsv(f)) {
          if (!(r['ORDEM_EXERC'] ?? '').startsWith(ordem)) continue;
          final linha = CvmAccountLine.doTexto(
            code: r['CD_CONTA'] ?? '',
            label: r['DS_CONTA'] ?? '',
            valor: r['VL_CONTA'] ?? '',
            escala: _escala(r['ESCALA_MOEDA']),
          );
          if (linha == null) continue;
          out
              .putIfAbsent(
                (
                  cnpj: r['CNPJ_CIA'] ?? '',
                  refer: _dia(r['DT_REFER']),
                  doc: doc.toUpperCase(),
                ),
                _Demonstracao.new,
              )
              .acrescentar(_dia(r['DT_INI_EXERC']), linha);
        }
      }
    }
    return out;
  }

  final dre = {'con': carregar('DRE_con', 'Ú'), 'ind': carregar('DRE_ind', 'Ú')};
  final dreAnt = {
    'con': carregar('DRE_con', 'P'),
    'ind': carregar('DRE_ind', 'P'),
  };
  final dfc = {
    'con': carregar('DFC_MI_con', 'Ú'),
    'ind': carregar('DFC_MI_ind', 'Ú'),
  };
  final dfcAnt = {
    'con': carregar('DFC_MI_con', 'P'),
    'ind': carregar('DFC_MI_ind', 'P'),
  };
  final bpa = {'con': carregar('BPA_con', 'Ú'), 'ind': carregar('BPA_ind', 'Ú')};
  final bpp = {'con': carregar('BPP_con', 'Ú'), 'ind': carregar('BPP_ind', 'Ú')};

  // --- Ponte ---------------------------------------------------------------
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

  Map<String, double?> fluxos(CvmChart dreC, CvmChart dfcC) => {
        'receita': dreC.receita,
        'ebit': dreC.ebit,
        'resultadoAntesDosTributos': dreC.resultadoAntesDosTributos,
        'tributos': dreC.tributos,
        'lucroLiquido': dreC.lucroLiquido,
        'caixaOperacional': dfcC.caixaOperacional,
        'caixaDeInvestimento': dfcC.caixaDeInvestimento,
        'capex': dfcC.capex,
        'depreciacaoEAmortizacao': dfcC.depreciacaoEAmortizacao,
      };

  // --- Montagem ------------------------------------------------------------
  final exercicios = <Map<String, Object?>>[];
  var comRecuo = 0, semDre = 0, balancoOk = 0, balancoN = 0;
  var duplicadasResolvidas = 0;
  final layouts = <String, int>{};

  for (final k in meta.keys) {
    final m = meta[k]!;
    var origem = 'con';
    if (dre['con']![k] == null) {
      origem = 'ind';
      if (dre['ind']![k] != null) comRecuo++;
    }
    final demDre = dre[origem]![k];
    if (demDre == null) {
      semDre++;
      continue;
    }

    final chartDre = CvmChart.of(demDre.linhas);
    final chartDfc = CvmChart.of(dfc[origem]![k]?.linhas ?? const []);
    final chartBal = CvmChart.of([
      ...?bpa[origem]![k]?.linhas,
      ...?bpp[origem]![k]?.linhas,
    ]);
    layouts[chartDre.layout.name] = (layouts[chartDre.layout.name] ?? 0) + 1;

    final at = chartBal.ativoTotal;
    final pt = chartBal.passivoTotal;
    if (at != null && pt != null && at.abs() > 1) {
      balancoN++;
      if (((at - pt).abs() / at.abs()) < 1e-6) balancoOk++;
    }

    // Acumulado do mesmo período no exercício anterior — só o ITR precisa,
    // para os últimos doze meses. A DFP é o ano cheio por si.
    Map<String, Object?>? anterior;
    if (k.doc == 'ITR') {
      final dAnt = dreAnt[origem]![k];
      if (dAnt != null) {
        final fAnt = fluxos(
          CvmChart.of(dAnt.linhas),
          CvmChart.of(dfcAnt[origem]![k]?.linhas ?? const []),
        );
        anterior = {'inicioDoPeriodo': dAnt.inicio, ...fAnt};
      }
      if (demDre.duplicadas > 0) duplicadasResolvidas++;
    }

    final cap = capital[k];
    exercicios.add({
      'cnpj': k.cnpj,
      'nome': m.denom,
      'tickers': porCnpj[k.cnpj] ?? const <String>[],
      'documento': k.doc,
      'inicioDoPeriodo': demDre.inicio,
      'fimDoExercicio': k.refer,
      'recebidoEm': m.recebido,
      'versao': m.versao,
      'origem': origem == 'con' ? 'consolidado' : 'individual',
      'layout': chartDre.layout.name,
      ...fluxos(chartDre, chartDfc),
      'lucroPorAcao': chartDre.lucroPorAcao,
      'ativoTotal': at,
      'ativoCirculante': chartBal.ativoCirculante,
      'passivoCirculante': chartBal.passivoCirculante,
      'patrimonioLiquido': chartBal.patrimonioLiquido,
      'naoControladores': chartBal.participacaoNaoControladores,
      'caixa': chartBal.caixa,
      'aplicacoesFinanceiras': chartBal.aplicacoesFinanceiras,
      'imobilizado': chartBal.imobilizado,
      'intangivel': chartBal.intangivel,
      'dividaDeCurtoPrazo': chartBal.dividaDeCurtoPrazo,
      'dividaDeLongoPrazo': chartBal.dividaDeLongoPrazo,
      'acoesIntegralizadas': cap?.integralizadas,
      'acoesEmTesouraria': cap?.tesouraria,
      'anterior': anterior,
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
  stdout.writeln('');
  stdout.writeln('  documentos montados : ${exercicios.length}');
  stdout.writeln('    DFP: ${exercicios.where((e) => e['documento'] == 'DFP').length}'
      '   ITR: ${exercicios.where((e) => e['documento'] == 'ITR').length}');
  stdout.writeln('  companhias distintas: '
      '${exercicios.map((e) => e['cnpj']).toSet().length}');
  stdout.writeln('  com ticker no universo de hoje: $comTicker');
  stdout.writeln('  fora do universo de hoje: ${exercicios.length - comTicker}');
  stdout.writeln('  recuo para individual: $comRecuo');
  stdout.writeln('  sem DRE: $semDre');
  stdout.writeln('  ITR em que a DRE trazia trimestre E acumulado: '
      '$duplicadasResolvidas');
  stdout.writeln('  layouts: $layouts');
  stdout.writeln('  IDENTIDADE ativo = passivo: $balancoOk / $balancoN');

  final saida = File('data/cvm_exercicios.json');
  saida.writeAsStringSync(jsonEncode(exercicios));
  stdout.writeln('\n  gravado ${saida.path} '
      '(${(saida.lengthSync() / 1e6).toStringAsFixed(1)} MB)');
}
