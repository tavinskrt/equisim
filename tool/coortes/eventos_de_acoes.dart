// Os eventos de ações de uma companhia listada — desdobramento, grupamento e
// bonificação —, e o que eles fazem com a série da fonte e com a contagem por
// data das coortes (itens B29 e B30).
//
// **Quatro fontes, porque nenhuma basta.** O quadro de eventos do Formulário de
// Referência declara o fator pela contagem antes e depois, mas parou em 2022; o
// registro da B3 traz a data ex dos eventos recentes, e não de todos — a
// bonificação de 2024 da Klabin não está lá; o `DISMES` do COTAHIST marca todo
// evento, mas só se distingue de provento quando o fator é grande. A quarta é a
// contagem do próprio FRE: a mudança que nenhuma emissão por valor explica é
// candidata a evento, localizada no preço. Juntas, e sem repetir o mesmo
// evento, cobrem o que cada uma deixa de fora. **Candidato falso não custa
// nada**: evento só ajusta a série onde o salto dele está no preço.
//
// **O que a fonte de preços fez com cada um** se sabe pelo fator entre o
// fechamento bruto e o dela: no dia ex de um evento ajustado ele salta
// exatamente pelo fator, e no de um não ajustado fica parado. É uma conta sem
// ruído de mercado — os dois fechamentos andam juntos em todo pregão em que a
// fonte não mexeu —, e por isso quem tem o COTAHIST não precisa da regra do
// salto que o aplicativo usa (`CorporateEvents.completeAdjustment`).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import '../b3/proventos.dart';
import '../cvm/csv.dart';
import '../cvm/emissoes_fre.dart';

/// Os eventos de ações declarados e registrados, prontos para localizar.
class ShareEvents {
  ShareEvents._(this._declared, this._registry, this._count,
      this._issuances);

  /// Eventos do quadro do FRE, por CNPJ: aprovação e fator, distintos.
  final Map<String, List<({DateTime approval, double factor})>> _declared;

  /// Registro da B3, por raiz do código.
  final Map<String, B3Issuer> _registry;

  /// Mudanças da contagem do FRE, por CNPJ: data e razão.
  final Map<String, List<({DateTime date, double ratio, double before})>> _count;

  /// Emissões por valor do FRE, para separar a mudança de contagem que é
  /// emissão da que é evento de ações.
  final FreIssuances? _issuances;

  /// Lê o quadro de eventos do FRE e o registro da B3.
  ///
  /// Sem o FRE em disco, segue só com o registro e o `DISMES`: um evento a
  /// menos localizado é um ajuste a menos, e não um ajuste errado.
  static ShareEvents read({
    String freDir = 'data/cvm/fre',
    String registry = 'assets/b3/emissores.json',
    String listedCounts = 'data/b3/listadas_contagem.json',
    FreIssuances? issuances,
  }) {
    final declared = <String, List<({DateTime approval, double factor})>>{};
    final folder = Directory(freDir);
    if (folder.existsSync()) {
      final seen = <String>{};
      final files = folder
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'^fre_cia_aberta_capital_social_desdobramento_\d{4}\.csv$')
              .hasMatch(f.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        for (final r in readCvmCsv(f)) {
          final cnpj = r['CNPJ_Companhia'];
          final approval = DateTime.tryParse('${r['Data_Aprovacao']}T00:00:00Z');
          final before =
              double.tryParse(r['Quantidade_Total_Acoes_Antes_Aprovacao'] ?? '');
          final after =
              double.tryParse(r['Quantidade_Total_Acoes_Depois_Aprovacao'] ?? '');
          if (cnpj == null || approval == null || before == null || after == null) {
            continue;
          }
          if (before <= 0 || after <= 0) continue;
          // Fator de 1 não é evento de ações: é o formulário repetindo a
          // contagem. E o mesmo evento se repete em toda versão do formulário.
          if (math.log(after / before).abs() < 1e-6) continue;
          if (!seen.add('$cnpj|${_day(approval)}|$before|$after')) continue;
          (declared[cnpj] ??= []).add((approval: approval, factor: after / before));
        }
      }
    }
    final file = File(registry);
    final b3 = file.existsSync()
        ? B3RegistryCodec.decodePackage(
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        : const <String, B3Issuer>{};
    final count = <String, List<({DateTime date, double ratio, double before})>>{};
    final countFile = File(listedCounts);
    if (countFile.existsSync()) {
      final json = jsonDecode(countFile.readAsStringSync()) as Map<String, dynamic>;
      for (final e in json.entries) {
        final points = [
          for (final p in ((e.value as Map<String, dynamic>)['contagem'] as List)
              .cast<Map<String, dynamic>>())
            (
              since: DateTime.parse('${p['desde']}T00:00:00Z'),
              shares: (p['acoes'] as num).toDouble(),
            ),
        ]..sort((a, b) => a.since.compareTo(b.since));
        final changes = <({DateTime date, double ratio, double before})>[];
        for (var i = 1; i < points.length; i++) {
          final a = points[i - 1].shares, b = points[i].shares;
          if (a > 0 && b > 0 && math.log(b / a).abs() > 1e-6) {
            changes.add((date: points[i].since, ratio: b / a, before: a));
          }
        }
        if (changes.isNotEmpty) count[e.key] = changes;
      }
    }
    return ShareEvents._(declared, b3, count, issuances);
  }

