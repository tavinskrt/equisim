import 'dart:math' as math;

import '../entities/asset.dart';
import '../entities/dividend_event.dart';
import '../entities/fundamentals.dart';
import '../entities/price_series.dart';
import '../failures/result.dart';
import '../value_objects/date_range.dart';
import '../value_objects/ticker.dart';

/// Série de taxas diárias (CDI, IPCA), já convertidas para fração.
class RateSeries {
  /// Datas dos períodos, alinhadas posição a posição com [rates].
  final List<DateTime> dates;

  /// Taxa do período correspondente, em fração (0.0004 = 0,04% no dia).
  final List<double> rates;

  /// Declara a série. **Não valida** que [dates] e [rates] tenham o mesmo
  /// comprimento; [annualized] só consulta [rates], então uma divergência
  /// passa despercebida até alguém indexar as duas em paralelo.
  const RateSeries({required this.dates, required this.rates});

  /// `true` quando não há nenhuma taxa. Note que olha [rates], não [dates].
  bool get isEmpty => rates.isEmpty;

  /// Fator acumulado do período: `Π(1 + rᵢ) − 1`.
  double get accumulated {
    var factor = 1.0;
    for (final r in rates) {
      factor *= 1 + r;
    }
    return factor - 1;
  }

  /// Taxa anual equivalente, dado o número de períodos por ano.
  ///
  /// Converte por **composição** sobre o fator acumulado, nunca multiplicando
  /// a taxa média pelo número de períodos.
  ///
  /// - [periodsPerYear]: base de contagem. `252` para série diária de CDI —
  ///   dias úteis, a base em que o BCB publica —, `12` para série mensal de
  ///   IPCA. Errar esta base desloca o resultado em ordens de grandeza.
  ///
  /// Devolve `0.0` para série vazia e `-1.0` (perda total) quando o fator
  /// acumulado é não positivo, evitando raiz de número negativo.
  double annualized({int periodsPerYear = 252}) {
    if (rates.isEmpty) return 0.0;
    final years = rates.length / periodsPerYear;
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
  /// A série subajusta proventos brasileiros; o retorno total de verdade é
  /// construído no domínio por `TotalReturnEngine`.
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker ticker, DateRange range);
}

/// Acesso a proventos.
abstract interface class DividendRepository {
  /// Histórico completo de proventos do ativo, sem recorte temporal.
  ///
  /// O recorte é do consumidor: `TotalReturnEngine` e `PortfolioBacktest`
  /// filtram por data-ex dentro do período simulado.
  Future<Result<List<DividendEvent>>> history(Ticker ticker);

  /// Histórico em lote. Como no [PriceRepository], o mapa pode ser parcial.
  Future<Result<Map<Ticker, List<DividendEvent>>>> historyBatch(
    List<Ticker> tickers,
  );

  /// Dividend yield dos últimos 12 meses publicado pela fonte.
  ///
  /// Usado como **portão de qualidade**: se divergir do DY calculado a partir
  /// do fluxo de eventos além da tolerância, o ativo é sinalizado em vez de
  /// reportar número errado em silêncio.
  Future<Result<double>> publishedTrailingYield(Ticker ticker);
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
}

/// Índice de mercado, para Rm e para o cálculo local de beta.
abstract interface class BenchmarkRepository {
  /// Série do Ibovespa (^BVSP) na janela pedida.
  ///
  /// É índice de **retorno total por construção**, então dispensa o tratamento
  /// de proventos que `TotalReturnEngine` aplica aos ativos individuais.
  Future<Result<PriceSeries>> ibovespa(DateRange range);
}
