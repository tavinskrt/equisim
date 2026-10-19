// A6 — o prazo das outorgas, do Formulário de Referência para o aplicativo.
//
// Lê o quadro de ativos intangíveis do FRE (item 9.1.b), fica com as linhas de
// "Concessões" do documento mais recente de cada companhia, e resume o texto
// livre da coluna `Duracao` pela mediana dos fins vigentes
// (`FreConcessionTerm`). Grava o pacote que o aplicativo lê e o relatório de
// cobertura.
//
// **Filtro de qualidade.** Só entra no pacote o prazo de um formulário com data
// de referência a partir de 2020 e com ao menos uma outorga vigente legível. O
// FRE repete contrato vencido e renovado com o prazo antigo — a distribuição da
// Cemig aparece "até fevereiro de 2016" no formulário de 2019 —, e prazo velho
// imposto como horizonte seria erro novo.
//
// **O que o pacote muda no preço é pouco, e está dito por quê** na decisão 88:
// com retorno terminal neutro, só o contrato que acaba dentro da projeção
// explícita move o preço.
//
// Uso:
//   python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
//   dart run tool/fre_outorgas.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'cvm/csv.dart';

const _output = 'assets/cvm/outorgas.json';
const _report = 'docs/validacao/outorgas.json';

/// Referência mínima do formulário: antes disso, o prazo é velho demais.
final _minReference = DateTime.utc(2020, 1, 1);

DateTime? _day(String? v) {
  if (v == null || v.length < 10) return null;
  return DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
}

String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  final dir = Directory('data/cvm/fre');
  if (!dir.existsSync()) {
    stderr.writeln('sem data/cvm/fre — rode: python tool/cvm_baixar.py '
        '--docs FRE --destino data/cvm/fre');
    exit(2);
  }
  final bridge = <String, List<String>>{};
  final pairs = (jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
      as Map<String, dynamic>;
  for (final p in pairs.entries) {
    (bridge[p.value as String] ??= []).add(p.key);
  }
  final registry = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);

  // CNPJ → documento mais recente com concessão: maior referência, e nela a
  // maior versão.
  final byCnpj = <String, ({DateTime ref, int version, List<String> durations})>{};
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('fre_cia_aberta_ativo_intangivel_'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    for (final r in readCvmCsv(f)) {
      if (!(r['Tipo_Ativo'] ?? '').startsWith('Concess')) continue;
      final cnpj = r['CNPJ_Companhia'];
      final ref = _day(r['Data_Referencia']);
      final version = int.tryParse(r['Versao'] ?? '');
      if (cnpj == null || ref == null || version == null) continue;
      final current = byCnpj[cnpj];
      if (current == null ||
          ref.isAfter(current.ref) ||
          (ref.isAtSameMomentAs(current.ref) && version > current.version)) {
        byCnpj[cnpj] = (ref: ref, version: version, durations: [r['Duracao'] ?? '']);
      } else if (ref.isAtSameMomentAs(current.ref) && version == current.version) {
        current.durations.add(r['Duracao'] ?? '');
      }
    }
  }

  final package = <String, ConcessionTerm>{};
  final rows = <Map<String, Object?>>[];
  for (final e in byCnpj.entries) {
    final tickers = bridge[e.key];
    if (tickers == null) continue;
    final summary = FreConcessionTerm.summarize(e.value.durations, e.value.ref);
    final recent = !e.value.ref.isBefore(_minReference);
    final enters = recent && summary.end != null;
    for (final t in tickers) {
      final issuer = registry[t.length >= 4 ? t.substring(0, 4) : ''];
      final c = issuer?.classification;
      final concession = c != null &&
          ConcessionSectors.hasFiniteTerm(
              sectorKey: c.sectorKey, industry: c.industry);
      rows.add({
        'ticker': t,
        'cnpj': e.key,
        'concessao': concession,
        'classificacao': c?.label,
        'referencia': _fmt(e.value.ref),
        'versao': e.value.version,
        'contratos': summary.contracts,
        'lidos': summary.readCount,
        'vigentes': summary.inForceCount,
        'fim': summary.end == null ? null : _fmt(summary.end!),
        'entra': enters,
        'motivo': enters
            ? null
            : !recent
                ? 'formulário de ${e.value.ref.year}, antes de 2020'
                : 'nenhuma outorga vigente com data legível',
      });
      if (enters) {
        package[t] = ConcessionTerm(
          end: summary.end!,
          contracts: summary.contracts,
          parsed: summary.readCount,
          active: summary.inForceCount,
          reference: e.value.ref,
        );
      }
    }
  }
  rows.sort((a, b) => (a['ticker']! as String).compareTo(b['ticker']! as String));

  final latest = byCnpj.values
      .map((v) => v.ref)
      .fold<DateTime>(DateTime.utc(2000), (a, b) => b.isAfter(a) ? b : a);
  File(_output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
        jsonEncode(ConcessionTermsCodec.encode(package, generatedAt: latest)));
  File(_report)
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));

  final concessions = rows.where((l) => l['concessao'] == true).toList();
  stdout.writeln('  companhias com concessão no FRE: ${byCnpj.length}');
  stdout.writeln('  tickers ligados: ${rows.length}, no pacote: ${package.length}');
  stdout.writeln('  concessões pela classificação da B3: ${concessions.length}');
  for (final l in concessions) {
    stdout.writeln('    ${(l['ticker']! as String).padRight(7)} '
        'ref ${l['referencia']}  ${l['vigentes']}/${l['contratos']} vigentes  '
        'fim ${l['fim'] ?? '—'}  ${l['entra'] == true ? 'ENTRA' : l['motivo']}');
  }
  stdout.writeln('  gravado $_output e $_report');
}