  /// Os eventos de ações de [ticker], localizados no fechamento bruto dele.
  ///
  /// O mesmo evento vindo de duas fontes entra uma vez: dois eventos a até
  /// quinze dias um do outro são o mesmo, e dois de mesmo fator a até 120 dias
  /// também — a aprovação e a data ex de uma bonificação podem estar meses
  /// separadas, e a contagem do FRE a localiza na primeira troca de `DISMES`.
  /// Vale a fonte que chegou antes: o quadro do FRE e o registro da B3 dão a
  /// data ex; a contagem, só uma aproximação.
  ///
  /// [withCount] falso deixa de fora a quarta fonte — a mudança de contagem
  /// do FRE —, para quem quer explicar justamente a contagem.
  List<ShareEvent> ofSecurity({
    required String? cnpj,
    required String ticker,
    required List<TradingDay> rawSessions,
    bool withCount = true,
  }) {
    final raw = [for (final p in rawSessions) p.raw];
    final out = <ShareEvent>[];
    void merge(ShareEvent e) {
      final repeatedEvent = out.any((x) {
        final days = x.exDate.difference(e.exDate).inDays.abs();
        return days <= 15 ||
            (days <= 120 &&
                (math.log(x.factor) - math.log(e.factor)).abs() < 0.02);
      });
      if (!repeatedEvent) out.add(e);
    }

    // **Cada fonte com a sua prova** (decisão 136). O quadro do FRE declara o
    // fator e a aprovação, não a data ex: ela é o pregão em que o preço
    // confirma — a primeira troca de `DISMES` depois da aprovação, que é o que
    // `CorporateEvents.locate` devolve para fator pequeno, é muitas vezes um
    // provento, e a ASAI3 ganhava um evento de 0,935 num dia qualquer.
    for (final d in _declared[cnpj] ?? const <({DateTime approval, double factor})>[]) {
      final ev = _locateInPrice(rawSessions, d.approval, d.factor);
      if (ev != null) merge(ev);
    }
    // O registro repete o evento por classe e por consulta — a BBAS3 de 2018
    // tem fator 2 no preço e produto 8 no registro: um por data.
    final root = ticker.length >= 4 ? ticker.substring(0, 4) : ticker;
    final dates = <String>{};
    for (final e in _registry[root]?.events ?? const <OfficialShareEvent>[]) {
      if (!(e.factor > 0) || !e.factor.isFinite) continue;
      if (!dates.add(_day(e.exDate))) continue;
      merge(ShareEvent(
          exDate: DateTime.utc(e.exDate.year, e.exDate.month, e.exDate.day),
          factor: e.factor,
          observedRatio: 1 / e.factor));
    }
    // O `DISMES` com salto grande só é evento de ações se a contagem mudou
    // junto: a SYNE3 caiu 47% em 09/12/2024, com troca de `DISMES`, numa
    // redução de capital com devolução em dinheiro — e a contagem do FRE não
    // se moveu. Tomada por desdobramento, ela dobrava o retorno de quem a
    // atravessava.
    final changes = _count[cnpj] ??
        const <({DateTime date, double ratio, double before})>[];
    for (final ev in CorporateEvents.detect(raw)) {
      final countChanged = changes.any((m) =>
          m.date.difference(ev.exDate).inDays.abs() <= 400 &&
          (math.log(m.ratio) - math.log(ev.factor)).abs() < 0.1);
      if (countChanged) merge(ev);
    }
    // A mudança de contagem que nenhuma emissão por valor explica: aumento de
    // 3% ou mais — bonificação, desdobramento —, ou redução à metade ou menos
    // — grupamento. Redução pequena é cancelamento de tesouraria, e não
    // evento. **Só entra se o preço a confirma** — troca de `DISMES` com o
    // salto do fator —, e não pelo primeiro salto parecido: a AMER3 caiu 38%
    // em 16/01/2023, na semana da fraude, e isso casava com uma mudança de
    // contagem de 1,62.
    if (!withCount) {
      out.sort((a, b) => a.exDate.compareTo(b.exDate));
      return out;
    }
    final issued = cnpj == null || _issuances == null
        ? const <ShareIssue>[]
        : _issuances.known(cnpj, DateTime.utc(2100));
    for (final m in changes) {
      if (!(m.ratio >= 1.03 || m.ratio <= 0.5)) continue;
      final newShares = m.before * (m.ratio - 1);
      final isIssuance = issued.any((i) =>
          i.date.difference(m.date).inDays.abs() <= 60 &&
          (i.shares / newShares - 1).abs() < 0.05);
      if (isIssuance) continue;
      final ev = _locateInPrice(rawSessions, m.date, m.ratio);
      if (ev != null) merge(ev);
    }
    out.sort((a, b) => a.exDate.compareTo(b.exDate));
    return out;
  }
}

