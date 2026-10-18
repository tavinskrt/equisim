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
  static ShareholderControl? fromFca(String text) {
    final t = text.trim().toLowerCase();
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
  static const int version = 1;

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
    final rows = [
      for (final f in filings)
        if (ShareholderControl.fromFca(f.species) case final c?)
          (
            reference: _utcDay(f.reference),
            control: c,
            speciesDate: f.speciesDate == null ? null : _utcDay(f.speciesDate!),
          ),
    ]..sort((a, b) => a.reference.compareTo(b.reference));
    if (rows.isEmpty) return const [];
    final periods = <ShareholderControlPeriod>[
      ShareholderControlPeriod(
          since: rows.first.reference, control: rows.first.control),
    ];
    for (var i = 1; i < rows.length; i++) {
      final before = rows[i - 1];
      final now = rows[i];
      if (now.control == before.control) continue;
      // Um ano de calendário depois, e não 366 dias corridos.
      final ref = now.reference;
      final until = DateTime.utc(ref.year + 1, ref.month, ref.day);
      final candidates = [
        for (final l in rows)
          if (l.control == now.control && l.speciesDate != null)
            if (!l.speciesDate!.isBefore(before.reference) &&
                !l.speciesDate!.isAfter(until))
              l.speciesDate!,
      ]..sort();
      periods.add(ShareholderControlPeriod(
        since: candidates.isEmpty ? now.reference : candidates.first,
        control: now.control,
      ));
    }
    return periods;
  }

  /// A espécie de controle no dia de [asOf], ou `null` antes do primeiro
  /// trecho. A comparação é por dia civil, em UTC, como as datas do histórico.
  static ShareholderControl? at(
    List<ShareholderControlPeriod> periods,
    DateTime asOf,
  ) {
    final day = _utcDay(asOf);
    ShareholderControl? vale;
    for (final p in periods) {
      if (_utcDay(p.since).isAfter(day)) break;
      vale = p.control;
    }
    return vale;
  }

  /// O pacote: o histórico de cada emissor, pela raiz do código de
  /// negociação — a mesma chave do registro da B3.
  static Map<String, Object?> encode(
    Map<String, List<ShareholderControlPeriod>> byIssuer, {
    required DateTime generatedAt,
  }) =>
      {
        'versao': version,
        'geradoEm': _day(generatedAt),
        'fonte': 'Formulário Cadastral da CVM, Especie_Controle_Acionario',
        'emissores': {
          for (final e in (byIssuer.keys.toList()..sort()))
            e: [
              for (final p in byIssuer[e]!)
                {'desde': _day(p.since), 'controle': p.control.name},
            ],
        },
      };

  /// Lê o pacote; `null` quando a versão ou a forma não são as esperadas.
  static ({DateTime generatedAt, Map<String, List<ShareholderControlPeriod>> byIssuer})?
      decode(Map<String, dynamic> json) {
    if (json['versao'] != version) return null;
    final parsed = DateTime.tryParse(json['geradoEm'] as String? ?? '');
    final generated = parsed == null ? null : _utcDay(parsed);
    final issuers = json['emissores'];
    if (generated == null || issuers is! Map<String, dynamic>) return null;
    final output = <String, List<ShareholderControlPeriod>>{};
    for (final e in issuers.entries) {
      final list = e.value;
      if (list is! List) return null;
      final periods = <ShareholderControlPeriod>[];
      for (final p in list) {
        if (p is! Map<String, dynamic>) return null;
        final readOrdering = DateTime.tryParse(p['desde'] as String? ?? '');
        final since = readOrdering == null ? null : _utcDay(readOrdering);
        final control = ShareholderControl.values
            .where((c) => c.name == p['controle'])
            .firstOrNull;
        if (since == null || control == null) return null;
        periods.add(ShareholderControlPeriod(since: since, control: control));
      }
      periods.sort((a, b) => a.since.compareTo(b.since));
      output[e.key] = periods;
    }
    return (generatedAt: generated, byIssuer: output);
  }

  static String _day(DateTime d) => _utcDay(d).toIso8601String().substring(0, 10);

  /// O dia civil de [d], à meia-noite em UTC: a data do formulário não tem
  /// hora, e o fuso da máquina não pode movê-la.
  static DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
