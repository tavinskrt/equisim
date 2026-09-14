/// Registro de empresas listadas da B3: contagem oficial de ações e eventos.
///
/// **De onde vem.** A página de empresas listadas da B3 é servida por um
/// endpoint que devolve, por emissor, a quantidade de ações por classe e os
/// eventos societários com fator e data-com. É o **registro declarado** que o
/// item A3.1 pedia: o fator do evento vem escrito, e não inferido do preço como
/// em `CorporateEvents` (decisão 75).
///
/// **Duas convenções de fator, conferidas contra o preço.** Sobre os eventos de
/// 2010 em diante dos 297 emissores do universo, confrontados com a razão de
/// fechamento do COTAHIST na data ex (14/09/2026):
///
/// | rótulo | o fator é | exemplo |
/// |---|---|---|
/// | `DESDOBRAMENTO` | **acréscimo percentual** | `900` = 1 para 10 |
/// | `BONIFICACAO` | **acréscimo percentual** | `25` = +25% |
/// | `GRUPAMENTO` | **multiplicador** | `0,05` = 20 para 1 |
///
/// **E os eventos da mesma data se compõem.** A B3 escreve um desdobramento de
/// 1 para 2 como grupamento de 10 para 1 **e** desdobramento de 1 para 20, no
/// mesmo dia — CPFE3 em 2011, VIVT3 e TIMS3 em 2025. Lido evento a evento, o
/// fator erra por 10x ou 100x; composto, bate com o preço em **93,4% de 243
/// eventos a 15%**, e o que sobra é o mercado andando no dia do grupamento de
/// papel em crise, e par incompleto no próprio registro.
///
/// **O que o registro não diz.** Só emissor listado hoje: companhia deslistada
/// não está lá, e para ela a inferência pelo preço continua sendo a fonte.
/// Cisão, incorporação e resgate trazem fator em outra convenção e não mudam a
/// contagem do mesmo papel de forma multiplicativa — ficam de fora.
library;

import '../../time/brazilian_calendar.dart';

/// Um evento de ações declarado pela B3, já composto por data e ISIN.
class OfficialShareEvent {
  /// ISIN do papel afetado.
  final String isin;

  /// Último dia com direito — a data-com.
  final DateTime lastDateWithRights;

  /// Primeiro dia útil depois da data-com: a data ex.
  final DateTime exDate;

  /// Ações depois ÷ ações antes, composto sobre os eventos do mesmo dia.
  final double factor;

  /// Rótulos que compuseram o fator, na ordem do registro.
  final List<String> labels;

  /// Declara o evento.
  const OfficialShareEvent({
    required this.isin,
    required this.lastDateWithRights,
    required this.exDate,
    required this.factor,
    required this.labels,
  });
}

/// Um emissor no registro.
class B3Issuer {
  /// Código de quatro letras — `PETR` para PETR3 e PETR4.
  final String code;

  /// Quantidade total de ações emitidas, **com as em tesouraria**.
  ///
  /// Conferido em 14/09/2026 contra o capital integralizado declarado à CVM:
  /// bate com o total em 260 de 293 emissores, e com o total líquido de
  /// tesouraria em 3.
  final double? totalShares;

  /// Ações ordinárias.
  final double? commonShares;

  /// Ações preferenciais.
  final double? preferredShares;

  /// Dia em que o registro foi consultado. A contagem é a desse dia.
  final DateTime consultedOn;

  /// Eventos de ações, em ordem de data ex.
  final List<OfficialShareEvent> events;

  /// Declara o emissor.
  const B3Issuer({
    required this.code,
    required this.totalShares,
    required this.commonShares,
    required this.preferredShares,
    required this.consultedOn,
    required this.events,
  });

