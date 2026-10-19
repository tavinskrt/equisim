/// Proventos em dinheiro declarados pela B3, e o retorno total que eles formam
/// (item A4, decisão 89).
///
/// **De onde vem.** O `GetListedCashDividends` do portal de empresas listadas
/// devolve, por emissor, o histórico inteiro de proventos em dinheiro — desde
/// 1995 nos 297 emissores do universo, 18.651 eventos em 14/09/2026 —, com a
/// classe da ação, a data-com, o valor, o rótulo e o fechamento anterior à data
/// ex. O registro do `GetListedSupplementCompany`, que o item A3.1 usa, só traz
/// os últimos doze meses.
///
/// **A unidade.** `valueCash` e `closingPricePriorExDate` vêm na unidade de
/// cotação da época — por ação, ou por lote de mil nos anos em que a B3 cotava
/// assim (`quotedPerShares = 1000`, 2.744 eventos). Os dois são divididos por
/// ela: o provento sai por ação.
library;

import '../../time/brazilian_calendar.dart';
import 'b3_registry.dart';
import '../../audit/wire_keyed.dart';

/// Natureza do provento, pelo rótulo da B3.
enum CashDividendKind implements WireKeyed {
  /// `DIVIDENDO` — isento para a pessoa física.
  dividend('dividendo'),

  /// `JRS CAP PROPRIO` — juros sobre capital próprio, com 15% retidos na fonte.
  interestOnEquity('jurosSobreCapital'),

  /// `RENDIMENTO` — isento, como o dividendo.
  income('rendimento'),

  /// `REST CAP DIN` — restituição de capital em dinheiro.
  capitalRefund('restituicaoDeCapital');

  const CashDividendKind(this.key);

  /// O valor cuja [key] é [key] — o que `values.byName` fazia com o nome.
  ///
  /// Lança [ArgumentError], como `byName`, quando nenhum valor tem a chave.
  static CashDividendKind fromKey(String key) {
    for (final k in values) {
      if (k.key == key) return k;
    }
    throw ArgumentError.value(key, 'name', 'Nenhum valor do enum com essa chave');
  }

  /// Chave gravada nas saídas — pacote de dados, rastro de auditoria,
  /// relatório. É dado, e não nome de código: renomear o valor não a muda.
  @override
  final String key;
}

/// Um provento em dinheiro, por ação.
class CashDividend {
  /// Classe da ação na convenção da B3: `ON`, `PN`, `PNA`, `PNB`, `UNT`.
  final String shareClass;

  /// Natureza, pelo rótulo.
  final CashDividendKind kind;

  /// Último dia com direito — a data-com.
  final DateTime lastDateWithRights;

  /// Primeiro pregão depois da data-com: a data ex.
  final DateTime exDate;

  /// Valor bruto por ação, em reais.
  final double amount;

  /// Fechamento por ação no último dia com direito, quando a B3 o informa.
  final double? closeWithRights;

  /// Declara o provento.
  const CashDividend({
    required this.shareClass,
    required this.kind,
    required this.lastDateWithRights,
    required this.exDate,
    required this.amount,
    this.closeWithRights,
  });

  /// Valor que chega ao acionista pessoa física: o juro sobre capital próprio
  /// perde os 15% retidos, e o resto é isento.
  double get netAmount => kind == CashDividendKind.interestOnEquity
      ? amount * (1 - B3CashDividends.jcpWithholding)
      : amount;
}

/// Leitura dos proventos da B3.
abstract final class B3CashDividends {
  /// Imposto retido na fonte sobre juros sobre capital próprio.
  static const double jcpWithholding = 0.15;

  static const Map<String, CashDividendKind> _labels = {
    'DIVIDENDO': CashDividendKind.dividend,
    'JRS CAP PROPRIO': CashDividendKind.interestOnEquity,
    'RENDIMENTO': CashDividendKind.income,
    'REST CAP DIN': CashDividendKind.capitalRefund,
  };

  /// Lê a lista `results` do `GetListedCashDividends`.
  ///
  /// Linha sem classe, sem data-com legível, sem valor positivo ou com rótulo
  /// desconhecido fica de fora: provento inventado entraria no retorno.
  static List<CashDividend> parse(Iterable<Object?> results) {
    final out = <CashDividend>[];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final shareClass = (r['typeStock'] as String?)?.trim();
      final kind = _labels[(r['corporateAction'] as String?)?.trim()];
      final withInput = B3Registry.parseDate(r['lastDatePriorEx']);
      final lot = B3Registry.parseNumber(r['quotedPerShares']) ?? 1;
      final value = B3Registry.parseNumber(r['valueCash']);
      if (shareClass == null || shareClass.isEmpty || kind == null || withInput == null) {
        continue;
      }
      if (value == null || !(value > 0) || !(lot > 0)) continue;
      final price = B3Registry.parseNumber(r['closingPricePriorExDate']);
      out.add(CashDividend(
        shareClass: shareClass,
        kind: kind,
        lastDateWithRights: withInput,
        exDate: BrazilianCalendar.nextTradingSession(withInput),
        amount: value / lot,
        closeWithRights: price != null && price > 0 ? price / lot : null,
      ));
    }
    out.sort((a, b) => a.exDate.compareTo(b.exDate));
    return out;
  }

  /// Classe da ação de [ticker], pelo sufixo numérico, ou `null`.
  ///
  /// 3 é ordinária, 4 preferencial, 5 a 8 preferenciais de classe A a D, e 11
  /// a unit.
  static String? shareClassOf(String ticker) {
    final m = RegExp(r'(\d+)$').firstMatch(ticker.trim());
    return switch (m?.group(1)) {
      '3' => 'ON',
      '4' => 'PN',
      '5' => 'PNA',
      '6' => 'PNB',
      '7' => 'PNC',
      '8' => 'PND',
      '11' => 'UNT',
      _ => null,
    };
  }
}

