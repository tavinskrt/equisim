import 'dart:math' as math;

import '../entities/asset.dart';
import '../entities/fundamentals.dart';
import '../entities/price_series.dart';
import '../failures/result.dart';
import '../value_objects/date_range.dart';
import '../value_objects/ticker.dart';

/// Frequência de uma série de taxas, e quantos períodos dela cabem num ano.
///
/// **Existe para que a base não viaje por parâmetro** (decisão 59). O
/// `annualized({periodsPerYear})` deixava a série muda sobre a própria
/// frequência e o chamador responsável por acertá-la — e a documentação
/// avisava que "errar esta base desloca o resultado em ordens de grandeza".
/// Uma série mensal anualizada em base 252 devolve número plausível e errado
/// por vinte vezes.
enum TimeBasis {
  /// Dias úteis, base em que o BCB publica o CDI.
  businessDaily(252),

  /// Meses, base do IPCA e do IBC-Br.
  monthly(12);

  /// Períodos desta base que cabem num ano.
  final int periodsPerYear;

  const TimeBasis(this.periodsPerYear);
}

/// Um ponto de uma série de taxas: a data e a taxa daquele período.
///
/// **Existe para que a data e a taxa não possam se separar** (decisão 59). A
/// série guardava duas listas prometidas alinhadas posição a posição, e o
/// alinhamento era responsabilidade de quem construía; o repositório de cache
/// iterava `rates` indexando `dates`, que é exatamente o caminho em que a
/// promessa quebrada vira exceção de índice longe da origem.
class RatePoint {
  /// Data do período.
  final DateTime date;

  /// Taxa do período, em fração (0.0004 = 0,04% no dia).
  final double rate;

  /// Declara o ponto.
  const RatePoint({required this.date, required this.rate});
}

/// Série de taxas diárias (CDI, IPCA), já convertidas para fração.
class RateSeries {
  /// Pontos da série, na ordem em que a fonte os publicou.
  final List<RatePoint> points;

  /// Frequência dos pontos. É ela que define a base da anualização.
  final TimeBasis basis;

  /// Declara a série.
  ///
  /// **Não há construtor por listas paralelas**, e a ausência é a decisão: com
  /// um ponto por período, não existe estado em que a data e a taxa discordem
  /// em quantidade.
  const RateSeries(this.points, {this.basis = TimeBasis.businessDaily});

  /// Série vazia, para recuo de chamador sem dado.
  static const RateSeries empty = RateSeries([]);

  /// Datas dos períodos. **Vista derivada** — a fonte da verdade é [points].
  List<DateTime> get dates => [for (final p in points) p.date];

  /// Taxas dos períodos. **Vista derivada** — a fonte da verdade é [points].
  List<double> get rates => [for (final p in points) p.rate];

  /// `true` quando não há nenhum ponto.
  bool get isEmpty => points.isEmpty;

  /// Os [n] últimos pontos, ou a série inteira se ela for mais curta.
  RateSeries tail(int n) => n >= points.length
      ? this
      : RateSeries(points.sublist(points.length - n), basis: basis);

  /// Fator acumulado do período: `Π(1 + rᵢ) − 1`.
  double get accumulated {
    var factor = 1.0;
    for (final p in points) {
      factor *= 1 + p.rate;
    }
    return factor - 1;
  }

  /// Taxa anual equivalente, na base que a própria série declara.
  ///
  /// Converte por **composição** sobre o fator acumulado, nunca multiplicando
  /// a taxa média pelo número de períodos.
  ///
  /// **A base vem de [basis], e não por parâmetro** (decisão 59): errá-la
  /// desloca o resultado em ordens de grandeza, e quem sabe a frequência é
  /// quem construiu a série, não quem a consome.
  ///
  /// Devolve `0.0` para série vazia e `-1.0` (perda total) quando o fator
  /// acumulado é não positivo, evitando raiz de número negativo.
  double annualized() {
    if (points.isEmpty) return 0.0;
    final years = points.length / basis.periodsPerYear;
    if (years <= 0) return 0.0;
    final factor = 1 + accumulated;
    if (factor <= 0) return -1.0;
    return math.pow(factor, 1 / years).toDouble() - 1;
  }
}

/// Acesso a cotações.
///
/// Contrato comum a todas as implementações: ausência de dado é [Result] de
/// falha, **nunca exceção nem lista vazia**. A série devolvida pode ser mais
/// curta que [DateRange] pedido — o ativo pode ter listado depois do início —,
/// e cabe ao chamador conferir as pontas.
abstract interface class PriceRepository {
  /// Cotações diárias de um ativo na janela pedida.
  ///
  /// - [ticker]: ativo.
  /// - [range]: janela desejada, com as duas pontas inclusivas.
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range);

  /// Busca em lote: uma requisição em vez de N.
  ///
  /// - [tickers]: ativos desejados.
  /// - [range]: janela comum a todos.
  ///
  /// O mapa devolvido pode ser **parcial**: ativos sem dado ficam de fora em
  /// vez de derrubar o lote inteiro.
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  );

  /// `adjustedClose` bruto da fonte — **apenas conferência**, nunca cálculo.
  /// A série embute proventos, que o domínio não modela; o cálculo usa
  /// `close`.
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker ticker, DateRange range);
}

/// Acesso a fundamentos. Devolve a série completa; o recorte temporal é
/// responsabilidade de `PointInTimeView`.
abstract interface class FundamentalsRepository {
  /// Todos os exercícios disponíveis do ativo, em ordem cronológica.
  ///
  /// Sem filtro de publicação: quem aplica o recorte *point-in-time* é
  /// `PointInTimeView`. Devolver aqui a série já filtrada esconderia do
  /// consumidor quantos exercícios existem contra quantos eram públicos.
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker);

  /// Perfil cadastral do ativo — nome e classificação setorial.
  Future<Result<Asset>> profile(Ticker ticker);

  /// Universo de ativos elegíveis. Define o que o usuário pode escolher.
  Future<Result<List<Ticker>>> universe();
}

/// Variáveis macroeconômicas.
abstract interface class MacroRepository {
  /// CDI diário (BCB SGS 12) — taxa livre de risco do CAPM e do Sharpe.
  Future<Result<RateSeries>> riskFreeDaily(DateRange range);

  /// IPCA mensal (BCB SGS 433) — retorno real.
  Future<Result<RateSeries>> inflationMonthly(DateRange range);

  /// IBC-Br dessazonalizado (BCB SGS 24364) — proxy mensal do produto real.
  ///
  /// Alimenta a parcela **real** do teto da perpetuidade. É índice, não taxa:
  /// só razões entre pontos têm sentido.
  Future<Result<RateSeries>> activityIndexMonthly(DateRange range);
}

/// Índice de mercado, para Rm e para o cálculo local de beta.
abstract interface class BenchmarkRepository {
  /// Série do Ibovespa (^BVSP) na janela pedida.
  ///
  /// É índice de **retorno total por construção** — diferença de convenção
  /// diante do `close` dos ativos, que não embute provento.
  Future<Result<PriceSeries>> ibovespa(DateRange range);
}
