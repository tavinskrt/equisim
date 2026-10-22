// O prazo das outorgas como era conhecido numa data (item A6 nas coortes).
//
// O pacote do aplicativo (`assets/cvm/outorgas.json`) é o formulário mais
// recente de cada companhia, e numa coorte de 2018 isso é conhecimento futuro.
// Aqui cada coorte lê o Formulário de Referência **recebido pela CVM até a data
// dela** — a data de recebimento vem do quadro geral `fre_cia_aberta_AAAA.csv`,
// pelo número do documento —, com a mesma regra do pacote:
//
// - o documento de maior referência e, nela, de maior versão;
// - a mediana dos fins das outorgas vigentes (`FreConcessionTerm.summarize`);
// - e o filtro de idade transposto para a coorte: o pacote aceita formulário
//   de referência a partir de 2020, seis anos antes do ano em que foi montado,
//   e a coorte aceita o de até seis anos antes do ano dela.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'csv.dart';

class GrantsByDate {
  GrantsByDate._(this._docs, this._bridge);

  /// CNPJ → documentos com concessão, com recebimento, referência, versão e
  /// os textos de duração.
  final Map<String,
          List<({DateTime received, DateTime ref, int version, List<String> durations})>>
      _docs;

  /// Ticker → CNPJ.
  final Map<String, String> _bridge;

  /// Anos de idade máxima do formulário, contados do ano da data.
  static const int maxAgeYears = 6;

  static DateTime? _day(String? v) {
    if (v == null || v.length < 10) return null;
    return DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
  }

  /// Lê `data/cvm/fre` e a ponte ticker↔CNPJ. `null` sem os arquivos.
  static GrantsByDate? read({String folder = 'data/cvm/fre'}) {
    final dir = Directory(folder);
    final bridgeFile = File('docs/validacao/ponte_cvm.json');
    if (!dir.existsSync() || !bridgeFile.existsSync()) return null;

    final receipt = <String, DateTime>{};
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (!RegExp(r'^fre_cia_aberta_\d{4}\.csv$').hasMatch(name)) continue;
      for (final r in readCvmCsv(f)) {
        final id = r['ID_DOC'];
        final received = _day(r['DT_RECEB']);
        if (id != null && received != null) receipt[id] = received;
      }
    }

    final byDoc = <String,
        ({String cnpj, DateTime received, DateTime ref, int version, List<String> durations})>{};
    for (final f in files) {
      if (!f.path.contains('fre_cia_aberta_ativo_intangivel_')) continue;
      for (final r in readCvmCsv(f)) {
        if (!(r['Tipo_Ativo'] ?? '').startsWith('Concess')) continue;
        final id = r['ID_Documento'];
        final cnpj = r['CNPJ_Companhia'];
        final ref = _day(r['Data_Referencia']);
        final version = int.tryParse(r['Versao'] ?? '');
        final received = id == null ? null : receipt[id];
        if (cnpj == null || ref == null || version == null || received == null) {
          continue;
        }
        final current = byDoc[id!];
        if (current == null) {
          byDoc[id] = (
            cnpj: cnpj,
            received: received,
            ref: ref,
            version: version,
            durations: [r['Duracao'] ?? ''],
          );
        } else {
          current.durations.add(r['Duracao'] ?? '');
        }
      }
    }
    final docs = <String,
        List<({DateTime received, DateTime ref, int version, List<String> durations})>>{};
    for (final d in byDoc.values) {
      (docs[d.cnpj] ??= []).add(
          (received: d.received, ref: d.ref, version: d.version, durations: d.durations));
    }

    final pairs = (jsonDecode(bridgeFile.readAsStringSync())
        as Map<String, dynamic>)['ponte'] as Map<String, dynamic>;
    return GrantsByDate._(
        docs, {for (final p in pairs.entries) p.key: p.value as String});
  }

  /// O prazo conhecido em [date], ou `null`.
  ConcessionTerm? atDate(String ticker, DateTime date) {
    final cnpj = _bridge[ticker];
    return cnpj == null ? null : atDateByCnpj(cnpj, date);
  }

  /// O prazo da companhia [cnpj] conhecido em [date], ou `null` — para as
  /// deslistadas, que não estão na ponte do universo de hoje.
  ConcessionTerm? atDateByCnpj(String cnpj, DateTime date) {
    final ownDocs = _docs[cnpj];
    if (ownDocs == null) return null;
    final day = DateTime.utc(date.year, date.month, date.day);
    ({DateTime received, DateTime ref, int version, List<String> durations})? best;
    for (final d in ownDocs) {
      if (d.received.isAfter(day)) continue;
      final m = best;
      if (m == null ||
          d.ref.isAfter(m.ref) ||
          (d.ref.isAtSameMomentAs(m.ref) && d.version > m.version)) {
        best = d;
      }
    }
    final m = best;
    if (m == null || m.ref.year < date.year - maxAgeYears) return null;
    final summary = FreConcessionTerm.summarize(m.durations, m.ref);
    if (summary.end == null) return null;
    return ConcessionTerm(
      end: summary.end!,
      contracts: summary.contracts,
      parsed: summary.readCount,
      active: summary.inForceCount,
      reference: m.ref,
    );
  }
}
