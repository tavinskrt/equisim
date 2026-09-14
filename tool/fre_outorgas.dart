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

const _saida = 'assets/cvm/outorgas.json';
const _relatorio = 'docs/validacao/outorgas.json';

/// Referência mínima do formulário: antes disso, o prazo é velho demais.
final _referenciaMinima = DateTime.utc(2020, 1, 1);

DateTime? _dia(String? v) {
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
  final ponte = <String, List<String>>{};
  final pares = (jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
      as Map<String, dynamic>;
  for (final p in pares.entries) {
    (ponte[p.value as String] ??= []).add(p.key);
  }
  final registro = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);

  // CNPJ → documento mais recente com concessão: maior referência, e nela a
  // maior versão.
  final porCnpj = <String, ({DateTime ref, int versao, List<String> duracoes})>{};
  final arquivos = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('fre_cia_aberta_ativo_intangivel_'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in arquivos) {
    for (final r in lerCsvCvm(f)) {
      if (!(r['Tipo_Ativo'] ?? '').startsWith('Concess')) continue;
      final cnpj = r['CNPJ_Companhia'];
      final ref = _dia(r['Data_Referencia']);
      final versao = int.tryParse(r['Versao'] ?? '');
      if (cnpj == null || ref == null || versao == null) continue;
      final atual = porCnpj[cnpj];
      if (atual == null ||
          ref.isAfter(atual.ref) ||
          (ref.isAtSameMomentAs(atual.ref) && versao > atual.versao)) {
        porCnpj[cnpj] = (ref: ref, versao: versao, duracoes: [r['Duracao'] ?? '']);
      } else if (ref.isAtSameMomentAs(atual.ref) && versao == atual.versao) {
        atual.duracoes.add(r['Duracao'] ?? '');
      }
    }
  }

  final pacote = <String, ConcessionTerm>{};
  final linhas = <Map<String, Object?>>[];
  for (final e in porCnpj.entries) {
    final tickers = ponte[e.key];
    if (tickers == null) continue;
    final resumo = FreConcessionTerm.summarize(e.value.duracoes, e.value.ref);
    final recente = !e.value.ref.isBefore(_referenciaMinima);
    final entra = recente && resumo.end != null;
    for (final t in tickers) {
      final emissor = registro[t.length >= 4 ? t.substring(0, 4) : ''];
      final c = emissor?.classification;
      final concessao = c != null &&
          ConcessionSectors.hasFiniteTerm(
              sectorKey: c.sectorKey, industry: c.industry);
      linhas.add({
        'ticker': t,
        'cnpj': e.key,
        'concessao': concessao,
        'classificacao': c?.label,
        'referencia': _fmt(e.value.ref),
        'versao': e.value.versao,
        'contratos': resumo.contratos,
        'lidos': resumo.lidos,
        'vigentes': resumo.vigentes,
        'fim': resumo.end == null ? null : _fmt(resumo.end!),
        'entra': entra,
        'motivo': entra
            ? null
            : !recente
                ? 'formulário de ${e.value.ref.year}, antes de 2020'
                : 'nenhuma outorga vigente com data legível',
      });
      if (entra) {
        pacote[t] = ConcessionTerm(
          end: resumo.end!,
          contracts: resumo.contratos,
          parsed: resumo.lidos,
          active: resumo.vigentes,
          reference: e.value.ref,
        );
      }
    }
  }
  linhas.sort((a, b) => (a['ticker']! as String).compareTo(b['ticker']! as String));

  final maisRecente = porCnpj.values
      .map((v) => v.ref)
      .fold<DateTime>(DateTime.utc(2000), (a, b) => b.isAfter(a) ? b : a);
  File(_saida)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
        jsonEncode(ConcessionTermsCodec.encode(pacote, geradoEm: maisRecente)));
  File(_relatorio)
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(linhas));

  final concessoes = linhas.where((l) => l['concessao'] == true).toList();
  stdout.writeln('  companhias com concessão no FRE: ${porCnpj.length}');
  stdout.writeln('  tickers ligados: ${linhas.length}, no pacote: ${pacote.length}');
  stdout.writeln('  concessões pela classificação da B3: ${concessoes.length}');
  for (final l in concessoes) {
    stdout.writeln('    ${(l['ticker']! as String).padRight(7)} '
        'ref ${l['referencia']}  ${l['vigentes']}/${l['contratos']} vigentes  '
        'fim ${l['fim'] ?? '—'}  ${l['entra'] == true ? 'ENTRA' : l['motivo']}');
  }
  stdout.writeln('  gravado $_saida e $_relatorio');
}
