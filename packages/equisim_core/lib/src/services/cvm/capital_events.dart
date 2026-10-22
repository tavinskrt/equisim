/// O que muda o capital de uma companhia **depois** do balanço, e como o
/// aplicativo o recebe (itens B28 e B29).
///
/// Duas listas por ativo, e as duas saem do Formulário de Referência da CVM,
/// conferidas contra o COTAHIST:
///
/// - **emissões por valor** ([ShareIssue]): o capital que entrou e não está no
///   último balanço — a cascata o soma ao patrimônio da ponte;
/// - **eventos de ações** ([ShareEvent]): desdobramento, grupamento e
///   bonificação, com a data ex — o preparo completa com eles o ajuste que a
///   fonte de preços deixou de fazer.
library;

import '../../entities/share_issue.dart';
import '../../value_objects/money.dart';
import '../b3/corporate_events.dart';

/// Emissões e eventos de ações de um ativo.
class CapitalEvents {
  /// Emissões por valor, em ordem de data.
  final List<ShareIssue> issues;

  /// Eventos de ações, em ordem de data ex.
  final List<ShareEvent> shareEvents;

  /// Declara as duas listas.
  const CapitalEvents({this.issues = const [], this.shareEvents = const []});

  /// Nenhuma das duas listas tem entrada.
  bool get isEmpty => issues.isEmpty && shareEvents.isEmpty;
}

/// Lê e grava o pacote de eventos de capital.
abstract final class CapitalEventsCodec {
  /// Versão do formato do pacote. A 2 grava o valor da emissão em centavos
  /// inteiros, e não em reais.
  static const int version = 2;

  /// Grava o pacote.
  static Map<String, Object> encodePackage(
    Map<String, CapitalEvents> byTicker, {
    required DateTime generatedAt,
  }) {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    return {
      'versao': version,
      'geradoEm': day(generatedAt),
      'ativos': {
        for (final e
            in (byTicker.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          if (!e.value.isEmpty)
            e.key: {
              'emissoes': [
                for (final i
                    in (e.value.issues.toList()
                      ..sort((a, b) => a.date.compareTo(b.date))))
                  {
                    'data': day(i.date),
                    'centavos': i.amount.cents,
                    'acoes': i.shares,
                    if (!i.declared) 'declarada': false,
                  },
              ],
              'eventos': [
                for (final v
                    in (e.value.shareEvents.toList()
                      ..sort((a, b) => a.exDate.compareTo(b.exDate))))
                  {'dataEx': day(v.exDate), 'fator': v.factor},
              ],
            },
      },
    };
  }

  /// Lê o pacote. Entrada malformada é **pulada**, e não derruba a leitura: um
  /// ativo sem emissão lida é avaliado com o patrimônio do balanço, que é o
  /// comportamento anterior.
  static Map<String, CapitalEvents> decodePackage(Map<String, dynamic> package) {
    final out = <String, CapitalEvents>{};
    final assets = package['ativos'];
    if (assets is! Map) return out;
    DateTime? date(Object? x) => x is String ? DateTime.tryParse(x) : null;
    double? number(Object? x) => x is num ? x.toDouble() : null;
    // Quantidade de ação é inteira: fração na fonte é entrada malformada.
    int? whole(Object? x) => x is int
        ? x
        : x is double && x.isFinite && (x - x.roundToDouble()).abs() < 1e-9
        ? x.round()
        : null;
    for (final e in assets.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final issuances = <ShareIssue>[];
      final list = v['emissoes'];
      if (list is List) {
        for (final x in list) {
          if (x is! Map) continue;
          final d = date(x['data']);
          final cents = x['centavos'];
          final shares = whole(x['acoes']);
          if (d == null || cents is! int || shares == null) continue;
          final i = ShareIssue(
            date: d,
            amount: Money(cents),
            shares: shares,
            declared: x['declarada'] != false,
          );
          if (i.isUsable) issuances.add(i);
        }
      }
      final events = <ShareEvent>[];
      final eventList = v['eventos'];
      if (eventList is List) {
        for (final x in eventList) {
          if (x is! Map) continue;
          final d = date(x['dataEx']);
          final f = number(x['fator']);
          if (d == null || f == null || !f.isFinite || f <= 0) continue;
          events.add(ShareEvent(exDate: d, factor: f, observedRatio: 1 / f));
        }
      }
      final c = CapitalEvents(issues: issuances, shareEvents: events);
      if (!c.isEmpty) out['${e.key}'] = c;
    }
    return out;
  }
}
