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
  static const int versao = 2;

  /// Grava o pacote.
  static Map<String, Object> encodePackage(
    Map<String, CapitalEvents> porTicker, {
    required DateTime geradoEm,
  }) {
    String dia(DateTime d) => d.toIso8601String().substring(0, 10);
    return {
      'versao': versao,
      'geradoEm': dia(geradoEm),
      'ativos': {
        for (final e
            in (porTicker.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          if (!e.value.isEmpty)
            e.key: {
              'emissoes': [
                for (final i
                    in (e.value.issues.toList()
                      ..sort((a, b) => a.date.compareTo(b.date))))
                  {
                    'data': dia(i.date),
                    'centavos': i.amount.cents,
                    'acoes': i.shares,
                    if (!i.declared) 'declarada': false,
                  },
              ],
              'eventos': [
                for (final v
                    in (e.value.shareEvents.toList()
                      ..sort((a, b) => a.exDate.compareTo(b.exDate))))
                  {'dataEx': dia(v.exDate), 'fator': v.factor},
              ],
            },
      },
    };
  }

  /// Lê o pacote. Entrada malformada é **pulada**, e não derruba a leitura: um
  /// ativo sem emissão lida é avaliado com o patrimônio do balanço, que é o
  /// comportamento anterior.
  static Map<String, CapitalEvents> decodePackage(Map<String, dynamic> pacote) {
    final out = <String, CapitalEvents>{};
    final ativos = pacote['ativos'];
    if (ativos is! Map) return out;
    DateTime? data(Object? x) => x is String ? DateTime.tryParse(x) : null;
    double? numero(Object? x) => x is num ? x.toDouble() : null;
    // Quantidade de ação é inteira: fração na fonte é entrada malformada.
    int? inteiro(Object? x) => x is int
        ? x
        : x is double && x.isFinite && (x - x.roundToDouble()).abs() < 1e-9
        ? x.round()
        : null;
    for (final e in ativos.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final emissoes = <ShareIssue>[];
      final lista = v['emissoes'];
      if (lista is List) {
        for (final x in lista) {
          if (x is! Map) continue;
          final d = data(x['data']);
          final centavos = x['centavos'];
          final acoes = inteiro(x['acoes']);
          if (d == null || centavos is! int || acoes == null) continue;
          final i = ShareIssue(
            date: d,
            amount: Money(centavos),
            shares: acoes,
            declared: x['declarada'] != false,
          );
          if (i.isUsable) emissoes.add(i);
        }
      }
      final eventos = <ShareEvent>[];
      final lista2 = v['eventos'];
      if (lista2 is List) {
        for (final x in lista2) {
          if (x is! Map) continue;
          final d = data(x['dataEx']);
          final f = numero(x['fator']);
          if (d == null || f == null || !f.isFinite || f <= 0) continue;
          eventos.add(ShareEvent(exDate: d, factor: f, observedRatio: 1 / f));
        }
      }
      final c = CapitalEvents(issues: emissoes, shareEvents: eventos);
      if (!c.isEmpty) out['${e.key}'] = c;
    }
    return out;
  }
}
