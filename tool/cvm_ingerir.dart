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
// **A regra de versão é decisão, e está aqui** (item B8). A CVM republica
// documento reapresentado com `VERSAO` maior, e os CSVs anuais trazem só a
// última — o número correto conhecido hoje, que numa avaliação datada é
// conhecimento futuro. Por isso a ingestão grava **dois arquivos**:
//
//   data/cvm_exercicios.json  a última versão de cada documento, como sempre;
//                             é o que o pacote do aplicativo e as ferramentas
//                             de conferência leem
//   data/cvm_versoes.json     as versões anteriores que estavam vigentes em
//                             alguma coorte, baixadas do RAD por
//                             `tool/cvm_versoes_baixar.py`, cada uma com a data
//                             de recebimento **dela**
//
// O backtest lê os dois, e `CvmSeries.vigentes` escolhe, em cada coorte, a
// versão que era pública naquela data.
//
// Uso:
//   python tool/cvm_baixar.py --de 2010 --ate 2026 --docs DFP,ITR,FCA
//   python tool/cvm_versoes_baixar.py            # as versões antigas
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

/// Chave de uma versão de documento.
typedef _Versao = ({String cnpj, String refer, String doc, int versao});

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

  // --- Metadados: recebimento de cada versão, e a vigente -----------------
  final meta = <_Doc, _Meta>{};
  final porVersao = <_Versao, _Meta>{};
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
        final m = _Meta(r['DENOM_CIA'] ?? '', v, _dia(r['DT_RECEB']));
        // A mesma versão aparece, às vezes, no índice de dois anos com datas
        // diferentes; vale a primeira lida, que é a regra de antes do B8.
        porVersao.putIfAbsent(
            (cnpj: k.cnpj, refer: k.refer, doc: k.doc, versao: v), () => m);
        final atual = meta[k];
        if (atual == null || v > atual.versao) meta[k] = m;
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

  // As versões antigas, no layout dos anuais, quando foram baixadas.
  final dirVersoes = Directory('$dir/versoes');
  final porNomeVersoes = <String, File>{
    if (dirVersoes.existsSync())
      for (final f in dirVersoes.listSync().whereType<File>())
        f.path.replaceAll('\\', '/').split('/').last: f,
  };

  /// Arquivos de um demonstrativo: os anuais, ou o das versões antigas.
  Iterable<(String, File)> arquivos(String sufixo,
      {required bool antigas}) sync* {
    for (final doc in ['dfp', 'itr']) {
      if (antigas) {
        final f = porNomeVersoes['${doc}_cia_aberta_${sufixo}_versoes.csv'];
        if (f != null) yield (doc, f);
      } else {
        for (final ano in anosOrdenados) {
          final f = porNome['${doc}_cia_aberta_${sufixo}_$ano.csv'];
          if (f != null) yield (doc, f);
        }
      }
    }
  }

  _Versao chave(Map<String, String> r, String doc) => (
        cnpj: r['CNPJ_CIA'] ?? '',
        refer: _dia(r['DT_REFER']),
        doc: doc.toUpperCase(),
        versao: int.tryParse(r['VERSAO'] ?? '') ?? 1,
      );

  // --- Composição de capital -----------------------------------------------
  Map<_Versao, ({double integralizadas, double tesouraria})> carregarCapital(
      {required bool antigas}) {
    final out = <_Versao, ({double integralizadas, double tesouraria})>{};
    for (final (doc, f) in arquivos('composicao_capital', antigas: antigas)) {
      for (final r in lerCsv(f)) {
        final tot = double.tryParse(r['QT_ACAO_TOTAL_CAP_INTEGR'] ?? '');
        final tes = double.tryParse(r['QT_ACAO_TOTAL_TESOURO'] ?? '') ?? 0;
        if (tot == null || tot <= 0) continue;
        out[chave(r, doc)] = (integralizadas: tot, tesouraria: tes);
      }
    }
    return out;
  }

  // --- Demonstrações --------------------------------------------------------
  /// Lê uma demonstração de todos os anos. [ordem] é `Ú` (exercício do
  /// documento) ou `P` (o comparativo que o acompanha).
  Map<_Versao, _Demonstracao> carregar(String sufixo, String ordem,
      {required bool antigas}) {
    final out = <_Versao, _Demonstracao>{};
    for (final (doc, f) in arquivos(sufixo, antigas: antigas)) {
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
            .putIfAbsent(chave(r, doc), _Demonstracao.new)
            .acrescentar(_dia(r['DT_INI_EXERC']), linha);
      }
    }
    return out;
  }

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
  var comRecuo = 0, semDre = 0, balancoOk = 0, balancoN = 0;
  var duplicadasResolvidas = 0, semRecebimento = 0;
  final layouts = <String, int>{};

  /// Monta os exercícios de um conjunto de CSVs — os anuais ou os das versões
  /// antigas. A data de recebimento é a **da versão** que as contas trazem.
  List<Map<String, Object?>> montar({required bool antigas}) {
    final dre = {
      'con': carregar('DRE_con', 'Ú', antigas: antigas),
      'ind': carregar('DRE_ind', 'Ú', antigas: antigas),
    };
    final dreAnt = {
      'con': carregar('DRE_con', 'P', antigas: antigas),
      'ind': carregar('DRE_ind', 'P', antigas: antigas),
    };
    final dfc = {
      'con': carregar('DFC_MI_con', 'Ú', antigas: antigas),
      'ind': carregar('DFC_MI_ind', 'Ú', antigas: antigas),
    };
    final dfcAnt = {
      'con': carregar('DFC_MI_con', 'P', antigas: antigas),
      'ind': carregar('DFC_MI_ind', 'P', antigas: antigas),
    };
    final bpa = {
      'con': carregar('BPA_con', 'Ú', antigas: antigas),
      'ind': carregar('BPA_ind', 'Ú', antigas: antigas),
    };
    final bpp = {
      'con': carregar('BPP_con', 'Ú', antigas: antigas),
      'ind': carregar('BPP_ind', 'Ú', antigas: antigas),
    };
    final capital = carregarCapital(antigas: antigas);

    final exercicios = <Map<String, Object?>>[];
    final chaves = {...dre['con']!.keys, ...dre['ind']!.keys};
    if (!antigas) {
      final comDre = {
        for (final k in chaves) (cnpj: k.cnpj, refer: k.refer, doc: k.doc),
      };
      semDre = meta.keys.where((k) => !comDre.contains(k)).length;
    }
    for (final k in chaves) {
      // A versão das contas dá a data de recebimento. Nos anuais, a versão que
      // o CSV traz é a última, e o índice a confirma; sem ela no índice, fica a
      // vigente, como antes.
      final m = porVersao[k] ??
          (antigas ? null : meta[(cnpj: k.cnpj, refer: k.refer, doc: k.doc)]);
      if (m == null) {
        semRecebimento++;
        continue;
      }
      var origem = 'con';
      if (dre['con']![k] == null) {
        origem = 'ind';
        if (dre['ind']![k] != null) comRecuo++;
      }
      final demDre = dre[origem]![k];
      if (demDre == null) continue;

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
      if (c != 0) return c;
      final f = (a['fimDoExercicio']! as String)
          .compareTo(b['fimDoExercicio']! as String);
      return f != 0 ? f : (a['versao']! as int).compareTo(b['versao']! as int);
    });
    return exercicios;
  }

  // Nos anuais, **uma entrada por documento, a de maior versão**: um
  // documento raro vem com duas versões em arquivos de anos diferentes (a DFP
  // de 2021 da INTER & CO), e a versão menor não é a vigente de hoje.
  final exercicios = () {
    final porDoc = <String, Map<String, Object?>>{};
    for (final e in montar(antigas: false)) {
      final k = '${e['cnpj']}|${e['fimDoExercicio']}|${e['documento']}';
      final atual = porDoc[k];
      if (atual == null || (e['versao']! as int) > (atual['versao']! as int)) {
        porDoc[k] = e;
      }
    }
    return [for (final e in porDoc.values) e];
  }();
  // O recuo, as duplicadas e a identidade descrevem a base vigente; as
  // versões antigas são contadas à parte.
  final (recuo0, dup0, balOk0, balN0) =
      (comRecuo, duplicadasResolvidas, balancoOk, balancoN);
  final antigas = porNomeVersoes.isEmpty
      ? const <Map<String, Object?>>[]
      : montar(antigas: true);
  final balancoAntigasOk = balancoOk - balOk0;
  final balancoAntigasN = balancoN - balN0;
  comRecuo = recuo0;
  duplicadasResolvidas = dup0;
  balancoOk = balOk0;
  balancoN = balN0;

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

  // --- Versões antigas (item B8) --------------------------------------------
  final saidaVersoes = File('data/cvm_versoes.json');
  if (antigas.isEmpty) {
    if (saidaVersoes.existsSync()) saidaVersoes.deleteSync();
    stdout.writeln('  sem versões antigas em $dir/versoes — rode '
        'tool/cvm_versoes_baixar.py para o point-in-time por versão');
  } else {
    saidaVersoes.writeAsStringSync(jsonEncode(antigas));
    stdout.writeln('  versões antigas montadas: ${antigas.length}   '
        'IDENTIDADE ativo = passivo: $balancoAntigasOk / $balancoAntigasN');
    stdout.writeln('  gravado ${saidaVersoes.path} '
        '(${(saidaVersoes.lengthSync() / 1e6).toStringAsFixed(1)} MB)');
  }
  if (semRecebimento > 0) {
    stdout.writeln('  versões sem data de recebimento no índice, descartadas: '
        '$semRecebimento');
  }
}
