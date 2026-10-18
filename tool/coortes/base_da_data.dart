// A ponte por papel na data da coorte (item C3).
//
// **Dois defeitos da montagem das coortes, e um é a causa do outro.**
//
// 1. **O preço da coorte estava na base de ações de hoje.** A fonte publica o
//    fechamento ajustado por todo evento de ações até hoje, e a coorte o
//    multiplicava pela contagem do exercício, que está na base daquele ano. A
//    MGLU3 de 30/09/2020 entrava a R$ 212,38: o fechamento do dia foi R$ 84,95,
//    e o desdobramento de 4 para 1 de outubro de 2020 e o grupamento de 10 para
//    1 de 2024 o levaram à base de hoje. O valor de mercado da coorte saía
//    errado pelo produto dos eventos posteriores — o mesmo fator no potencial
//    e no book-to-market —, e o volume da fonte, que não é ajustado, dava à
//    Porta 0 um financeiro errado pelo mesmo fator. Conferido em 15/09/2026:
//    697 de 2.247 observações das listadas com fechamento no COTAHIST estavam
//    fora da base da data por mais de 2%, e 386 por mais de 1,5 vez.
// 2. **A razão de unidade e o divisor colapsavam por construção** (limitações
//    §3.5): com `valor de mercado = contagem × preço` e a mesma contagem como
//    corrente, a unit saía com `u = 1` e as duas candidatas a divisor, iguais.
//
// **O que a coorte passa a montar**, para listada e deslistada:
//
// - a série de preço **na base da data**: a da fonte vezes o fator
//   `fechamento bruto ÷ fechamento da fonte` medido no último pregão até a
//   data, e o volume refeito do financeiro do COTAHIST;
// - a contagem de ações **da data**, do Formulário de Referência (A3.4), como
//   contagem corrente e como a contagem oficial que arbitra o divisor — o papel
//   que o registro da B3 tem no aplicativo;
// - o valor de mercado **da companhia**, espécie a espécie: a contagem de
//   ordinárias e de preferenciais vezes o fechamento bruto do papel mais
//   negociado de cada uma. É a convenção em que a unit mede `u` ações.
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import '../b3/proventos.dart';

/// Espécie de um papel pelo número do ticker.
enum ShareKind { common, preferred, unit }

/// `common` para 3, `preferred` de 4 a 8, `unit` para 11; `null` para o
/// resto — recibo, bônus, BDR.
ShareKind? kindOf(String ticker) {
  if (ticker.length < 5) return null;
  final n = int.tryParse(ticker.substring(4));
  if (n == null) return null;
  if (n == 3) return ShareKind.common;
  if (n >= 4 && n <= 8) return ShareKind.preferred;
  if (n == 11) return ShareKind.unit;
  return null;
}

/// Os códigos de uma companhia: os conhecidos e, para a raiz de quatro letras
/// de cada um, os das espécies e da unit — `3` a `8` e `11`.
///
/// A FCA nem sempre declara o código de cada espécie: a Alupar declara só a
/// ALUP11, e a ALUP3 e a ALUP4 negociam. O papel que não existe simplesmente
/// não tem pregão no COTAHIST.
Set<String> companyCodes(Iterable<String> known) => {
      for (final c in known) ...{
        c,
        if (c.length > 4)
          for (final n in const ['3', '4', '5', '6', '7', '8', '11'])
            '${c.substring(0, 4)}$n',
      },
    };