  /// Eventos com data ex em `(depois, ate]`, compostos num fator só — o que
  /// transforma uma contagem de [depois] na base de [ate].
  ///
  /// Só eventos do [isin] informado: classes do mesmo emissor podem ter
  /// eventos diferentes.
  double factorBetween(String isin, DateTime depois, DateTime ate) {
    final d = DateTime.utc(depois.year, depois.month, depois.day);
    final a = DateTime.utc(ate.year, ate.month, ate.day);
    var f = 1.0;
    for (final e in events) {
      if (e.isin != isin) continue;
      if (e.exDate.isAfter(d) && !e.exDate.isAfter(a)) f *= e.factor;
    }
    return f;
  }
}

/// Leitura do registro.
abstract final class B3Registry {
  /// Número no formato da B3: ponto de milhar e vírgula decimal —
  /// `5.730.834.040`, `0,05000000000`.
  static double? parseNumber(Object? v) {
    if (v is num) return v.toDouble();
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));
  }

  /// Data no formato `dd/mm/aaaa`.
  static DateTime? parseDate(Object? v) {
    if (v is! String) return null;
    final p = v.trim().split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]), m = int.tryParse(p[1]), a = int.tryParse(p[2]);
    if (d == null || m == null || a == null) return null;
    return DateTime.utc(a, m, d);
  }

  /// Ações depois ÷ ações antes para um evento, ou `null` quando o rótulo não
  /// muda a contagem de forma multiplicativa.
  static double? multiplier(String label, double factor) {
    if (!factor.isFinite || factor <= 0) return null;
    return switch (label) {
      'DESDOBRAMENTO' || 'BONIFICACAO' => 1 + factor / 100,
      'GRUPAMENTO' => factor,
      _ => null,
    };
  }

  /// Eventos de ações de uma lista `stockDividends`, compostos por ISIN e
  /// data-com.
  ///
  /// O registro repete o mesmo evento uma vez por papel emitido (`assetIssued`)
  /// — um grupamento de ON aparece para cada recibo e direito ligado a ela.
  /// Entradas idênticas em ISIN, data, rótulo e fator contam uma vez.
  static List<OfficialShareEvent> events(List<Object?> stockDividends) {
    final vistos = <String>{};
    final porChave = <String, ({String isin, DateTime dataCom, List<String> rotulos, double fator})>{};
    for (final raw in stockDividends) {
      if (raw is! Map<String, dynamic>) continue;
      final label = raw['label'];
      final isin = raw['isinCode'];
      final dataCom = parseDate(raw['lastDatePrior']);
      final bruto = parseNumber(raw['factor']);
      if (label is! String || isin is! String || isin.isEmpty) continue;
      if (dataCom == null || bruto == null) continue;
      final m = multiplier(label, bruto);
      if (m == null) continue;
      if (!vistos.add('$isin|${dataCom.toIso8601String()}|$label|${raw['factor']}')) {
        continue;
      }
      final chave = '$isin|${dataCom.toIso8601String()}';
      final antes = porChave[chave];
      porChave[chave] = antes == null
          ? (isin: isin, dataCom: dataCom, rotulos: [label], fator: m)
          : (
              isin: isin,
              dataCom: dataCom,
              rotulos: [...antes.rotulos, label],
              fator: antes.fator * m,
            );
    }
    final out = [
      for (final e in porChave.values)
        OfficialShareEvent(
          isin: e.isin,
          lastDateWithRights: e.dataCom,
          exDate: _proximoDiaUtil(e.dataCom),
          factor: e.fator,
          labels: List.unmodifiable(e.rotulos),
        ),
    ]..sort((a, b) => a.exDate.compareTo(b.exDate));
    return List.unmodifiable(out);
  }

  /// Um emissor a partir da resposta do endpoint, ou `null` sem código.
  static B3Issuer? issuer(Map<String, dynamic> json, {required DateTime consultedOn}) {
    final code = json['code'];
    if (code is! String || code.trim().isEmpty) return null;
    final eventos = json['stockDividends'];
    return B3Issuer(
      code: code.trim(),
      totalShares: _positivo(parseNumber(json['totalNumberShares'])),
      commonShares: parseNumber(json['numberCommonShares']),
      preferredShares: parseNumber(json['numberPreferredShares']),
      consultedOn: DateTime.utc(consultedOn.year, consultedOn.month, consultedOn.day),
      events: eventos is List ? events(eventos) : const [],
    );
  }

  static double? _positivo(double? v) => v != null && v > 0 ? v : null;

  static DateTime _proximoDiaUtil(DateTime d) {
    var x = DateTime.utc(d.year, d.month, d.day + 1);
    while (!BrazilianCalendar.isBusinessDay(x, knownAt: d)) {
      x = DateTime.utc(x.year, x.month, x.day + 1);
    }
    return x;
  }
}

