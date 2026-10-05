/// A espécie do controle acionário, do Formulário Cadastral da CVM (item B46).
library;

/// Quem controla a companhia, como ela declara no Formulário Cadastral.
///
/// O FCA traz, todo ano, a coluna `Especie_Controle_Acionario`: "Estatal",
/// "Estatal Holding", "Privado", "Privado Holding", "Estrangeiro" ou
/// "Estrangeiro Holding". A holding é a mesma espécie de controle, exercida por
/// meio de outra companhia — a Petrobras declara "Estatal Holding" —, e por isso
/// não muda a classe.
enum ShareholderControl {
  /// Controle de um ente público: União, estado ou município.
  state,

  /// Controle privado nacional.
  private,

  /// Controle privado estrangeiro.
  foreign;

  /// A classe do texto do FCA, ou `null` quando ele não diz.
  static ShareholderControl? fromFca(String texto) {
    final t = texto.trim().toLowerCase();
    if (t.startsWith('estatal')) return ShareholderControl.state;
    if (t.startsWith('privad')) return ShareholderControl.private;
    if (t.startsWith('estrangeir')) return ShareholderControl.foreign;
    return null;
  }
}

/// Um trecho do histórico: a espécie de controle valendo desde [since].
class ShareholderControlPeriod {
  /// Primeiro dia em que a espécie vale.
  final DateTime since;

  /// A espécie.
  final ShareholderControl control;

  const ShareholderControlPeriod({required this.since, required this.control});
}

/// Uma linha do FCA, como a ferramenta a lê.
typedef ShareholderControlFiling = ({
  DateTime reference,
  String species,
  DateTime? speciesDate,
});

/// O histórico do controle, montado das linhas do FCA, e o pacote.
abstract final class ShareholderControlHistory {
  /// Versão do formato do pacote.
  static const int versao = 1;

  /// O histórico de uma companhia, a partir das linhas do FCA de todos os anos.
  ///
  /// **A data da mudança.** O formulário é anual, com data de referência no
  /// primeiro dia do ano, e a privatização acontece no meio dele. A coluna
  /// `Data_Especie_Controle_Acionario` deveria dar o dia, mas vem em branco,
  /// com a data da fundação ou com a do evento conforme a companhia e o ano: a
  /// Eletrobras declara 28/01/1971 nos formulários de 2022 a 2024 e 17/06/2022
  /// nos de 2025 e 2026. Por isso, para cada mudança entre o formulário de um
  /// ano e o do seguinte, vale a primeira data declarada **pela espécie nova**,
  /// em qualquer formulário, que caia entre a referência do último formulário
  /// da espécie antiga e um ano depois da do primeiro da nova. Sem data
  /// plausível, a mudança vale da referência do primeiro formulário da espécie
  /// nova, 1º de janeiro — o que pode adiantá-la ou atrasá-la em meses: a
  /// CEEE-D, privatizada em julho de 2021, muda em 01/01/2022.
  ///
  /// Linhas sem espécie legível são ignoradas. Devolve lista vazia quando não
  /// sobra nenhuma.
  static List<ShareholderControlPeriod> fromFilings(
    List<ShareholderControlFiling> filings,
  ) {
    final linhas = [
      for (final f in filings)
        if (ShareholderControl.fromFca(f.species) case final c?)
          (
            reference: _diaUtc(f.reference),
            control: c,
            speciesDate: f.speciesDate == null ? null : _diaUtc(f.speciesDate!),
          ),
    ]..sort((a, b) => a.reference.compareTo(b.reference));
    if (linhas.isEmpty) return const [];
    final periodos = <ShareholderControlPeriod>[
      ShareholderControlPeriod(
          since: linhas.first.reference, control: linhas.first.control),
    ];
    for (var i = 1; i < linhas.length; i++) {
      final antes = linhas[i - 1];
      final agora = linhas[i];
      if (agora.control == antes.control) continue;
      // Um ano de calendário depois, e não 366 dias corridos.
      final ref = agora.reference;
      final ate = DateTime.utc(ref.year + 1, ref.month, ref.day);
      final candidatas = [
        for (final l in linhas)
          if (l.control == agora.control && l.speciesDate != null)
            if (!l.speciesDate!.isBefore(antes.reference) &&
                !l.speciesDate!.isAfter(ate))
              l.speciesDate!,
      ]..sort();
      periodos.add(ShareholderControlPeriod(
        since: candidatas.isEmpty ? agora.reference : candidatas.first,
        control: agora.control,
      ));
    }
    return periodos;
  }

  /// A espécie de controle no dia de [asOf], ou `null` antes do primeiro
  /// trecho. A comparação é por dia civil, em UTC, como as datas do histórico.
  static ShareholderControl? at(
    List<ShareholderControlPeriod> periods,
    DateTime asOf,
  ) {
    final dia = _diaUtc(asOf);
    ShareholderControl? vale;
    for (final p in periods) {
      if (_diaUtc(p.since).isAfter(dia)) break;
      vale = p.control;
    }
    return vale;
  }

  /// O pacote: o histórico de cada emissor, pela raiz do código de
  /// negociação — a mesma chave do registro da B3.
  static Map<String, Object?> encode(
    Map<String, List<ShareholderControlPeriod>> porEmissor, {
    required DateTime geradoEm,
  }) =>
      {
        'versao': versao,
        'geradoEm': _dia(geradoEm),
        'fonte': 'Formulário Cadastral da CVM, Especie_Controle_Acionario',
        'emissores': {
          for (final e in (porEmissor.keys.toList()..sort()))
            e: [
              for (final p in porEmissor[e]!)
                {'desde': _dia(p.since), 'controle': p.control.name},
            ],
        },
      };

  /// Lê o pacote; `null` quando a versão ou a forma não são as esperadas.
  static ({DateTime geradoEm, Map<String, List<ShareholderControlPeriod>> porEmissor})?
      decode(Map<String, dynamic> json) {
    if (json['versao'] != versao) return null;
    final lido = DateTime.tryParse(json['geradoEm'] as String? ?? '');
    final gerado = lido == null ? null : _diaUtc(lido);
    final emissores = json['emissores'];
    if (gerado == null || emissores is! Map<String, dynamic>) return null;
    final saida = <String, List<ShareholderControlPeriod>>{};
    for (final e in emissores.entries) {
      final lista = e.value;
      if (lista is! List) return null;
      final periodos = <ShareholderControlPeriod>[];
      for (final p in lista) {
        if (p is! Map<String, dynamic>) return null;
        final lida = DateTime.tryParse(p['desde'] as String? ?? '');
        final desde = lida == null ? null : _diaUtc(lida);
        final controle = ShareholderControl.values
            .where((c) => c.name == p['controle'])
            .firstOrNull;
        if (desde == null || controle == null) return null;
        periodos.add(ShareholderControlPeriod(since: desde, control: controle));
      }
      periodos.sort((a, b) => a.since.compareTo(b.since));
      saida[e.key] = periodos;
    }
    return (geradoEm: gerado, porEmissor: saida);
  }

  static String _dia(DateTime d) => _diaUtc(d).toIso8601String().substring(0, 10);

  /// O dia civil de [d], à meia-noite em UTC: a data do formulário não tem
  /// hora, e o fuso da máquina não pode movê-la.
  static DateTime _diaUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