/// Retorno total a partir do retorno de preço e dos proventos do período.
abstract final class TotalReturn {
  /// Fator de reinvestimento dos proventos com data ex em `(de, ate]`.
  ///
  /// O retorno total diário é `(P_t + D_t)/P_{t−1}`, e o produto dele no
  /// período é o retorno de preço vezes `Π (1 + D_i / P_ex,i)` — o provento
  /// reinvestido no fechamento da data ex. **Por isso o fator não depende de
  /// ajuste por desdobramento**: provento e preço da data ex estão na mesma
  /// base, a daquele dia, e multiplicam um retorno de preço que já foi
  /// ajustado por evento.
  ///
  /// - [closeOnExDate]: fechamento **bruto**, por ação, no primeiro pregão a
  ///   partir da data ex. `null` quando a série não tem o pregão — papel que
  ///   trocou de código, como ESTC3 para YDUQ3, só tem no COTAHIST o código
  ///   novo. Aí vale o preço com direito que a B3 publica, menos o provento: a
  ///   aproximação erra pelo quanto o mercado andou no dia ex vezes o
  ///   rendimento, e é contada em `approximated`. Sem nenhum dos dois, o
  ///   provento fica de fora e é contado em `withoutPrice`.
  /// - [net]: `true` desconta o imposto retido do juro sobre capital próprio.
  ///
  /// **Proventos da mesma data ex entram juntos** (lente `nucleo`,
  /// 25/09/2026): o retorno do dia é `(P_ex + D_1 + D_2)/P_com`, e o fator é
  /// `1 + (D_1 + D_2)/P_ex`. Multiplicar `(1 + D_1/P_ex)(1 + D_2/P_ex)`
  /// inventava o termo cruzado `D_1·D_2/P_ex²` — um provento rendendo sobre o
  /// outro no mesmo dia —, e dividendo e juro sobre capital próprio saem
  /// juntos com frequência. Os rendimentos do dia somam, como no índice.
  static ({double factor, int applied, int approximated, int withoutPrice})
      factor({
    required Iterable<CashDividend> dividends,
    required DateTime from,
    required DateTime until,
    required double? Function(DateTime exDate) closeOnExDate,
    bool net = true,
  }) {
    final d = DateTime.utc(from.year, from.month, from.day);
    final a = DateTime.utc(until.year, until.month, until.day);
    final byDay = <DateTime, List<CashDividend>>{};
    for (final x in dividends) {
      if (!x.exDate.isAfter(d) || x.exDate.isAfter(a)) continue;
      final day = DateTime.utc(x.exDate.year, x.exDate.month, x.exDate.day);
      (byDay[day] ??= []).add(x);
    }
    var factor = 1.0;
    var applied = 0;
    var approximated = 0;
    var withoutPrice = 0;
    for (final group in byDay.values) {
      final price = closeOnExDate(group.first.exDate);
      // O rendimento do dia sobre o preço ex; sem o pregão, sobre o preço com
      // direito, e o preço ex sai dele menos os proventos do dia: `D/P_ex` é
      // `(D/P_com) / (1 − ΣD/P_com)`.
      var overEx = 0.0;
      if (price != null && price > 0) {
        for (final x in group) {
          overEx += (net ? x.netAmount : x.amount) / price;
        }
      } else {
        double? withInput;
        for (final x in group) {
          withInput ??= x.closeWithRights;
        }
        var decline = 0.0;
        var paid = 0.0;
        if (withInput != null && withInput > 0) {
          for (final x in group) {
            decline += x.amount / withInput;
            paid += (net ? x.netAmount : x.amount) / withInput;
          }
        }
        if (withInput == null || !(withInput > 0) || !(decline < 1)) {
          withoutPrice += group.length;
          continue;
        }
        overEx = paid / (1 - decline);
        approximated += group.length;
      }
      factor *= 1 + overEx;
      applied += group.length;
    }
    return (
      factor: factor,
      applied: applied,
      approximated: approximated,
      withoutPrice: withoutPrice,
    );
  }
}