/// Os eventos que a fonte de preços **não** ajustou, com a data ex em que o
/// salto está (item B29).
///
/// Para cada evento, procura a dez dias da data dada o pregão em que o bruto
/// salta pelo fator. Se nele o fator entre o bruto e a fonte também salta pelo
/// fator, a fonte ajustou; se fica parado, não ajustou, e o evento sai com esse
/// dia. Sem pregão que case — evento mal localizado, papel suspenso —, o evento
/// não sai: ajustar num dia errado inventaria o salto que se quer tirar.
List<ShareEvent> notAdjustedBySource(
  PriceSeries source,
  List<TradingDay> rawSessions,
  List<ShareEvent> events,
) {
  if (events.isEmpty || rawSessions.length < 2 || source.isEmpty) return const [];
  final fromSource = <String, double>{
    for (final p in source.points)
      if (p.close > 0) _day(p.date): p.close,
  };
  final out = <ShareEvent>[];
  for (final e in events) {
    final q = e.factor;
    // Abaixo de 2% o salto do evento não se separa de um pregão comum, e o
    // efeito dele na série é desse tamanho.
    if (!(q > 0) || !q.isFinite || math.log(q).abs() < 0.02) continue;
    final margin = math.log(q).abs() < math.log(1.6) ? 0.04 : 0.08;
    var adjusted = false;
    DateTime? unadjustedDay;
    for (var i = 1; i < rawSessions.length; i++) {
      final b = rawSessions[i], a = rawSessions[i - 1];
      final days = b.date.difference(e.exDate).inDays;
      if (days < -10) continue;
      if (days > 10) break;
      if (b.date.difference(a.date).inDays > 7) continue;
      final fa = fromSource[_day(a.date)], fb = fromSource[_day(b.date)];
      if (fa == null || fb == null || !(a.close > 0) || !(b.close > 0)) continue;
      final rawJump = math.log(b.close / a.close);
      final factorStep = math.log((b.close / fb) / (a.close / fa));
      if ((factorStep + math.log(q)).abs() < 0.01) {
        adjusted = true;
        break;
      }
      // Sem ajuste: o fator parado, o bruto caindo pelo fator e o `DISMES`
      // trocando no dia — sem a troca, uma queda comum de mercado passaria.
      if (factorStep.abs() < 0.005 &&
          b.distribution != a.distribution &&
          (rawJump + math.log(q)).abs() < margin) {
        unadjustedDay ??= b.date;
      }
    }
    if (!adjusted && unadjustedDay != null) {
      out.add(ShareEvent(
          exDate: DateTime.utc(
              unadjustedDay.year, unadjustedDay.month, unadjustedDay.day),
          factor: q,
          observedRatio: e.observedRatio));
    }
  }
  return out;
}

