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

class OutorgasPorData {
  OutorgasPorData._(this._docs, this._ponte);

  /// CNPJ → documentos com concessão, com recebimento, referência, versão e
  /// os textos de duração.
  final Map<String,
          List<({DateTime receb, DateTime ref, int versao, List<String> duracoes})>>
      _docs;

  /// Ticker → CNPJ.
  final Map<String, String> _ponte;

  /// Anos de idade máxima do formulário, contados do ano da data.
  static const int idadeMaximaAnos = 6;

  static DateTime? _dia(String? v) {
    if (v == null || v.length < 10) return null;
    return DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
  }

  /// Lê `data/cvm/fre` e a ponte ticker↔CNPJ. `null` sem os arquivos.
  static OutorgasPorData? ler({String pasta = 'data/cvm/fre'}) {
    final dir = Directory(pasta);
    final ponteArq = File('docs/validacao/ponte_cvm.json');
    if (!dir.existsSync() || !ponteArq.existsSync()) return null;

    final recebimento = <String, DateTime>{};
    final arquivos = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in arquivos) {
      final nome = f.uri.pathSegments.last;
      if (!RegExp(r'^fre_cia_aberta_\d{4}\.csv$').hasMatch(nome)) continue;
      for (final r in lerCsvCvm(f)) {
        final id = r['ID_DOC'];
        final receb = _dia(r['DT_RECEB']);
        if (id != null && receb != null) recebimento[id] = receb;
      }
    }

    final porDoc = <String,
        ({String cnpj, DateTime receb, DateTime ref, int versao, List<String> duracoes})>{};
    for (final f in arquivos) {
      if (!f.path.contains('fre_cia_aberta_ativo_intangivel_')) continue;
      for (final r in lerCsvCvm(f)) {
        if (!(r['Tipo_Ativo'] ?? '').startsWith('Concess')) continue;
        final id = r['ID_Documento'];
        final cnpj = r['CNPJ_Companhia'];
        final ref = _dia(r['Data_Referencia']);
        final versao = int.tryParse(r['Versao'] ?? '');
        final receb = id == null ? null : recebimento[id];
        if (cnpj == null || ref == null || versao == null || receb == null) {
          continue;
        }
        final atual = porDoc[id!];
        if (atual == null) {
          porDoc[id] = (
            cnpj: cnpj,
            receb: receb,
            ref: ref,
            versao: versao,
            duracoes: [r['Duracao'] ?? ''],
          );
        } else {
          atual.duracoes.add(r['Duracao'] ?? '');
        }
      }
    }
    final docs = <String,
        List<({DateTime receb, DateTime ref, int versao, List<String> duracoes})>>{};
    for (final d in porDoc.values) {
      (docs[d.cnpj] ??= []).add(
          (receb: d.receb, ref: d.ref, versao: d.versao, duracoes: d.duracoes));
    }

    final pares = (jsonDecode(ponteArq.readAsStringSync())
        as Map<String, dynamic>)['ponte'] as Map<String, dynamic>;
    return OutorgasPorData._(
        docs, {for (final p in pares.entries) p.key: p.value as String});
  }

  /// O prazo conhecido em [data], ou `null`.
  ConcessionTerm? naData(String ticker, DateTime data) {
    final cnpj = _ponte[ticker];
    return cnpj == null ? null : naDataPorCnpj(cnpj, data);
  }

  /// O prazo da companhia [cnpj] conhecido em [data], ou `null` — para as
  /// deslistadas, que não estão na ponte do universo de hoje.
  ConcessionTerm? naDataPorCnpj(String cnpj, DateTime data) {
    final meus = _docs[cnpj];
    if (meus == null) return null;
    final dia = DateTime.utc(data.year, data.month, data.day);
    ({DateTime receb, DateTime ref, int versao, List<String> duracoes})? melhor;
    for (final d in meus) {
      if (d.receb.isAfter(dia)) continue;
      final m = melhor;
      if (m == null ||
          d.ref.isAfter(m.ref) ||
          (d.ref.isAtSameMomentAs(m.ref) && d.versao > m.versao)) {
        melhor = d;
      }
    }
    final m = melhor;
    if (m == null || m.ref.year < data.year - idadeMaximaAnos) return null;
    final resumo = FreConcessionTerm.summarize(m.duracoes, m.ref);
    if (resumo.end == null) return null;
    return ConcessionTerm(
      end: resumo.end!,
      contracts: resumo.contratos,
      parsed: resumo.lidos,
      active: resumo.vigentes,
      reference: m.ref,
    );
  }
}
