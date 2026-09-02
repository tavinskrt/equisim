import 'dart:math' as math;

import '../../failures/failure.dart';
import '../../failures/result.dart';
import '../../value_objects/money.dart';
import '../../value_objects/paired_series.dart';

/// Movimentação externa de capital, datada.
///
/// Convenção de sinal: aporte é **negativo** (saída do bolso do investidor),
/// resgate e valor final são **positivos**. É a convenção da TIR.
class CashFlow {
  /// Dia da movimentação, truncado para meia-noite local.
  final DateTime date;

  /// Valor movimentado. Negativo para aporte, positivo para resgate e para o
  /// valor final da posição.
  final Money amount;

  /// Constrói o fluxo, truncando [date] para o dia.
  CashFlow({required DateTime date, required this.amount})
      : date = DateTime(date.year, date.month, date.day);

  @override
  String toString() => '${date.toIso8601String().substring(0, 10)}: $amount';
}

/// Pregões por ano, base de anualização.
///
/// 252 é a base de dias úteis da B3 e do Banco Central — a mesma em que Selic e
/// CDI são publicados. Conversão entre bases é sempre por composição
/// (`(1+i)^(1/252) − 1`), nunca por divisão.
const int tradingDaysPerYear = 252;

/// Métricas de retorno de uma carteira.
abstract final class Returns {
  /// **Retorno ponderado pelo tempo (TWR)**.
  ///
  /// Neutraliza o efeito do cronograma de aportes: é a métrica correta para
  /// comparar a qualidade de duas composições de carteira, porque não premia
  /// nem pune a carteira por ter recebido dinheiro em momento favorável.
  ///
  /// Para cada período, `r = (V_t − F_t) / V_{t−1} − 1`, onde `F_t` é o fluxo
  /// externo aportado no período `t` e `V_t` é o valor ao final dele.
  ///
  /// Usar CAGR sobre capital aportado no lugar disto é o erro clássico: trata
  /// 120 aportes mensais como se fossem um único investimento no dia 1.
  ///
  /// - [values]: patrimônio ao final de cada período, em ordem cronológica.
  /// - [path]: patrimônio e fluxo externo de cada período, casados pelo tipo.
  ///   Aporte é positivo em [WealthPath.externalFlows] — convenção oposta à de
  ///   [CashFlow], porque a fórmula subtrai o fluxo do valor final.
  ///
  /// Devolve `0.0` para menos de dois períodos. Períodos abertos com patrimônio
  /// não positivo são **pulados**, não zerados: uma carteira que zera e recebe
  /// aporte novo não contamina o composto com um retorno infinito.
  ///
  /// **Não valida dimensão e não lança.** O `ArgumentError` que abria este
  /// método deixou de existir junto com o par de listas soltas: [WealthPath]
  /// não é construtível desalinhado.
  static double timeWeighted(WealthPath path) {
    final values = path.values;
    final externalFlows = path.externalFlows;
    if (values.length < 2) return 0.0;

    var compounded = 1.0;
    for (var i = 1; i < values.length; i++) {
      final previous = values[i - 1];
      if (previous <= 0) continue;
      final periodReturn = (values[i] - externalFlows[i]) / previous - 1.0;
      compounded *= 1.0 + periodReturn;
    }
    return compounded - 1.0;
  }

  /// Índice de retorno total normalizado em base 100, a partir dos valores da
  /// carteira e dos fluxos externos. É a curva que deve alimentar volatilidade
  /// e drawdown — a curva bruta de patrimônio salta no dia do aporte e
  /// contaminaria as duas métricas.
  ///
  /// - [path]: patrimônio e fluxo externo de cada período, casados pelo tipo.
  /// - [base]: nível inicial do índice. Padrão `100.0`.
  ///
  /// Devolve lista vazia para entrada vazia, e uma lista do mesmo comprimento
  /// de `path.values` caso contrário. O [RangeError] que uma lista de fluxos
  /// mais curta provocava aqui deixou de ser representável.
  static List<double> timeWeightedIndex(
    WealthPath path, {
    double base = 100.0,
  }) {
    final values = path.values;
    final externalFlows = path.externalFlows;
    if (values.isEmpty) return const [];
    final out = <double>[base];
    var level = base;
    for (var i = 1; i < values.length; i++) {
      final previous = values[i - 1];
      if (previous > 0) {
        final periodReturn = (values[i] - externalFlows[i]) / previous - 1.0;
        level *= 1.0 + periodReturn;
      }
      out.add(level);
    }
    return out;
  }

  /// Converte um retorno acumulado em taxa anual composta.
  ///
  /// - [totalReturn]: retorno do período inteiro, em fração.
  /// - [years]: duração do período em anos, tipicamente `DateRange.years`.
  ///
  /// Devolve `0.0` para [years] não positivo, e `-1.0` (perda total) quando o
  /// fator de crescimento `1 + totalReturn` é não positivo — a raiz de índice
  /// fracionário de número negativo não existe no domínio real, e devolver
  /// `NaN` propagaria em silêncio até a interface.
  static double annualize(double totalReturn, double years) {
    if (years <= 0) return 0.0;
    final growth = 1.0 + totalReturn;
    if (growth <= 0) return -1.0;
    return math.pow(growth, 1.0 / years).toDouble() - 1.0;
  }

