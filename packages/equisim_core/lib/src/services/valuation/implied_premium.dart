/// O prêmio de risco de mercado implícito no preço da bolsa, e a média de dez
/// anos dele, que é o prêmio do CAPM do motor (decisão 142).
///
/// **De onde vem.** Em cada fim de trimestre, o valor de mercado somado das
/// companhias listadas é igualado ao dinheiro que elas distribuem — dividendos e
/// juros sobre capital próprio dos doze meses —, crescendo com a economia
/// nominal: `r = rendimento × (1 + g) + g` (Gordon; o método de Damodaran, com
/// os dois estágios no mesmo `g` por falta de consenso de analistas). `r` é o
/// retorno que o preço embute. O prêmio do trimestre é `r` menos o prefixado de
/// dez anos da curva do Tesouro na mesma data. A série é medida fora do
/// aplicativo (`tool/premio_implicito.dart`), que não tem como somar a bolsa
/// inteira para avaliar um ativo, e chega por pacote.
///
/// **Por que a média de dez anos, e não o trimestre.** O implícito do
/// trimestre fica negativo quando o prefixado dispara — em 2015, em 2024 e em
/// 2026 —, e prêmio negativo faz o beta alto baratear o capital. A média de dez
/// anos fica positiva em todas as datas do backtest, entre 1% e 1,6%, e concorda
/// com o prêmio histórico de dez anos do Ibovespa contra o CDI
/// (`docs/validacao/premio_implicito.md`).
///
/// **Por que `r − Rf`, e não Fisher.** O CAPM do motor soma:
/// `Ke = Rf + β × prêmio`. O prêmio que, somado à taxa livre de risco, devolve o
/// retorno que o preço embute para beta 1 é a diferença, e não a razão
/// `(1 + r) ÷ (1 + Rf) − 1`, que é a mesma grandeza dividida por `1 + Rf`.
library;

/// Um trimestre da série do prêmio implícito.
class ImpliedPremiumQuarter {
  /// Último dia do trimestre, em UTC.
  final DateTime date;

  /// Retorno que o preço da bolsa embute, `r`, em fração ao ano.
  final double impliedReturn;

  /// Prefixado de dez anos da curva do Tesouro na data, em fração ao ano.
  final double riskFree;

  const ImpliedPremiumQuarter({
    required this.date,
    required this.impliedReturn,
    required this.riskFree,
  });

  /// O prêmio do trimestre na forma que o CAPM do motor soma, `r − Rf`.
  double get premium => impliedReturn - riskFree;
}

/// A série trimestral do prêmio implícito, como o pacote a traz.
class ImpliedPremiumPackage {
  /// Data em que a série foi medida.
  final DateTime geradoEm;

  /// Os trimestres, em ordem de data.
  final List<ImpliedPremiumQuarter> quarters;

  /// Anos da média.
  static const int windowYears = 10;

  /// Trimestres mínimos dentro da janela para a média valer.
  ///
  /// **Vinte, metade da janela.** A série começa em 2011, e as coortes do
  /// backtest de 2018 têm de 29 a 31 trimestres atrás de si: com o mínimo de
  /// quarenta, elas não teriam prêmio. Com vinte, a média dessas datas é a dos
  /// trimestres que havia, e a partir de 31/12/2020 a janela está cheia.
  static const int minQuarters = 20;

  const ImpliedPremiumPackage({required this.geradoEm, required this.quarters});

  /// Os trimestres que entram na média de [asOf]: fim em
  /// `(asOf − dez anos, asOf]`.
  List<ImpliedPremiumQuarter> window(DateTime asOf) {
    final fim = DateTime.utc(asOf.year, asOf.month, asOf.day);
    final inicio = DateTime.utc(asOf.year - windowYears, asOf.month, asOf.day);
    return [
      for (final q in quarters)
        if (q.date.isAfter(inicio) && !q.date.isAfter(fim)) q,
    ];
  }

  /// A média de dez anos do prêmio implícito até [asOf], ou `null` com menos
  /// de [minQuarters] trimestres na janela.
  double? normalizedAt(DateTime asOf) {
    final janela = window(asOf);
    if (janela.length < minQuarters) return null;
    var soma = 0.0;
    for (final q in janela) {
      soma += q.premium;
    }
    return soma / janela.length;
  }

  /// O último trimestre medido até [asOf], ou `null`.
  ImpliedPremiumQuarter? latestAt(DateTime asOf) {
    final fim = DateTime.utc(asOf.year, asOf.month, asOf.day);
    ImpliedPremiumQuarter? ultimo;
    for (final q in quarters) {
      if (q.date.isAfter(fim)) break;
      ultimo = q;
    }
    return ultimo;
  }
}

/// Serialização da série do prêmio implícito.
abstract final class ImpliedPremiumCodec {
  /// Versão do formato.
  static const int versao = 1;

  /// Grava o pacote.
  static Map<String, Object> encode(ImpliedPremiumPackage pacote) => {
        'versao': versao,
        'geradoEm': _dia(pacote.geradoEm),
        'trimestres': [
          for (final q in pacote.quarters)
            {
              'data': _dia(q.date),
              'retornoImplicito': q.impliedReturn,
              'prefixado10': q.riskFree,
            },
        ],
      };

  /// Lê o pacote, ou devolve `null` quando ele não é utilizável.
  ///
  /// Recusa em vez de adivinhar: versão diferente, data ilegível, trimestre
  /// com número não finito ou série vazia devolvem `null`, e quem chama segue
  /// com o prêmio parametrizado — declarado.
  static ImpliedPremiumPackage? decode(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return null;
    final gerado = DateTime.tryParse('${pacote['geradoEm']}');
    final lista = pacote['trimestres'];
    if (gerado == null || lista is! List || lista.isEmpty) return null;
    final quarters = <ImpliedPremiumQuarter>[];
    for (final item in lista) {
      if (item is! Map) return null;
      final data = DateTime.tryParse('${item['data']}');
      final r = (item['retornoImplicito'] as num?)?.toDouble();
      final rf = (item['prefixado10'] as num?)?.toDouble();
      if (data == null || r == null || rf == null) return null;
      if (!r.isFinite || !rf.isFinite) return null;
      quarters.add(ImpliedPremiumQuarter(
        date: DateTime.utc(data.year, data.month, data.day),
        impliedReturn: r,
        riskFree: rf,
      ));
    }
    quarters.sort((a, b) => a.date.compareTo(b.date));
    return ImpliedPremiumPackage(
      geradoEm: DateTime.utc(gerado.year, gerado.month, gerado.day),
      quarters: List.unmodifiable(quarters),
    );
  }

  static String _dia(DateTime d) => d.toIso8601String().substring(0, 10);
}