/// Formato de pacote do registro, para empacotar no aplicativo.
///
/// Mora no núcleo pela mesma razão do `CvmDocumentCodec`: a ferramenta que
/// grava e o repositório que lê precisam concordar sobre o formato, e duas
/// cópias divergiriam em silêncio.
abstract final class B3RegistryCodec {
  /// Versão do formato. Muda quando uma chave muda de significado.
  static const int versao = 1;

  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _data(Object? v) {
    if (v is! String || v.length < 10) return null;
    final p = v.substring(0, 10).split('-');
    if (p.length != 3) return null;
    final a = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (a == null || m == null || d == null) return null;
    return DateTime.utc(a, m, d);
  }

  /// O pacote inteiro.
  static Map<String, Object> encodePackage(
    Iterable<B3Issuer> emissores, {
    required DateTime geradoEm,
  }) =>
      {
        'versao': versao,
        'geradoEm': _dia(geradoEm),
        'emissores': {
          for (final e in emissores)
            e.code: {
              'consultadoEm': _dia(e.consultedOn),
              if (e.totalShares != null) 'total': e.totalShares!,
              if (e.commonShares != null) 'on': e.commonShares!,
              if (e.preferredShares != null) 'pn': e.preferredShares!,
              'eventos': [
                for (final x in e.events)
                  {
                    'isin': x.isin,
                    'dataCom': _dia(x.lastDateWithRights),
                    'dataEx': _dia(x.exDate),
                    'fator': x.factor,
                    'rotulos': x.labels,
                  },
              ],
            },
        },
      };

  /// Lê o pacote. Versão desconhecida devolve mapa vazio: formato que o leitor
  /// não entende não é lido pela metade.
  static Map<String, B3Issuer> decodePackage(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return const {};
    final emissores = pacote['emissores'];
    if (emissores is! Map<String, dynamic>) return const {};
    final out = <String, B3Issuer>{};
    for (final e in emissores.entries) {
      final v = e.value;
      if (v is! Map<String, dynamic>) continue;
      final consultado = _data(v['consultadoEm']);
      if (consultado == null) continue;
      final eventos = <OfficialShareEvent>[];
      final brutos = v['eventos'];
      if (brutos is List) {
        for (final x in brutos) {
          if (x is! Map<String, dynamic>) continue;
          final isin = x['isin'];
          final com = _data(x['dataCom']);
          final ex = _data(x['dataEx']);
          final fator = (x['fator'] as num?)?.toDouble();
          final rotulos = x['rotulos'];
          if (isin is! String || com == null || ex == null) continue;
          if (fator == null || !fator.isFinite || fator <= 0) continue;
          eventos.add(OfficialShareEvent(
            isin: isin,
            lastDateWithRights: com,
            exDate: ex,
            factor: fator,
            labels: rotulos is List
                ? List.unmodifiable(rotulos.whereType<String>())
                : const [],
          ));
        }
      }
      out[e.key] = B3Issuer(
        code: e.key,
        totalShares: (v['total'] as num?)?.toDouble(),
        commonShares: (v['on'] as num?)?.toDouble(),
        preferredShares: (v['pn'] as num?)?.toDouble(),
        consultedOn: consultado,
        events: List.unmodifiable(eventos
          ..sort((a, b) => a.exDate.compareTo(b.exDate))),
      );
    }
    return out;
  }
}