  /// **Taxa interna de retorno de fluxos datados (XIRR)**.
  ///
  /// É o retorno efetivo do investidor: pondera cada real pelo tempo em que
  /// ficou investido. É o número a confrontar com a rentabilidade requerida
  /// da meta.
  ///
  /// Resolve `Σ CF_i / (1+r)^(d_i/365) = 0` por Newton-Raphson com bisseção
  /// de resguardo.
  ///
  /// A base de contagem é **365 dias corridos**, não 252 úteis: os fluxos são
  /// datados em calendário, e a TIR estendida é definida sobre tempo corrido.
  ///
  /// - [flows]: movimentações datadas. A ordem não importa — são ordenadas
  ///   internamente. Aporte negativo, resgate e valor final positivos.
  /// - [guess]: chute inicial de Newton, ao ano. Padrão `0.1`.
  /// - [tolerance]: critério de parada sobre o VPL e sobre o passo. Padrão
  ///   `1e-9`.
  /// - [maxIterations]: teto por método. Padrão `200`.
  ///
  /// Retorna a taxa **anual** em fração.
  ///
  /// Devolve [InsufficientData] com menos de dois fluxos; [InvalidInput] se
  /// faltar fluxo positivo ou negativo — sem troca de sinal não há raiz;
  /// [ComputationFailure] quando a bisseção não consegue isolar a raiz no
  /// intervalo `[-99,99%, 10000%]`.
  ///
  /// **Ressalva de convergência:** esgotado [maxIterations] na bisseção sem
  /// atingir [tolerance], o ponto médio corrente é devolvido como [Ok]. Com o
  /// intervalo padrão isso exigiria mais de 200 bisseções para uma faixa de
  /// largura ~101, o que não ocorre na prática — mas o contrato não distingue
  /// esse retorno de uma convergência plena.
  ///
  /// Fluxos com mais de uma troca de sinal admitem múltiplas raízes (regra de
  /// Descartes); aqui devolve-se a primeira encontrada, sem sinalizar as
  /// demais.
  static Result<double> extendedIrr(
    List<CashFlow> flows, {
    double guess = 0.1,
    double tolerance = 1e-9,
    int maxIterations = 200,
  }) {
    if (flows.length < 2) {
      return const Err(InsufficientData('XIRR exige ao menos dois fluxos.'));
    }

    final hasPositive = flows.any((f) => f.amount.cents > 0);
    final hasNegative = flows.any((f) => f.amount.cents < 0);
    if (!hasPositive || !hasNegative) {
      return const Err(InvalidInput(
        'XIRR exige ao menos um fluxo positivo e um negativo.',
      ));
    }

    final sorted = [...flows]..sort((a, b) => a.date.compareTo(b.date));
    final origin = sorted.first.date;
    final years = sorted
        .map((f) => f.date.difference(origin).inDays / 365.0)
        .toList(growable: false);
    final amounts =
        sorted.map((f) => f.amount.reais).toList(growable: false);

    double npv(double rate) {
      var total = 0.0;
      for (var i = 0; i < amounts.length; i++) {
        total += amounts[i] / math.pow(1.0 + rate, years[i]);
      }
      return total;
    }

    // Newton-Raphson.
    var rate = guess;
    for (var iteration = 0; iteration < maxIterations; iteration++) {
      if (rate <= -1.0) break;
      var value = 0.0;
      var derivative = 0.0;
      for (var i = 0; i < amounts.length; i++) {
        final discount = math.pow(1.0 + rate, years[i]).toDouble();
        value += amounts[i] / discount;
        derivative -= years[i] * amounts[i] / (discount * (1.0 + rate));
      }
      if (value.abs() < tolerance) return Ok(rate);
      if (derivative.abs() < 1e-14) break;
      final next = rate - value / derivative;
      if (!next.isFinite) break;
      if ((next - rate).abs() < tolerance) return Ok(next);
      rate = next;
    }

    // Bisseção de resguardo quando Newton diverge.
    return _bisect(npv, -0.9999, 100.0, tolerance, maxIterations);
  }

  /// Bisseção sobre [f] no intervalo `[lo, hi]`.
  ///
  /// Exige troca de sinal entre as pontas — é o que garante a existência da
  /// raiz. Esgotado [maxIterations], devolve o ponto médio corrente como [Ok]
  /// sem sinalizar a não convergência; ver a ressalva em [extendedIrr].
  static Result<double> _bisect(
    double Function(double) f,
    double lo,
    double hi,
    double tolerance,
    int maxIterations,
  ) {
    var low = lo;
    var high = hi;
    var fLow = f(low);
    final fHigh = f(high);
    if (fLow.isNaN || fHigh.isNaN || fLow * fHigh > 0) {
      return const Err(ComputationFailure(
        'Não foi possível isolar a raiz: a função não muda de sinal no intervalo.',
      ));
    }
    for (var i = 0; i < maxIterations; i++) {
      final mid = (low + high) / 2.0;
      final fMid = f(mid);
      if (fMid.abs() < tolerance || (high - low) / 2.0 < tolerance) {
        return Ok(mid);
      }
      if (fLow * fMid < 0) {
        high = mid;
      } else {
        low = mid;
        fLow = fMid;
      }
    }
    return Ok((low + high) / 2.0);
  }
}