/// A contagem do FRE em [t] com os eventos que ele ainda não absorveu
/// (item B30).
///
/// O quadro de eventos do FRE parou em 2022, e daí em diante a contagem só muda
/// quando a companhia corrige o formulário — o que pode levar mais de um ano.
/// Enquanto isso a coorte dividia pela contagem de antes do evento, com o preço
/// de depois: a BBAS3 de 30/06/2024 saía com metade do valor de mercado e o
/// dobro do potencial.
///
/// **Só age quando a contagem está parada**: nenhuma mudança, por fator
/// nenhum, de 400 dias antes do evento até a data. Se ela mudou, o formulário
/// tratou o evento — a aprovação costuma vir antes da data ex, e às vezes
/// junto com outra operação —, e a contagem fica como veio.
({double? shares, List<ShareEvent> applied}) sharesWithEvents(
  List<({DateTime since, double shares})> count,
  DateTime t,
  List<ShareEvent> events,
) {
  final day = DateTime.utc(t.year, t.month, t.day);
  if (count.isEmpty) return (shares: null, applied: const []);
  // A contagem precisa cobrir a data do evento: um evento anterior ao primeiro
  // formulário — o registro da B3 guarda eventos de 1989 — já está nela.
  final start = count.first.since;
  double? shares;
  double? previous;
  final changes = <({DateTime date, double ratio})>[];
  for (final p in count) {
    if (p.since.isAfter(day)) break;
    if (previous != null && previous > 0 && p.shares > 0) {
      final r = p.shares / previous;
      if (math.log(r).abs() > 1e-6) {
        changes.add((date: p.since, ratio: r));
      }
    }
    previous = p.shares;
    shares = p.shares;
  }
  if (shares == null) return (shares: null, applied: const []);
  final applied = <ShareEvent>[];
  var adjusted = shares;
  for (final e in events) {
    final ex = DateTime.utc(e.exDate.year, e.exDate.month, e.exDate.day);
    if (ex.isAfter(day)) continue;
    if (!(e.factor > 0) || math.log(e.factor).abs() < 0.02) continue;
    // Só evento recente: a contagem do FRE começa em 2010, e o valor dela já
    // traz os eventos anteriores — uma data de aprovação antiga no primeiro
    // ponto não quer dizer contagem de antes do evento. Três anos cobrem com
    // folga o atraso de correção medido.
    if (ex.isBefore(DateTime.utc(2011)) ||
        ex.isBefore(DateTime.utc(day.year - 3, day.month, day.day))) {
      continue;
    }
    if (!start.isBefore(ex)) continue;
    // **Parada de verdade**: nenhuma mudança da contagem, por fator nenhum, de
    // 400 dias antes do evento até a data. Se ela mudou, o formulário tratou o
    // evento, ainda que junto com outra coisa — a AERI3 registrou o grupamento
    // de 20 para 1 antes da data ex e junto com uma emissão, com razão 0,081,
    // e aplicar o evento de novo tirava 95% do valor de mercado.
    final moved = changes.any((m) =>
        m.date.isAfter(ex.subtract(const Duration(days: 400))));
    if (moved) continue;
    adjusted *= e.factor;
    applied.add(e);
  }
  return (shares: adjusted, applied: applied);
}