/// Índice de retorno total sobre uma série de fechamentos (item A4).
abstract final class TotalReturnIndex {
  /// O índice, posição a posição com [closes], começando em 1.
  ///
  /// O retorno de cada pregão é `P_t/P_{t−1}`, mais o rendimento dos proventos
  /// com data ex em `(t−1, t]`: `D/P_com`, com o preço **com direito** que a B3
  /// publica. É a identidade `(P_ex + D)/P_com = P_ex/P_com + D/P_com` — e,
  /// como `D` e `P_com` são brutos do mesmo dia, o rendimento não depende de a
  /// série estar ajustada por desdobramento.
  ///
  /// Provento sem preço com direito fica de fora, contado em `withoutPrice`.
  static ({List<double> index, int applied, int withoutPrice}) build({
    required List<DateTime> dates,
    required List<double> closes,
    required Iterable<CashDividend> dividends,
    bool net = true,
  }) {
    final n = dates.length < closes.length ? dates.length : closes.length;
    final sortedDividends = [...dividends]..sort((a, b) => a.exDate.compareTo(b.exDate));
    final index = List<double>.filled(n, 1.0);
    var applied = 0;
    var withoutPrice = 0;
    var k = 0;
    DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    // Proventos anteriores ao primeiro pregão não pertencem à série.
    while (k < sortedDividends.length &&
        n > 0 &&
        !sortedDividends[k].exDate.isAfter(day(dates[0]))) {
      k++;
    }
    for (var i = 1; i < n; i++) {
      final today = day(dates[i]);
      var income = 0.0;
      while (k < sortedDividends.length && !sortedDividends[k].exDate.isAfter(today)) {
        final p = sortedDividends[k++];
        final withInput = p.closeWithRights;
        if (withInput == null || !(withInput > 0)) {
          withoutPrice++;
          continue;
        }
        income += (net ? p.netAmount : p.amount) / withInput;
        applied++;
      }
      final previous = closes[i - 1];
      final r = previous > 0 ? closes[i] / previous + income : 1.0;
      index[i] = index[i - 1] * r;
    }
    return (index: index, applied: applied, withoutPrice: withoutPrice);
  }
}

/// Formato do pacote de proventos, para empacotar no aplicativo (item A4).
///
/// Mora no núcleo pela mesma razão do `B3RegistryCodec`: a ferramenta que grava
/// e o repositório que lê precisam concordar sobre o formato.
abstract final class CashDividendsCodec {
  /// Versão do formato.
  static const int version = 1;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _date(Object? v) {
    if (v is! String || v.length < 10) return null;
    final p = v.substring(0, 10).split('-');
    if (p.length != 3) return null;
    final a = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (a == null || m == null || d == null) return null;
    return DateTime.utc(a, m, d);
  }

  /// O pacote inteiro, por emissor de quatro letras.
  static Map<String, Object> encode(Map<String, List<CashDividend>> byIssuer,
          {required DateTime generatedAt}) =>
      {
        'versao': version,
        'geradoEm': _day(generatedAt),
        'emissores': {
          for (final e in byIssuer.entries)
            e.key: [
              for (final p in e.value)
                {
                  'classe': p.shareClass,
                  'tipo': p.kind.key,
                  'dataCom': _day(p.lastDateWithRights),
                  'dataEx': _day(p.exDate),
                  'valor': p.amount,
                  if (p.closeWithRights != null) 'precoComDireito': p.closeWithRights!,
                },
            ],
        },
      };

  /// Lê o pacote. Versão desconhecida devolve mapa vazio.
  static Map<String, List<CashDividend>> decode(Map<String, dynamic> package) {
    if (package['versao'] != version) return const {};
    final issuers = package['emissores'];
    if (issuers is! Map<String, dynamic>) return const {};
    final out = <String, List<CashDividend>>{};
    for (final e in issuers.entries) {
      final list = e.value;
      if (list is! List) continue;
      final dividends = <CashDividend>[];
      for (final x in list) {
        if (x is! Map<String, dynamic>) continue;
        final shareClass = x['classe'];
        final kind = CashDividendKind.values
            .where((k) => k.key == x['tipo'])
            .firstOrNull;
        final withInput = _date(x['dataCom']);
        final ex = _date(x['dataEx']);
        final value = (x['valor'] as num?)?.toDouble();
        final price = (x['precoComDireito'] as num?)?.toDouble();
        if (shareClass is! String || kind == null || withInput == null || ex == null) {
          continue;
        }
        if (value == null || !(value > 0)) continue;
        dividends.add(CashDividend(
          shareClass: shareClass,
          kind: kind,
          lastDateWithRights: withInput,
          exDate: ex,
          amount: value,
          closeWithRights: price != null && price > 0 ? price : null,
        ));
      }
      dividends.sort((a, b) => a.exDate.compareTo(b.exDate));
      out[e.key] = List.unmodifiable(dividends);
    }
    return out;
  }

  /// Os proventos da classe de [ticker], dentro de [byIssuer].
  static List<CashDividend> forTicker(
      Map<String, List<CashDividend>> byIssuer, String ticker) {
    if (ticker.length < 5) return const [];
    final shareClass = B3CashDividends.shareClassOf(ticker);
    if (shareClass == null) return const [];
    return [
      for (final p in byIssuer[ticker.substring(0, 4)] ?? const <CashDividend>[])
        if (p.shareClass == shareClass) p,
    ];
  }
}
