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

/// Natureza do provento, pelo rótulo da B3.
enum CashDividendKind {
  /// `DIVIDENDO` — isento para a pessoa física.
  dividendo,

  /// `JRS CAP PROPRIO` — juros sobre capital próprio, com 15% retidos na fonte.
  jurosSobreCapital,

  /// `RENDIMENTO` — isento, como o dividendo.
  rendimento,

  /// `REST CAP DIN` — restituição de capital em dinheiro.
  restituicaoDeCapital,
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
  double get netAmount => kind == CashDividendKind.jurosSobreCapital
      ? amount * (1 - B3CashDividends.jcpWithholding)
      : amount;
}

/// Leitura dos proventos da B3.
abstract final class B3CashDividends {
  /// Imposto retido na fonte sobre juros sobre capital próprio.
  static const double jcpWithholding = 0.15;

  static const Map<String, CashDividendKind> _rotulos = {
    'DIVIDENDO': CashDividendKind.dividendo,
    'JRS CAP PROPRIO': CashDividendKind.jurosSobreCapital,
    'RENDIMENTO': CashDividendKind.rendimento,
    'REST CAP DIN': CashDividendKind.restituicaoDeCapital,
  };

  /// Lê a lista `results` do `GetListedCashDividends`.
  ///
  /// Linha sem classe, sem data-com legível, sem valor positivo ou com rótulo
  /// desconhecido fica de fora: provento inventado entraria no retorno.
  static List<CashDividend> parse(Iterable<Object?> results) {
    final out = <CashDividend>[];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final classe = (r['typeStock'] as String?)?.trim();
      final kind = _rotulos[(r['corporateAction'] as String?)?.trim()];
      final com = B3Registry.parseDate(r['lastDatePriorEx']);
      final lote = B3Registry.parseNumber(r['quotedPerShares']) ?? 1;
      final valor = B3Registry.parseNumber(r['valueCash']);
      if (classe == null || classe.isEmpty || kind == null || com == null) {
        continue;
      }
      if (valor == null || !(valor > 0) || !(lote > 0)) continue;
      final preco = B3Registry.parseNumber(r['closingPricePriorExDate']);
      out.add(CashDividend(
        shareClass: classe,
        kind: kind,
        lastDateWithRights: com,
        exDate: BrazilianCalendar.nextTradingSession(com),
        amount: valor / lote,
        closeWithRights: preco != null && preco > 0 ? preco / lote : null,
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
  static ({double factor, int applied, int approximated, int withoutPrice})
      factor({
    required Iterable<CashDividend> dividends,
    required DateTime de,
    required DateTime ate,
    required double? Function(DateTime exDate) closeOnExDate,
    bool net = true,
  }) {
    final d = DateTime.utc(de.year, de.month, de.day);
    final a = DateTime.utc(ate.year, ate.month, ate.day);
    var fator = 1.0;
    var aplicados = 0;
    var aproximados = 0;
    var semPreco = 0;
    for (final x in dividends) {
      if (!x.exDate.isAfter(d) || x.exDate.isAfter(a)) continue;
      var preco = closeOnExDate(x.exDate);
      if (preco == null || !(preco > 0)) {
        final com = x.closeWithRights;
        preco = com != null && com > x.amount ? com - x.amount : null;
        if (preco == null) {
          semPreco++;
          continue;
        }
        aproximados++;
      }
      fator *= 1 + (net ? x.netAmount : x.amount) / preco;
      aplicados++;
    }
    return (
      factor: fator,
      applied: aplicados,
      approximated: aproximados,
      withoutPrice: semPreco,
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
    final proventos = [...dividends]..sort((a, b) => a.exDate.compareTo(b.exDate));
    final indice = List<double>.filled(n, 1.0);
    var aplicados = 0;
    var semPreco = 0;
    var k = 0;
    DateTime dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    // Proventos anteriores ao primeiro pregão não pertencem à série.
    while (k < proventos.length &&
        n > 0 &&
        !proventos[k].exDate.isAfter(dia(dates[0]))) {
      k++;
    }
    for (var i = 1; i < n; i++) {
      final hoje = dia(dates[i]);
      var rendimento = 0.0;
      while (k < proventos.length && !proventos[k].exDate.isAfter(hoje)) {
        final p = proventos[k++];
        final com = p.closeWithRights;
        if (com == null || !(com > 0)) {
          semPreco++;
          continue;
        }
        rendimento += (net ? p.netAmount : p.amount) / com;
        aplicados++;
      }
      final anterior = closes[i - 1];
      final r = anterior > 0 ? closes[i] / anterior + rendimento : 1.0;
      indice[i] = indice[i - 1] * r;
    }
    return (index: indice, applied: aplicados, withoutPrice: semPreco);
  }
}

/// Formato do pacote de proventos, para empacotar no aplicativo (item A4).
///
/// Mora no núcleo pela mesma razão do `B3RegistryCodec`: a ferramenta que grava
/// e o repositório que lê precisam concordar sobre o formato.
abstract final class CashDividendsCodec {
  /// Versão do formato.
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

  /// O pacote inteiro, por emissor de quatro letras.
  static Map<String, Object> encode(Map<String, List<CashDividend>> porEmissor,
          {required DateTime geradoEm}) =>
      {
        'versao': versao,
        'geradoEm': _dia(geradoEm),
        'emissores': {
          for (final e in porEmissor.entries)
            e.key: [
              for (final p in e.value)
                {
                  'classe': p.shareClass,
                  'tipo': p.kind.name,
                  'dataCom': _dia(p.lastDateWithRights),
                  'dataEx': _dia(p.exDate),
                  'valor': p.amount,
                  if (p.closeWithRights != null) 'precoComDireito': p.closeWithRights!,
                },
            ],
        },
      };

  /// Lê o pacote. Versão desconhecida devolve mapa vazio.
  static Map<String, List<CashDividend>> decode(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return const {};
    final emissores = pacote['emissores'];
    if (emissores is! Map<String, dynamic>) return const {};
    final out = <String, List<CashDividend>>{};
    for (final e in emissores.entries) {
      final lista = e.value;
      if (lista is! List) continue;
      final proventos = <CashDividend>[];
      for (final x in lista) {
        if (x is! Map<String, dynamic>) continue;
        final classe = x['classe'];
        final tipo = CashDividendKind.values
            .where((k) => k.name == x['tipo'])
            .firstOrNull;
        final com = _data(x['dataCom']);
        final ex = _data(x['dataEx']);
        final valor = (x['valor'] as num?)?.toDouble();
        final preco = (x['precoComDireito'] as num?)?.toDouble();
        if (classe is! String || tipo == null || com == null || ex == null) {
          continue;
        }
        if (valor == null || !(valor > 0)) continue;
        proventos.add(CashDividend(
          shareClass: classe,
          kind: tipo,
          lastDateWithRights: com,
          exDate: ex,
          amount: valor,
          closeWithRights: preco != null && preco > 0 ? preco : null,
        ));
      }
      proventos.sort((a, b) => a.exDate.compareTo(b.exDate));
      out[e.key] = List.unmodifiable(proventos);
    }
    return out;
  }

  /// Os proventos da classe de [ticker], dentro de [porEmissor].
  static List<CashDividend> forTicker(
      Map<String, List<CashDividend>> porEmissor, String ticker) {
    if (ticker.length < 5) return const [];
    final classe = B3CashDividends.shareClassOf(ticker);
    if (classe == null) return const [];
    return [
      for (final p in porEmissor[ticker.substring(0, 4)] ?? const <CashDividend>[])
        if (p.shareClass == classe) p,
    ];
  }
}