/// O pregão, de 30 dias antes de [d] a 150 depois, em que o `DISMES` troca e o
/// fechamento bruto se divide pelo fator [q]; `null` sem ele.
ShareEvent? _locateInPrice(List<TradingDay> rawSessions, DateTime d, double q) {
  final margin = math.log(q).abs() < math.log(1.6) ? 0.06 : 0.08;
  for (var i = 1; i < rawSessions.length; i++) {
    final b = rawSessions[i], a = rawSessions[i - 1];
    final days = b.date.difference(d).inDays;
    if (days < -30) continue;
    if (days > 150) break;
    if (b.date.difference(a.date).inDays > 7) continue;
    if (b.distribution == a.distribution) continue;
    if (!(a.close > 0) || !(b.close > 0)) continue;
    final ratio = b.close / a.close;
    if ((math.log(ratio) + math.log(q)).abs() < margin) {
      return ShareEvent(
          exDate: DateTime.utc(b.date.year, b.date.month, b.date.day),
          factor: q,
          observedRatio: ratio);
    }
  }
  return null;
}

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

/// As variações de capital do FRE que nenhum evento de ações explica, como
/// emissões **sem valor declarado** (item B28): a cascata não as soma, e diz
/// quanto o preço justo mudaria se fossem emissão por valor.
///
/// A bonificação também aumenta o capital — capitaliza reserva —, e o que a
/// separa da emissão é o registro da B3, quando ele a tem, ou o preço: no dia
/// ex, o fechamento bruto se divide pela razão entre as contagens, e o `DISMES`
/// do COTAHIST troca. Uma queda comum de
/// mercado não troca o `DISMES`, e um provento troca mas não cai pela razão. A
/// busca vai de 30 dias antes da aprovação a 150 depois — a data ex costuma vir
/// depois dela, e a contagem do FRE às vezes é corrigida antes. A KLBN11 de
/// 2024 aparece no FRE como R$ 1,6 bilhão de capital com 10% de ações novas:
/// é a bonificação de 07/05/2024, com o bruto caindo 7,6% e o `DISMES` trocando
/// no dia, e fica de fora.
///
/// - [events]: os eventos do quadro do FRE, do registro da B3 e do `DISMES` —
///   **sem** a mudança de contagem, que se explicaria a si mesma.
List<ShareIssue> issuancesWithoutEvent(
  List<({ShareIssue issuance, double ratio})> candidates,
  List<TradingDay> rawSessions,
  List<ShareEvent> events,
) =>
    [
      for (final c in candidates)
        if (!_eventJump(rawSessions, c.issuance.date, c.ratio) &&
            !events.any((e) =>
                e.exDate.difference(c.issuance.date).inDays.abs() <= 150 &&
                (math.log(e.factor) - math.log(c.ratio)).abs() < 0.03))
          ShareIssue(
            date: c.issuance.date,
            amount: c.issuance.amount,
            shares: c.issuance.shares,
            declared: false,
          ),
    ];

bool _eventJump(List<TradingDay> rawSessions, DateTime d, double q) {
  // Com a troca de `DISMES` exigida, a folga pode ser a da detecção: a
  // bonificação de 20% da POMO4 caiu 20% no dia ex, e não 16,7%.
  final margin = math.log(q).abs() < math.log(1.6) ? 0.06 : 0.08;
  for (var i = 1; i < rawSessions.length; i++) {
    final b = rawSessions[i], a = rawSessions[i - 1];
    final days = b.date.difference(d).inDays;
    if (days < -30) continue;
    if (days > 150) break;
    if (b.date.difference(a.date).inDays > 7) continue;
    if (b.distribution == a.distribution) continue;
    if (!(a.close > 0) || !(b.close > 0)) continue;
    if ((math.log(b.close / a.close) + math.log(q)).abs() < margin) return true;
  }
  return false;
}
