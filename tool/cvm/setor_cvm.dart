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

typedef Portas = ({bool financeira, bool ciclica, bool concessao});

Portas portasDe(B3Classification c) => (
      financeira: FinancialSectors.isFinancial(
          sectorKey: c.sectorKey, industry: c.industry),
      ciclica: CyclicalSectors.hasCyclePrecedence(
          sectorKey: c.sectorKey, industry: c.industry),
      concessao: ConcessionSectors.hasFiniteTerm(
          sectorKey: c.sectorKey, industry: c.industry),
    );

class SetorCvm {
  SetorCvm._(this.setorPorCnpj, this._porSetor);

  /// Setor de atividade da FCA mais recente de cada CNPJ.
  final Map<String, String> setorPorCnpj;

  /// Setor da CVM → (CNPJ da listada, classificação da B3).
  final Map<String, List<(String, B3Classification)>> _porSetor;

  static const _prefixoHolding = 'Emp. Adm. Part. - ';

  /// Lê a FCA geral de `data/cvm` e liga as listadas pela ponte.
  ///
  /// - [classificacaoListada]: CNPJ da listada → classificação da B3.
  static SetorCvm? ler(Map<String, B3Classification> classificacaoListada,
      {String pasta = 'data/cvm'}) {
    final dir = Directory(pasta);
    if (!dir.existsSync()) return null;
    final ultimo = <String, (String, int, String)>{};
    final arquivos = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            RegExp(r'^fca_cia_aberta_geral_\d{4}\.csv$')
                .hasMatch(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (arquivos.isEmpty) return null;
    for (final f in arquivos) {
      for (final r in lerCsvCvm(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final ref = r['Data_Referencia'] ?? '';
        final versao = int.tryParse(r['Versao'] ?? '') ?? 0;
        final setor = (r['Setor_Atividade'] ?? '').trim();
        if (cnpj == null || setor.isEmpty) continue;
        final atual = ultimo[cnpj];
        if (atual == null ||
            ref.compareTo(atual.$1) > 0 ||
            (ref == atual.$1 && versao >= atual.$2)) {
          ultimo[cnpj] = (ref, versao, setor);
        }
      }
    }
    final setorPorCnpj = {for (final e in ultimo.entries) e.key: e.value.$3};
    final porSetor = <String, List<(String, B3Classification)>>{};
    for (final e in classificacaoListada.entries) {
      final setor = setorPorCnpj[e.key];
      if (setor == null) continue;
      (porSetor[setor] ??= []).add((e.key, e.value));
    }
    return SetorCvm._(setorPorCnpj, porSetor);
  }

  /// As listadas do setor, tentando a forma sem o prefixo de holding e a com
  /// ele quando a exata não tem nenhuma.
  List<(String, B3Classification)> _pares(String setor) {
    final exata = _porSetor[setor];
    if (exata != null && exata.isNotEmpty) return exata;
    final semPrefixo = setor.startsWith(_prefixoHolding)
        ? setor.substring(_prefixoHolding.length)
        : '$_prefixoHolding$setor';
    return _porSetor[semPrefixo] ?? const [];
  }

  /// A classificação da B3 que representa [setor], sem [excluir].
  static B3Classification? _representante(
      List<(String, B3Classification)> pares, {String? excluir}) {
    final uteis = [for (final p in pares) if (p.$1 != excluir) p.$2];
    if (uteis.isEmpty) return null;
    final votos = <Portas, int>{};
    for (final c in uteis) {
      final k = portasDe(c);
      votos[k] = (votos[k] ?? 0) + 1;
    }
    final maioria = votos.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    final porRotulo = <String, (B3Classification, int)>{};
    for (final c in uteis) {
      if (portasDe(c) != maioria) continue;
      final atual = porRotulo[c.label];
      porRotulo[c.label] = (c, (atual?.$2 ?? 0) + 1);
    }
    // Empate de contagem: o rótulo em ordem alfabética, para o resultado não
    // depender da ordem de leitura.
    final ordenados = porRotulo.values.toList()
      ..sort((a, b) {
        final n = b.$2.compareTo(a.$2);
        return n != 0 ? n : a.$1.label.compareTo(b.$1.label);
      });
    return ordenados.first.$1;
  }

  /// A classificação que representa o setor da CVM de [cnpj], ou `null`.
  B3Classification? classificacaoDe(String cnpj) {
    final setor = setorPorCnpj[cnpj];
    if (setor == null) return null;
    return _representante(_pares(setor));
  }

  /// Nas listadas, as três portas pelo setor da CVM, sem a companhia, contra as
  /// portas pela B3.
  ({
    int listadas,
    int semReferencia,
    int financeira,
    int ciclica,
    int concessao,
    int todas,
    List<String> divergentes,
  }) concordancia() {
    var n = 0, sem = 0, fin = 0, cic = 0, con = 0, todas = 0;
    final divergentes = <String>[];
    for (final e in _porSetor.entries) {
      for (final (cnpj, b3) in e.value) {
        n++;
        final prevista = _representante(e.value, excluir: cnpj);
        if (prevista == null) {
          sem++;
          continue;
        }
        final p = portasDe(prevista), r = portasDe(b3);
        if (p.financeira == r.financeira) fin++;
        if (p.ciclica == r.ciclica) cic++;
        if (p.concessao == r.concessao) con++;
        if (p == r) {
          todas++;
        } else {
          divergentes.add('${e.key}: ${b3.label} → ${prevista.label}');
        }
      }
    }
    return (
      listadas: n,
      semReferencia: sem,
      financeira: fin,
      ciclica: cic,
      concessao: con,
      todas: todas,
      divergentes: divergentes,
    );
  }
}
