import '../value_objects/ticker.dart';

/// Cotação de fechamento de um pregão.
///
/// [close] vem ajustado por desdobramentos e grupamentos, mas **não** por
/// proventos (convenção Yahoo, verificada em BBAS3 15/04/2024 e WEGE3
/// 27/04/2021 — nenhuma descontinuidade nas datas-ex de split).
///
/// [adjustedClose] é série de retorno total, porém **subajusta proventos
/// brasileiros** — não deve ser usada em cálculo, apenas conferência.
class PricePoint {
  /// Dia do pregão, truncado para meia-noite local.
  final DateTime date;

  /// Fechamento ajustado por desdobramento e grupamento, em reais.
  final double close;

  /// Fechamento ajustado também por proventos, como a fonte o publica.
  ///
  /// `null` quando a fonte não o informa. **Não use em cálculo** — ver a doc
  /// da classe.
  final double? adjustedClose;

  /// Constrói o ponto, truncando [date] para o dia.
  ///
  /// O truncamento é o que permite usar a data como chave de mapa e comparar
  /// séries de ativos diferentes sem que a hora publicada pela fonte separe
  /// dois pregões do mesmo dia.
  PricePoint({
    required DateTime date,
    required this.close,
    this.adjustedClose,
  }) : date = DateTime(date.year, date.month, date.day);
}

/// Série histórica de preços de um ativo, ordenada cronologicamente.
class PriceSeries {
  /// Ativo a que a série pertence.
  final Ticker ticker;

  /// Pontos em ordem cronológica crescente. **Imutável** — a lista é uma cópia
  /// não modificável, então quem construiu a série pode alterar a lista de
  /// origem sem afetá-la.
  final List<PricePoint> points;

  /// Constrói a série ordenando os pontos por data e congelando a lista.
  ///
  /// Ordenar na construção é o que autoriza a busca binária de [closeAsOf] e
  /// dispensa todo consumidor de conferir a ordem. Datas repetidas não são
  /// removidas: sobrevivem as duas, e o índice de [closeOn] fica com a última.
  ///
  /// - [ticker]: ativo da série.
  /// - [points]: pontos em qualquer ordem.
  ///
  /// Complexidade O(n log n).
  PriceSeries({required this.ticker, required List<PricePoint> points})
      : points = List<PricePoint>.unmodifiable(
          <PricePoint>[...points]
            ..sort((PricePoint a, PricePoint b) => a.date.compareTo(b.date)),
        );

  /// `true` quando não há nenhum pregão na série.
  bool get isEmpty => points.isEmpty;

  /// `true` quando há ao menos um pregão.
  bool get isNotEmpty => points.isNotEmpty;

  /// Data do primeiro pregão. Lança [StateError] se a série estiver vazia.
  DateTime get firstDate => points.first.date;

  /// Data do último pregão. Lança [StateError] se a série estiver vazia.
  DateTime get lastDate => points.last.date;

  /// Índice por data, construído sob demanda.
  late final Map<DateTime, double> _byDate = {
    for (final p in points) p.date: p.close,
  };

  /// Fechamento **exatamente** na data pedida.
  ///
  /// - [date]: dia procurado. É truncada antes da busca.
  ///
  /// Devolve `null` quando não houve pregão nesse dia — fim de semana, feriado,
  /// suspensão. Para o último preço conhecido em vez do preço exato, use
  /// [closeAsOf]. Complexidade O(1); constrói o índice na primeira chamada.
  double? closeOn(DateTime date) => _byDate[DateTime(date.year, date.month, date.day)];

  /// Último fechamento conhecido em ou antes de [date] — *forward fill*.
  ///
  /// Necessário porque pregões não coincidem perfeitamente entre ativos
  /// (leilões, suspensões, feriados regionais).
  ///
  /// - [date]: dia de referência. É truncada antes da busca.
  ///
  /// Devolve `null` apenas quando [date] é anterior ao primeiro pregão da
  /// série — aí não há passado para preencher. **Nunca olha para frente**, o
  /// que é o que impede a simulação de usar preço futuro.
  ///
  /// Complexidade O(log n) por busca binária, depois de um acerto O(1) no
  /// índice quando a data existe.
  double? closeAsOf(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    final direct = _byDate[target];
    if (direct != null) return direct;

    var lo = 0;
    var hi = points.length - 1;
    int? best;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (!points[mid].date.isAfter(target)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best == null ? null : points[best].close;
  }

  /// Datas dos pregões, em ordem cronológica.
  ///
  /// Constrói uma lista nova a cada chamada — O(n). Em laço, guarde o
  /// resultado em vez de reler o getter.
  List<DateTime> get dates => points.map((p) => p.date).toList();
}
