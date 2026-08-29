import '../entities/dividend_event.dart';
import '../entities/price_series.dart';
import '../tax/tax_policy.dart';
import '../value_objects/date_range.dart';

/// Série de retorno total construída pelo próprio domínio.
class TotalReturnSeries {
  /// Datas dos pregões simulados, em ordem cronológica e alinhadas a [index].
  final List<DateTime> dates;

  /// Índice de retorno total, com base 1,0 na primeira data.
  final List<double> index;

  /// Proventos brutos por ação acumulados no período.
  final double grossDividendsPerShare;

  /// Imposto retido por ação acumulado no período.
  final double withheldTaxPerShare;

  const TotalReturnSeries({
    required this.dates,
    required this.index,
    required this.grossDividendsPerShare,
    required this.withheldTaxPerShare,
  });

  /// `true` quando nenhum pregão entrou na simulação.
  bool get isEmpty => index.isEmpty;

  /// Retorno acumulado do período, em fração.
  ///
  /// Devolve `0.0` com menos de dois pontos. Como [index] parte de 1,0 e só
  /// cresce por reinvestimento, o denominador nunca é zero em série construída
  /// por [TotalReturnEngine.build].
  double get totalReturn => index.length < 2 ? 0.0 : index.last / index.first - 1.0;

  /// Retornos diários simples entre pontos consecutivos de [index].
  ///
  /// Devolve `length − 1` elementos no caso normal — menos, se algum ponto
  /// anterior for não positivo, porque esses pares são **descartados** em vez
  /// de produzir divisão por zero. O resultado deixa então de estar alinhado a
  /// [dates], o que só importa para quem parear séries por posição; para isso
  /// use `BetaCalculator.alignReturns`, que pareia por data.
  ///
  /// Constrói a lista a cada chamada — O(n).
  List<double> get dailyReturns {
    final out = <double>[];
    for (var i = 1; i < index.length; i++) {
      if (index[i - 1] > 0) out.add(index[i] / index[i - 1] - 1.0);
    }
    return out;
  }
}

/// Constrói séries de retorno total a partir de preço + proventos + tributação.
///
/// Esta é a **fonte única de verdade** de retorno no domínio: alimenta backtest,
/// dividend yield, beta, correlação e volatilidade. O `adjustedClose` da fonte
/// não é usado em cálculo por subajustar proventos brasileiros.
abstract final class TotalReturnEngine {
  /// Simula uma posição inicial de uma ação, reinvestindo cada provento
  /// líquido de imposto no fechamento da data de pagamento.
  ///
  /// O direito ao provento é apurado pela posição vigente na **data-ex**;
  /// o caixa entra e é reinvestido na **data de pagamento**.
  ///
  /// - [prices]: série de fechamentos do ativo.
  /// - [dividends]: proventos do ativo. Só entram os de data-ex **dentro** do
  ///   período simulado; os anteriores pertencem a quem detinha a ação antes.
  /// - [taxPolicy]: define quanto de cada provento chega ao caixa.
  /// - [range]: recorte opcional. Sem ele, usa a série inteira.
  ///
  /// Retorna série com [TotalReturnSeries.index] partindo de 1,0. Devolve série
  /// vazia — não uma falha — quando nenhum pregão sobra após o recorte.
  ///
  /// **Precondição:** o fechamento do primeiro pregão do recorte deve ser
  /// positivo. Ele é o denominador do índice, e um zero ali propagaria
  /// `Infinity` por toda a série. Séries reais não têm fechamento zero, e não
  /// há guarda para não mascarar dado corrompido da fonte.
  ///
  /// Complexidade **O(p · e)**: para cada pregão varre a lista de proventos
  /// elegíveis duas vezes. Aceitável porque `e` é da ordem de dezenas — cinco
  /// anos de proventos trimestrais dão ~20 eventos contra ~1250 pregões.
  static TotalReturnSeries build({
    required PriceSeries prices,
    required List<DividendEvent> dividends,
    required TaxPolicy taxPolicy,
    DateRange? range,
  }) {
    final points = range == null
        ? prices.points
        : prices.points.where((p) => range.contains(p.date)).toList();

    if (points.isEmpty) {
      return const TotalReturnSeries(
        dates: [],
        index: [],
        grossDividendsPerShare: 0,
        withheldTaxPerShare: 0,
      );
    }

    final first = points.first.date;
    final last = points.last.date;

    // Somente eventos cuja data-ex cai dentro do período simulado: proventos
    // com data-ex anterior pertencem a quem detinha a ação antes do início.
    final relevant = dividends
        .where((d) => !d.exDate.isBefore(first) && !d.exDate.isAfter(last))
        .toList()
      ..sort((a, b) => a.exDate.compareTo(b.exDate));

    // Posição com direito a cada provento, apurada na data-ex.
    final entitlement = <int, double>{};
    final paid = <int>{};

    var shares = 1.0;
    final startPrice = points.first.close;
    var gross = 0.0;
    var withheld = 0.0;

    final dates = <DateTime>[];
    final index = <double>[];

    for (final point in points) {
      final today = point.date;

      // 1) Registra o direito para eventos cuja data-ex já passou.
      for (var i = 0; i < relevant.length; i++) {
        if (entitlement.containsKey(i)) continue;
        if (!relevant[i].exDate.isAfter(today)) {
          entitlement[i] = shares;
        }
      }

      // 2) Credita e reinveste eventos cuja data de pagamento já chegou.
      for (var i = 0; i < relevant.length; i++) {
        if (paid.contains(i)) continue;
        final event = relevant[i];
        if (event.paymentDate.isAfter(today)) continue;
        final held = entitlement[i];
        if (held == null) continue;

        final net = taxPolicy.netAmount(event) * held;
        gross += event.amountPerShare * held;
        withheld += taxPolicy.withheldAmount(event) * held;

        if (point.close > 0 && net > 0) {
          shares += net / point.close;
        }
        paid.add(i);
      }

      dates.add(today);
      index.add(shares * point.close / startPrice);
    }

    return TotalReturnSeries(
      dates: dates,
      index: index,
      grossDividendsPerShare: gross,
      withheldTaxPerShare: withheld,
    );
  }
}