/// Pregões de [ticker] encadeados pelos códigos anteriores da mesma espécie.
///
/// A fonte publica a série inteira sob o código de hoje; o COTAHIST, sob o de
/// cada época. Entram os códigos que a companhia declarou na FCA com o mesmo
/// número de classe — `VVAR3` para a `BHIA3`. No pregão em que dois códigos
/// negociam, fica o de hoje.
List<TradingDay> chain(
  String ticker,
  Iterable<String> companyCodes,
  Map<String, List<TradingDay>> cotahist,
) {
  final shareClass = ticker.length > 4 ? ticker.substring(4) : '';
  final byDay = <DateTime, TradingDay>{};
  final previousOnes = [
    for (final c in companyCodes)
      if (c != ticker && c.length > 4 && c.substring(4) == shareClass) c,
  ]..sort();
  for (final c in [...previousOnes, ticker]) {
    for (final p in cotahist[c] ?? const <TradingDay>[]) {
      byDay[p.date] = p;
    }
  }
  return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

/// Folga, em dias corridos, entre a data da coorte e o último pregão: além
/// disso o papel não negociava, e não há preço da data.
const int sessionMargin = 10;

/// O fator que leva a série da fonte à base de ações de [date].
///
/// `fechamento bruto ÷ fechamento da fonte` no último pregão do COTAHIST até
/// [date], medido no mesmo dia da fonte. Não se reconstrói pelos eventos do
/// registro: o fator é o que a fonte aplicou, e o registro da B3 repete evento
/// — a BBAS3 de 2018 tem fator 2 no preço e produto 8 no registro.
///
/// Devolve `null` sem pregão a até [sessionMargin] dias, ou sem fechamento da
/// fonte naquele dia.
({double factor, TradingDay tradingDay})? baseFactorOf({
  required PriceSeries source,
  required List<TradingDay> rawSessions,
  required DateTime date,
}) {
  final tradingDay = tradingDayUntil(rawSessions, date, marginDays: sessionMargin);
  if (tradingDay == null || !(tradingDay.close > 0)) return null;
  final day = DateTime.utc(tradingDay.date.year, tradingDay.date.month, tradingDay.date.day);
  for (final p in source.points.reversed) {
    final d = DateTime.utc(p.date.year, p.date.month, p.date.day);
    if (d.isAfter(day)) continue;
    if (d.isBefore(day)) return null;
    if (!(p.close > 0)) return null;
    final f = tradingDay.close / p.close;
    return f.isFinite && f > 0 ? (factor: f, tradingDay: tradingDay) : null;
  }
  return null;
}

/// A série da fonte na base de ações da data, pelo [factor] de [baseFactorOf].
///
/// O fechamento é multiplicado pelo fator. O volume é refeito do financeiro do
/// COTAHIST no mesmo dia — `financeiro ÷ fechamento na base da data` —, para que
/// `fechamento × volume` continue sendo o financeiro que a Porta 0 mede: o
/// volume da fonte não é ajustado, e o fechamento é. Dia sem COTAHIST mantém o
/// volume da fonte, que nesse caso só erra se houve evento entre ele e a data.
PriceSeries seriesOnDateBasis(
  PriceSeries source,
  List<TradingDay> rawSessions,
  double factor,
) {
  final tradedValue = <DateTime, double>{
    for (final p in rawSessions)
      if (p.tradedValue != null) p.date: p.tradedValue!,
  };
  return PriceSeries(
    ticker: source.ticker,
    points: [
      for (final p in source.points)
        () {
          final close = p.close * factor;
          final f = tradedValue[DateTime.utc(p.date.year, p.date.month, p.date.day)];
          return PricePoint(
            date: p.date,
            close: close,
            adjustedClose: p.adjustedClose,
            volume: (f != null && close > 0) ? f / close : p.volume,
          );
        }(),
    ],
  );
}

/// Valor de mercado da companhia em [data], espécie a espécie.
class MarketValue {
  /// Em reais.
  final double value;

  /// Como saiu: `especies` com as duas espécies pelo preço delas,
  /// `umaEspecie` com a companhia de uma espécie só ou a espécie sem pregão
  /// pelo preço da outra, e `semDivisao` sem a divisão entre espécies.
  final String origin;

  const MarketValue(this.value, this.origin);

  /// Pregões considerados no financeiro que escolhe o papel de cada espécie.
  static const int tradedValueSessions = 21;

  /// - [shares]: contagem total da data, somadas as espécies.
  /// - [commonFraction]: ordinárias ÷ total na data, ou `null` sem divisão.
  /// - [securities]: pregões brutos de cada papel da companhia, já encadeados.
  ///
  /// A preferencial com mais de uma classe listada — PNA e PNB — vai toda pelo
  /// preço da mais negociada: o formulário não separa a contagem entre elas. A
  /// unit não entra: ela é cesta das outras duas.
  ///
  /// Devolve `null` quando nenhum papel de espécie negociou até [sessionMargin]
  /// dias antes da data.
  static MarketValue? atDate({
    required double shares,
    required double? commonFraction,
    required Map<String, List<TradingDay>> securities,
    required DateTime date,
  }) {
    if (!(shares > 0)) return null;
    ({double price, double tradedValue})? best(ShareKind e) {
      ({double price, double tradedValue})? m;
      for (final entry in securities.entries) {
        if (kindOf(entry.key) != e) continue;
        final s = entry.value;
        final last = tradingDayUntil(s, date, marginDays: sessionMargin);
        if (last == null || !(last.close > 0)) continue;
        // Posição do último pregão, por busca binária: a série é ordenada.
        var lo = 0, hi = s.length;
        while (lo < hi) {
          final m = (lo + hi) ~/ 2;
          if (s[m].date.isAfter(last.date)) {
            hi = m;
          } else {
            lo = m + 1;
          }
        }
        final i = lo - 1;
        var fin = 0.0;
        for (var k = math.max(0, i - tradedValueSessions + 1); k <= i; k++) {
          fin += s[k].tradedValue ?? 0;
        }
        if (m == null || fin > m.tradedValue) {
          m = (price: last.close, tradedValue: fin);
        }
      }
      return m;
    }

    final on = best(ShareKind.common);
    final pn = best(ShareKind.preferred);
    if (on == null && pn == null) return null;
    final f = commonFraction;
    if (f == null || !f.isFinite || f < 0 || f > 1) {
      final p = (on == null || (pn != null && pn.tradedValue > on.tradedValue))
          ? pn!.price
          : on.price;
      return MarketValue(shares * p, 'semDivisao');
    }
    final pOn = on?.price ?? pn!.price;
    final pPn = pn?.price ?? on!.price;
    // A fração vem de uma razão de contagens: a espécie única é a fração a
    // uma folga de 0 ou de 1, e não a igualdade exata.
    const margin = 1e-9;
    final singleClass = f >= 1 - margin || f <= margin || on == null || pn == null;
    return MarketValue(
      shares * (f * pOn + (1 - f) * pPn),
      singleClass ? 'umaEspecie' : 'especies',
    );
  }
}

/// Divisão do capital entre ordinárias e preferenciais ao longo do tempo, do
/// quadro de capital social do Formulário de Referência.
///
/// A mesma regra de data da contagem (`ShareCountHistory`): cada aprovação de
/// capital vale pela **primeira** declaração dela. Desdobramento e grupamento
/// não mudam a fração, e por isso a série é só das aprovações.
class CapitalClasses {
  CapitalClasses._(this.points);

  /// `(desde, fração de ordinárias)`, em ordem de data.
  final List<({DateTime since, double fraction})> points;

  static CapitalClasses fromFre(Iterable<Map<String, String>> rows) {
    for (final kind in ShareCountHistory.kinds) {
      final byReference = <String, List<Map<String, String>>>{};
      for (final r in rows) {
        if (r['Tipo_Capital']?.trim() != kind) continue;
        (byReference['${r['Data_Referencia']}'] ??= []).add(r);
      }
      if (byReference.isEmpty) continue;
      // A maior versão de cada referência, em ordem de referência.
      final references = byReference.keys.toList()..sort();
      final points = <({DateTime since, double fraction})>[];
      final seen = <DateTime>[];
      for (final ref in references) {
        final doc = byReference[ref]!;
        final version = doc
            .map((r) => int.tryParse(r['Versao'] ?? '') ?? 0)
            .fold<int>(0, math.max);
        for (final r in doc) {
          if ((int.tryParse(r['Versao'] ?? '') ?? 0) != version) continue;
          final v = r['Data_Autorizacao_Aprovacao'];
          final approval = (v == null || v.length < 10)
              ? null
              : DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
          final on = double.tryParse(r['Quantidade_Acoes_Ordinarias'] ?? '');
          final pn = double.tryParse(r['Quantidade_Acoes_Preferenciais'] ?? '');
          if (approval == null || on == null || pn == null) continue;
          if (on < 0 || pn < 0 || on + pn <= 0) continue;
          if (seen.any((a) => a.isAtSameMomentAs(approval))) continue;
          seen.add(approval);
          points.add((since: approval, fraction: on / (on + pn)));
        }
      }
      points.sort((a, b) => a.since.compareTo(b.since));
      return CapitalClasses._(List.unmodifiable(points));
    }
    return CapitalClasses._(const []);
  }

  /// Lê a série gravada por `b3_deslistadas_contagem.dart`.
  static CapitalClasses fromJson(List<Object?>? list) => CapitalClasses._([
        for (final p in (list ?? const []).cast<Map<String, dynamic>>())
          (
            since: DateTime.parse('${(p['desde'] as String).substring(0, 10)}T00:00:00Z'),
            fraction: (p['fracaoOrdinarias'] as num).toDouble(),
          ),
      ]);

  List<Map<String, Object>> toJson() => [
        for (final p in points)
          {
            'desde': p.since.toIso8601String().substring(0, 10),
            'fracaoOrdinarias': p.fraction,
          },
      ];

  /// Fração de ordinárias em vigor em [date], ou a primeira declarada quando a
  /// data vem antes dela — a divisão entre espécies muda pouco, e sem ela o
  /// valor de mercado perde a espécie. `null` sem ponto nenhum.
  double? at(DateTime date) {
    if (points.isEmpty) return null;
    final d = DateTime.utc(date.year, date.month, date.day);
    var current = points.first.fraction;
    for (final p in points) {
      if (p.since.isAfter(d)) break;
      current = p.fraction;
    }
    return current;
  }
}
