/// Alavancagem de mercado medida na mesma janela em que o beta é estimado.
library;

import '../../entities/fundamentals.dart';
import '../../entities/price_series.dart';
import '../../value_objects/date_range.dart';
import '../valuation/inference.dart';

/// A alavancagem que o beta observado carrega.
///
/// **Por que existe.** O beta é covariância de cinco anos de retorno diário, e
/// portanto reflete a estrutura de capital **daqueles cinco anos**.
/// Desalavancá-lo com a foto de hoje mistura janelas: se a empresa alavancou
/// no período, a foto é maior que a média e o `β_U` sai pequeno demais; se
/// desalavancou, o contrário.
///
/// Medido em 11/09/2026 sobre 124 ativos com ao menos três exercícios na
/// janela: o fator da janela difere do de hoje em mais de 10% em **50** deles
/// e em mais de 25% em **24**. A CPLE3 aparece com 386,1% de dívida sobre
/// valor de mercado hoje contra 49,8% de mediana na janela.
///
/// **A mediana e não a média.** Um exercício de valor de mercado deprimido —
/// fundo de crise, evento societário — domina a média e não a mediana, e o que
/// se quer é a estrutura típica do período, não a pior dela.
abstract final class MarketLeverage {
  /// Distância máxima, em dias, entre o fim do exercício e o pregão usado.
  ///
  /// Vinte dias cobrem feriado prolongado e recesso sem alcançar o exercício
  /// vizinho. Sem pregão dentro disso o exercício não entra: preço de outro
  /// trimestre não descreve o valor de mercado daquele fechamento.
  static const int maxPregaoDistanteEmDias = 20;

  /// Exercícios mínimos na janela para a mediana descrever alguma coisa.
  static const int minExercicios = 3;

  /// Mediana de `dívida líquida ÷ valor de mercado` nos exercícios da janela.
  ///
  /// O valor de mercado de cada exercício é o **preço do pregão mais próximo
  /// do fechamento** vezes a contagem de ações **daquele exercício** — nunca a
  /// corrente, que descreve a empresa de hoje e não a de então.
  ///
  /// Devolve `null` com menos de [minExercicios] pares utilizáveis, e aí o
  /// chamador recua para a foto — que é o comportamento anterior, declarado.
  static double? overWindow({
    required List<FundamentalsSnapshot> snapshots,
    required List<PricePoint> prices,
    required DateRange window,
  }) {
    if (prices.isEmpty) return null;
    final razoes = <double>[];
    for (final s in snapshots) {
      if (!window.contains(s.fiscalPeriodEnd)) continue;
      final acoes = s.sharesOutstandingAsOf;
      if (acoes == null || acoes <= 0) continue;

      PricePoint? maisProximo;
      var menorDistancia = maxPregaoDistanteEmDias + 1;
      final fim = _emDias(s.fiscalPeriodEnd);
      for (final p in prices) {
        final d = (_emDias(p.date) - fim).abs();
        if (d < menorDistancia) {
          menorDistancia = d;
          maisProximo = p;
        }
      }
      if (maisProximo == null) continue;

      final valorDeMercado = maisProximo.close * acoes;
      final de = s.debtToMarketEquity(valorDeMercado);
      if (de != null) razoes.add(de);
    }
    if (razoes.length < minExercicios) return null;
    final m = Inference.median(razoes);
    return (m != null && m.isFinite) ? m : null;
  }

  /// Dias desde a época, contados em UTC.
  ///
  /// **`difference().inDays` entre datas locais não é contagem de dias.** Numa
  /// transição de horário de verão o intervalo entre duas meias-noites tem 23
  /// ou 25 horas, e o truncamento para dias erra por um. O erro é pequeno e a
  /// escolha do pregão mais próximo é decidida por diferenças de poucos dias —
  /// exatamente onde um dia decide.
  static int _emDias(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
