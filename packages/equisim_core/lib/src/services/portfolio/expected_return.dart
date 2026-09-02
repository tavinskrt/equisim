import 'dart:math' as math;

import '../../entities/portfolio.dart';
import '../../entities/valuation.dart';
import '../../value_objects/ticker.dart';

/// Retorno anual esperado de um ativo, decomposto.
class ExpectedAssetReturn {
  final Ticker ticker;

  /// Valorização total até o preço justo, sem prazo, em fração.
  final double upside;

  /// Parcela anualizada da convergência de preço.
  final double priceConvergence;

  const ExpectedAssetReturn({
    required this.ticker,
    required this.upside,
    required this.priceConvergence,
  });

  /// Retorno esperado ao ano.
  ///
  /// É a convergência de preço e nada mais: o modelo não distribui provento
  /// (ver `docs/decisoes/023-remocao-de-proventos.md`), então somar um *yield*
  /// aqui embutiria um retorno que nenhuma outra tela do trabalho apura.
  double get annual => priceConvergence;
}

/// Converte *upside* de valuation em taxa anual comparável à meta.
///
/// **Problema de unidade que isto resolve**: o upside do DCF é uma valorização
/// *total* (ex.: +40%) sem prazo definido, enquanto a rentabilidade requerida é
/// uma taxa *por período* (ex.: 12% a.a.). Comparar os dois diretamente não
/// significa nada — é preciso declarar em quanto tempo o preço converge para o
/// valor justo.
///
///     r_esperado = (1 + upside)^(1/H) − 1
///
/// **O retorno é só de preço.** O trabalho não modela provento, e a estimativa
/// é portanto conservadora: um acionista que receba dividendo obtém mais que
/// isto. Ver `docs/decisoes/023-remocao-de-proventos.md`.
abstract final class ExpectedReturn {
  /// Horizonte de convergência padrão, em meses.
  ///
  /// 12 meses acompanha a convenção de mercado para preço-alvo. É parâmetro
  /// declarado, não constante escondida: deve aparecer junto do resultado.
  static const int defaultHorizonMonths = 12;

  /// Anualiza um upside total sobre o horizonte [horizonMonths].
  static double annualizedFromUpside(
    double upside, {
    int horizonMonths = defaultHorizonMonths,
  }) {
    if (horizonMonths <= 0) return 0.0;
    final growth = 1.0 + upside;
    if (growth <= 0) return -1.0;
    final years = horizonMonths / 12.0;
    return math.pow(growth, 1.0 / years).toDouble() - 1.0;
  }

  /// Retorno esperado de um ativo.
  static ExpectedAssetReturn forAsset({
    required Ticker ticker,
    required double upside,
    int horizonMonths = defaultHorizonMonths,
  }) =>
      ExpectedAssetReturn(
        ticker: ticker,
        upside: upside,
        priceConvergence:
            annualizedFromUpside(upside, horizonMonths: horizonMonths),
      );

  /// Retorno esperado da carteira: média dos ativos ponderada pelos pesos.
  ///
  /// Ativos sem valuation disponível são ignorados, e os pesos remanescentes
  /// reescalados — reportar o peso faltante é responsabilidade da interface.
  static double forPortfolio({
    required Portfolio portfolio,
    required Map<Ticker, ValuationResult> valuations,
    int horizonMonths = defaultHorizonMonths,
  }) {
    var weighted = 0.0;
    var covered = 0.0;

    for (final entry in portfolio.entries.values) {
      final valuation = valuations[entry.ticker];
      if (valuation == null) continue;
      final expected = forAsset(
        ticker: entry.ticker,
        upside: valuation.upside,
        horizonMonths: horizonMonths,
      );
      weighted += entry.weight.value * expected.annual;
      covered += entry.weight.value;
    }

    if (covered <= 0) return 0.0;
    return weighted / covered;
  }

  /// Fração do peso da carteira que possui valuation disponível.
  static double coverage({
    required Portfolio portfolio,
    required Map<Ticker, ValuationResult> valuations,
  }) {
    var covered = 0.0;
    for (final entry in portfolio.entries.values) {
      if (valuations.containsKey(entry.ticker)) {
        covered += entry.weight.value;
      }
    }
    return covered;
  }
}
