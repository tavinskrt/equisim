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
// O backtest lê os dois, e `CvmSeries.inForceAt` escolhe, em cada coorte, a
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
List<Map<String, String>> readCsv(File f) {
  final rows =
      const LineSplitter().convert(latin1.decode(f.readAsBytesSync()));
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

List<String> _fields(String l) {
  final out = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (var i = 0; i < l.length; i++) {
    final ch = l[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ';' && !quoted) {
      out.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  out.add(current.toString());
  return out;
}

int _scale(String? e) => (e ?? '').toUpperCase() == 'MIL' ? 1000 : 1;

String _day(String? s) => (s == null || s.length < 10) ? '' : s.substring(0, 10);

/// Chave de um documento: companhia, data de referência e tipo.
typedef _Doc = ({String cnpj, String refer, String doc});

/// Chave de uma versão de documento.
typedef _Version = ({String cnpj, String refer, String doc, int version});

/// Metadados de um documento entregue à CVM.
class _Meta {
  final String denom;
  final int version;
  final String? received;
  _Meta(this.denom, this.version, this.received);
}

/// Linhas de uma demonstração, com o início do período das contas de fluxo.
class _Statement {
  final Map<String, ({String ini, CvmAccountLine row})> byAccount = {};

  /// Quantas contas chegaram com mais de uma linha — o trimestre e o
  /// acumulado, na DRE do ITR.
  int duplicates = 0;

  /// Fica com a linha de **menor** início de período para cada conta — o
  /// acumulado do exercício. Balanço não tem início, e passa direto.
  void append(String ini, CvmAccountLine row) {
    final current = byAccount[row.code];
    if (current != null) duplicates++;
    if (current == null || (ini.isNotEmpty && ini.compareTo(current.ini) < 0)) {
      byAccount[row.code] = (ini: ini, row: row);
    }
  }

  List<CvmAccountLine> get rows =>
      [for (final v in byAccount.values) v.row];

  /// Início do período acumulado, pela receita ou pelo lucro.
  String? get start {
    for (final c in const ['3.01', '3.11', '3.09', '3.13', '6.01']) {
      final v = byAccount[c];
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
  final byName = <String, File>{
    for (final f in d.listSync().whereType<File>())
      f.path.replaceAll('\\', '/').split('/').last: f,
  };

  final years = <int>{};
  for (final n in byName.keys) {
    final m = RegExp(r'_(\d{4})\.csv$').firstMatch(n);
    if (m != null) years.add(int.parse(m.group(1)!));
  }
  final sortedYears = years.toList()..sort();
  stdout.writeln('== Ingestão da CVM ==');
  stdout.writeln('  anos encontrados: ${sortedYears.first}–'
      '${sortedYears.last}\n');

  // --- Metadados: recebimento de cada versão, e a vigente -----------------
  final meta = <_Doc, _Meta>{};
  final byVersion = <_Version, _Meta>{};
  for (final year in sortedYears) {
    for (final doc in ['dfp', 'itr']) {
      final f = byName['${doc}_cia_aberta_$year.csv'];
      if (f == null) continue;
      for (final r in readCsv(f)) {
        final k = (
          cnpj: r['CNPJ_CIA'] ?? '',
          refer: _day(r['DT_REFER']),
          doc: doc.toUpperCase(),
        );
        final v = int.tryParse(r['VERSAO'] ?? '') ?? 1;
        final m = _Meta(r['DENOM_CIA'] ?? '', v, _day(r['DT_RECEB']));
        // A mesma versão aparece, às vezes, no índice de dois anos com datas
        // diferentes; vale a primeira lida, que é a regra de antes do B8.
        byVersion.putIfAbsent(
            (cnpj: k.cnpj, refer: k.refer, doc: k.doc, version: v), () => m);
        final current = meta[k];
        if (current == null || v > current.version) meta[k] = m;
      }
    }
  }
  final byKind = <String, int>{};
  for (final k in meta.keys) {
    byKind[k.doc] = (byKind[k.doc] ?? 0) + 1;
  }
  stdout.writeln('  documentos: ${meta.length} $byKind');
  final restated = meta.values.where((m) => m.version > 1).length;
  stdout.writeln('  reapresentados (VERSAO > 1): $restated '
      '(${(100 * restated / meta.length).toStringAsFixed(1)}%)');

  // As versões antigas, no layout dos anuais, quando foram baixadas.
  final versionsDir = Directory('$dir/versoes');
  final versionsByName = <String, File>{
    if (versionsDir.existsSync())
      for (final f in versionsDir.listSync().whereType<File>())
        f.path.replaceAll('\\', '/').split('/').last: f,
  };

  /// Arquivos de um demonstrativo: os anuais, ou o das versões antigas.
  Iterable<(String, File)> files(String suffix,
      {required bool oldVersions}) sync* {
    for (final doc in ['dfp', 'itr']) {
      if (oldVersions) {
        final f = versionsByName['${doc}_cia_aberta_${suffix}_versoes.csv'];
        if (f != null) yield (doc, f);
      } else {
        for (final year in sortedYears) {
          final f = byName['${doc}_cia_aberta_${suffix}_$year.csv'];
          if (f != null) yield (doc, f);
        }
      }
    }
  }

  _Version key(Map<String, String> r, String doc) => (
        cnpj: r['CNPJ_CIA'] ?? '',
        refer: _day(r['DT_REFER']),
        doc: doc.toUpperCase(),
        version: int.tryParse(r['VERSAO'] ?? '') ?? 1,
      );

  // --- Composição de capital -----------------------------------------------
  Map<_Version, ({double paidInShares, double treasury})> loadCapital(
      {required bool oldVersions}) {
    final out = <_Version, ({double paidInShares, double treasury})>{};
    for (final (doc, f) in files('composicao_capital', oldVersions: oldVersions)) {
      for (final r in readCsv(f)) {
        final tot = double.tryParse(r['QT_ACAO_TOTAL_CAP_INTEGR'] ?? '');
        final treasuryShares = double.tryParse(r['QT_ACAO_TOTAL_TESOURO'] ?? '') ?? 0;
        if (tot == null || tot <= 0) continue;
        out[key(r, doc)] = (paidInShares: tot, treasury: treasuryShares);
      }
    }
    return out;
  }

  // --- Demonstrações --------------------------------------------------------
  /// Lê uma demonstração de todos os anos. [order] é `Ú` (exercício do
  /// documento) ou `P` (o comparativo que o acompanha).
  Map<_Version, _Statement> load(String suffix, String order,
      {required bool oldVersions}) {
    final out = <_Version, _Statement>{};
    for (final (doc, f) in files(suffix, oldVersions: oldVersions)) {
      for (final r in readCsv(f)) {
        if (!(r['ORDEM_EXERC'] ?? '').startsWith(order)) continue;
        final row = CvmAccountLine.fromText(
          code: r['CD_CONTA'] ?? '',
          label: r['DS_CONTA'] ?? '',
          value: r['VL_CONTA'] ?? '',
          scale: _scale(r['ESCALA_MOEDA']),
        );
        if (row == null) continue;
        out
            .putIfAbsent(key(r, doc), _Statement.new)
            .append(_day(r['DT_INI_EXERC']), row);
      }
    }
    return out;
  }

  // --- Ponte ---------------------------------------------------------------
  final bridgePath = File('docs/validacao/ponte_cvm.json');
  if (!bridgePath.existsSync()) {
    stderr.writeln('Rode antes: dart run tool/cvm_ponte.dart $dir');
    exit(2);
  }
  final bridge = ((jsonDecode(bridgePath.readAsStringSync())
          as Map<String, dynamic>)['ponte'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  final byCnpj = <String, List<String>>{};
  for (final e in bridge.entries) {
    byCnpj.putIfAbsent(e.value, () => []).add(e.key);
  }

  Map<String, double?> flows(CvmChart dreChart, CvmChart dfcC) => {
        'receita': dreChart.revenue,
        'ebit': dreChart.ebit,
        'resultadoAntesDosTributos': dreChart.incomeBeforeTaxes,
        'tributos': dreChart.taxes,
        'lucroLiquido': dreChart.netIncome,
        'caixaOperacional': dfcC.operatingCashFlow,
        'caixaDeInvestimento': dfcC.investingCashFlow,
        'capex': dfcC.capex,
        'depreciacaoEAmortizacao': dfcC.depreciationAndAmortization,
      };

  // --- Montagem ------------------------------------------------------------
  var withFallback = 0, withoutDre = 0, balanceOk = 0, balanceN = 0;
  var resolvedDuplicates = 0, withoutReceipt = 0;
  final layouts = <String, int>{};

  /// Monta os exercícios de um conjunto de CSVs — os anuais ou os das versões
  /// antigas. A data de recebimento é a **da versão** que as contas trazem.
  List<Map<String, Object?>> build({required bool oldVersions}) {
    final dre = {
      'con': load('DRE_con', 'Ú', oldVersions: oldVersions),
      'ind': load('DRE_ind', 'Ú', oldVersions: oldVersions),
    };
    final previousDre = {
      'con': load('DRE_con', 'P', oldVersions: oldVersions),
      'ind': load('DRE_ind', 'P', oldVersions: oldVersions),
    };
    final dfc = {
      'con': load('DFC_MI_con', 'Ú', oldVersions: oldVersions),
      'ind': load('DFC_MI_ind', 'Ú', oldVersions: oldVersions),
    };
    final dfcPrev = {
      'con': load('DFC_MI_con', 'P', oldVersions: oldVersions),
      'ind': load('DFC_MI_ind', 'P', oldVersions: oldVersions),
    };
    final bpa = {
      'con': load('BPA_con', 'Ú', oldVersions: oldVersions),
      'ind': load('BPA_ind', 'Ú', oldVersions: oldVersions),
    };
    final bpp = {
      'con': load('BPP_con', 'Ú', oldVersions: oldVersions),
      'ind': load('BPP_ind', 'Ú', oldVersions: oldVersions),
    };
    final capital = loadCapital(oldVersions: oldVersions);

    final fiscalYears = <Map<String, Object?>>[];
    final keys = {...dre['con']!.keys, ...dre['ind']!.keys};
    if (!oldVersions) {
      final withDre = {
        for (final k in keys) (cnpj: k.cnpj, refer: k.refer, doc: k.doc),
      };
      withoutDre = meta.keys.where((k) => !withDre.contains(k)).length;
    }
    for (final k in keys) {
      // A versão das contas dá a data de recebimento. Nos anuais, a versão que
      // o CSV traz é a última, e o índice a confirma; sem ela no índice, fica a
      // vigente, como antes.
      final m = byVersion[k] ??
          (oldVersions ? null : meta[(cnpj: k.cnpj, refer: k.refer, doc: k.doc)]);
      if (m == null) {
        withoutReceipt++;
        continue;
      }
      var origin = 'con';
      if (dre['con']![k] == null) {
        origin = 'ind';
        if (dre['ind']![k] != null) withFallback++;
      }
      final dreStatement = dre[origin]![k];
      if (dreStatement == null) continue;

      final chartDre = CvmChart.of(dreStatement.rows);
      final chartDfc = CvmChart.of(dfc[origin]![k]?.rows ?? const []);
      final chartBal = CvmChart.of([
        ...?bpa[origin]![k]?.rows,
        ...?bpp[origin]![k]?.rows,
      ]);
      layouts[chartDre.layout.key] = (layouts[chartDre.layout.key] ?? 0) + 1;

      final at = chartBal.totalAssets;
      final pt = chartBal.totalLiabilities;
      if (at != null && pt != null && at.abs() > 1) {
        balanceN++;
        if (((at - pt).abs() / at.abs()) < 1e-6) balanceOk++;
      }

      // Acumulado do mesmo período no exercício anterior — só o ITR precisa,
      // para os últimos doze meses. A DFP é o ano cheio por si.
      Map<String, Object?>? previous;
      if (k.doc == 'ITR') {
        final dPrev = previousDre[origin]![k];
        if (dPrev != null) {
          final fPrev = flows(
            CvmChart.of(dPrev.rows),
            CvmChart.of(dfcPrev[origin]![k]?.rows ?? const []),
          );
          previous = {'inicioDoPeriodo': dPrev.start, ...fPrev};
        }
        if (dreStatement.duplicates > 0) resolvedDuplicates++;
      }

      final cap = capital[k];
      fiscalYears.add({
        'cnpj': k.cnpj,
        'nome': m.denom,
        'tickers': byCnpj[k.cnpj] ?? const <String>[],
        'documento': k.doc,
        'inicioDoPeriodo': dreStatement.start,
        'fimDoExercicio': k.refer,
        'recebidoEm': m.received,
        'versao': m.version,
        'origem': origin == 'con' ? 'consolidado' : 'individual',
        'layout': chartDre.layout.key,
        ...flows(chartDre, chartDfc),
        'lucroPorAcao': chartDre.earningsPerShare,
        'ativoTotal': at,
        'ativoCirculante': chartBal.currentAssets,
        'passivoCirculante': chartBal.currentLiabilities,
        'patrimonioLiquido': chartBal.equity,
        'naoControladores': chartBal.nonControllingInterests,
        'caixa': chartBal.cash,
        'aplicacoesFinanceiras': chartBal.financialInvestments,
        'imobilizado': chartBal.propertyPlantEquipment,
        'intangivel': chartBal.intangibleAssets,
        'dividaDeCurtoPrazo': chartBal.shortTermDebt,
        'dividaDeLongoPrazo': chartBal.longTermDebt,
        'acoesIntegralizadas': cap?.paidInShares,
        'acoesEmTesouraria': cap?.treasury,
        'anterior': previous,
      });
    }

    fiscalYears.sort((a, b) {
      final c = (a['cnpj']! as String).compareTo(b['cnpj']! as String);
      if (c != 0) return c;
      final f = (a['fimDoExercicio']! as String)
          .compareTo(b['fimDoExercicio']! as String);
      return f != 0 ? f : (a['versao']! as int).compareTo(b['versao']! as int);
    });
    return fiscalYears;
  }

  // Nos anuais, **uma entrada por documento, a de maior versão**: um
  // documento raro vem com duas versões em arquivos de anos diferentes (a DFP
  // de 2021 da INTER & CO), e a versão menor não é a vigente de hoje.
  final fiscalYears = () {
    final byDoc = <String, Map<String, Object?>>{};
    for (final e in build(oldVersions: false)) {
      final k = '${e['cnpj']}|${e['fimDoExercicio']}|${e['documento']}';
      final current = byDoc[k];
      if (current == null || (e['versao']! as int) > (current['versao']! as int)) {
        byDoc[k] = e;
      }
    }
    return [for (final e in byDoc.values) e];
  }();
  // O recuo, as duplicadas e a identidade descrevem a base vigente; as
  // versões antigas são contadas à parte.
  final (fallback0, dup0, balanceOk0, balanceN0) =
      (withFallback, resolvedDuplicates, balanceOk, balanceN);
  final oldVersions = versionsByName.isEmpty
      ? const <Map<String, Object?>>[]
      : build(oldVersions: true);
  final oldBalanceOk = balanceOk - balanceOk0;
  final oldBalanceN = balanceN - balanceN0;
  withFallback = fallback0;
  resolvedDuplicates = dup0;
  balanceOk = balanceOk0;
  balanceN = balanceN0;

  final withTicker =
      fiscalYears.where((e) => (e['tickers']! as List).isNotEmpty).length;
  stdout.writeln('');
  stdout.writeln('  documentos montados : ${fiscalYears.length}');
  stdout.writeln('    DFP: ${fiscalYears.where((e) => e['documento'] == 'DFP').length}'
      '   ITR: ${fiscalYears.where((e) => e['documento'] == 'ITR').length}');
  stdout.writeln('  companhias distintas: '
      '${fiscalYears.map((e) => e['cnpj']).toSet().length}');
  stdout.writeln('  com ticker no universo de hoje: $withTicker');
  stdout.writeln('  fora do universo de hoje: ${fiscalYears.length - withTicker}');
  stdout.writeln('  recuo para individual: $withFallback');
  stdout.writeln('  sem DRE: $withoutDre');
  stdout.writeln('  ITR em que a DRE trazia trimestre E acumulado: '
      '$resolvedDuplicates');
  stdout.writeln('  layouts: $layouts');
  stdout.writeln('  IDENTIDADE ativo = passivo: $balanceOk / $balanceN');

  final output = File('data/cvm_exercicios.json');
  output.writeAsStringSync(jsonEncode(fiscalYears));
  stdout.writeln('\n  gravado ${output.path} '
      '(${(output.lengthSync() / 1e6).toStringAsFixed(1)} MB)');

  // --- Versões antigas (item B8) --------------------------------------------
  final versionsOutput = File('data/cvm_versoes.json');
  if (oldVersions.isEmpty) {
    if (versionsOutput.existsSync()) versionsOutput.deleteSync();
    stdout.writeln('  sem versões antigas em $dir/versoes — rode '
        'tool/cvm_versoes_baixar.py para o point-in-time por versão');
  } else {
    versionsOutput.writeAsStringSync(jsonEncode(oldVersions));
    stdout.writeln('  versões antigas montadas: ${oldVersions.length}   '
        'IDENTIDADE ativo = passivo: $oldBalanceOk / $oldBalanceN');
    stdout.writeln('  gravado ${versionsOutput.path} '
        '(${(versionsOutput.lengthSync() / 1e6).toStringAsFixed(1)} MB)');
  }
  if (withoutReceipt > 0) {
    stdout.writeln('  versões sem data de recebimento no índice, descartadas: '
        '$withoutReceipt');
  }
}
