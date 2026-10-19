// O setor das companhias deslistadas que a B3 não classifica (item C1b).
//
// A decisão 87 põe o setor da B3 em todo ativo, e o portal responde também
// para 43 das 164 deslistadas da ponte. Para as outras, a única classificação
// que existe é a que a companhia declara na FCA da CVM, o "setor de atividade",
// numa taxonomia diferente.
//
// **A cascata não precisa da taxonomia inteira, só de três portas**: a Porta 1
// (instituição financeira), a precedência do ciclo (commodity) e o prazo
// determinado (concessão). Então a tradução é medida, e não escrita à mão: para
// cada setor da CVM, as listadas que têm os dois cadastros dizem qual
// combinação das três portas é a da maioria, e a classificação da B3 mais comum
// com essa combinação passa a representar o setor. A concordância é conferida
// nas próprias listadas **sem a companhia**, para que ela não vote em si mesma.
//
// Setor da CVM sem listada que o represente fica sem classificação — e aí a
// Porta 1 não dispara, que é o recuo que a cascata já declara.
import 'package:equisim_core/equisim_core.dart';

import 'dart:io';

import 'csv.dart';

typedef Gates = ({bool financial, bool cyclical, bool concession});

Gates gatesOf(B3Classification c) => (
      financial: FinancialSectors.isFinancial(
          sectorKey: c.sectorKey, industry: c.industry),
      cyclical: CyclicalSectors.hasCyclePrecedence(
          sectorKey: c.sectorKey, industry: c.industry),
      concession: ConcessionSectors.hasFiniteTerm(
          sectorKey: c.sectorKey, industry: c.industry),
    );

class CvmSector {
  CvmSector._(this.sectorByCnpj, this._bySector);

  /// Setor de atividade da FCA mais recente de cada CNPJ.
  final Map<String, String> sectorByCnpj;

  /// Setor da CVM → (CNPJ da listada, classificação da B3).
  final Map<String, List<(String, B3Classification)>> _bySector;

  static const _holdingPrefix = 'Emp. Adm. Part. - ';

  /// Lê a FCA geral de `data/cvm` e liga as listadas pela ponte.
  ///
  /// - [listedClassification]: CNPJ da listada → classificação da B3.
  static CvmSector? read(Map<String, B3Classification> listedClassification,
      {String folder = 'data/cvm'}) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return null;
    final last = <String, (String, int, String)>{};
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            RegExp(r'^fca_cia_aberta_geral_\d{4}\.csv$')
                .hasMatch(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) return null;
    for (final f in files) {
      for (final r in readCvmCsv(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final ref = r['Data_Referencia'] ?? '';
        final version = int.tryParse(r['Versao'] ?? '') ?? 0;
        final sector = (r['Setor_Atividade'] ?? '').trim();
        if (cnpj == null || sector.isEmpty) continue;
        final current = last[cnpj];
        if (current == null ||
            ref.compareTo(current.$1) > 0 ||
            (ref == current.$1 && version >= current.$2)) {
          last[cnpj] = (ref, version, sector);
        }
      }
    }
    final sectorByCnpj = {for (final e in last.entries) e.key: e.value.$3};
    final bySector = <String, List<(String, B3Classification)>>{};
    for (final e in listedClassification.entries) {
      final sector = sectorByCnpj[e.key];
      if (sector == null) continue;
      (bySector[sector] ??= []).add((e.key, e.value));
    }
    return CvmSector._(sectorByCnpj, bySector);
  }

  /// As listadas do setor, tentando a forma sem o prefixo de holding e a com
  /// ele quando a exata não tem nenhuma.
  List<(String, B3Classification)> _pairs(String sector) {
    final exact = _bySector[sector];
    if (exact != null && exact.isNotEmpty) return exact;
    final withoutPrefix = sector.startsWith(_holdingPrefix)
        ? sector.substring(_holdingPrefix.length)
        : '$_holdingPrefix$sector';
    return _bySector[withoutPrefix] ?? const [];
  }

  /// A classificação da B3 que representa [setor], sem [exclude].
  static B3Classification? _representative(
      List<(String, B3Classification)> pairs, {String? exclude}) {
    final useful = [for (final p in pairs) if (p.$1 != exclude) p.$2];
    if (useful.isEmpty) return null;
    final votes = <Gates, int>{};
    for (final c in useful) {
      final k = gatesOf(c);
      votes[k] = (votes[k] ?? 0) + 1;
    }
    final majority = votes.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    final byLabel = <String, (B3Classification, int)>{};
    for (final c in useful) {
      if (gatesOf(c) != majority) continue;
      final current = byLabel[c.label];
      byLabel[c.label] = (c, (current?.$2 ?? 0) + 1);
    }
    // Empate de contagem: o rótulo em ordem alfabética, para o resultado não
    // depender da ordem de leitura.
    final sortedRows = byLabel.values.toList()
      ..sort((a, b) {
        final n = b.$2.compareTo(a.$2);
        return n != 0 ? n : a.$1.label.compareTo(b.$1.label);
      });
    return sortedRows.first.$1;
  }

  /// A classificação que representa o setor da CVM de [cnpj], ou `null`.
  B3Classification? classificationOf(String cnpj) {
    final sector = sectorByCnpj[cnpj];
    if (sector == null) return null;
    return _representative(_pairs(sector));
  }

  /// Nas listadas, as três portas pelo setor da CVM, sem a companhia, contra as
  /// portas pela B3.
  ({
    int listed,
    int withoutReference,
    int financial,
    int cyclical,
    int concession,
    int totalCount,
    List<String> divergent,
  }) agreement() {
    var n = 0, withoutCount = 0, financialCount = 0, cyclicalCount = 0, concessionCount = 0, totalCount = 0;
    final divergent = <String>[];
    for (final e in _bySector.entries) {
      for (final (cnpj, b3) in e.value) {
        n++;
        final predicted = _representative(e.value, exclude: cnpj);
        if (predicted == null) {
          withoutCount++;
          continue;
        }
        final p = gatesOf(predicted), r = gatesOf(b3);
        if (p.financial == r.financial) financialCount++;
        if (p.cyclical == r.cyclical) cyclicalCount++;
        if (p.concession == r.concession) concessionCount++;
        if (p == r) {
          totalCount++;
        } else {
          divergent.add('${e.key}: ${b3.label} → ${predicted.label}');
        }
      }
    }
    return (
      listed: n,
      withoutReference: withoutCount,
      financial: financialCount,
      cyclical: cyclicalCount,
      concession: concessionCount,
      totalCount: totalCount,
      divergent: divergent,
    );
  }
}
