import 'dart:math' as math;

import '../../entities/valuation.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';

/// Premissas de uma rodada de DCF.
class DcfAssumptions {
  /// Anos de projeção explícita.
  final int projectionYears;

  /// Crescimento anual do fluxo no período explícito, em fração.
  final double growthRate;

  /// Crescimento na perpetuidade, em fração.
  final double perpetualGrowth;

  /// Taxa de desconto anual, em fração. Para FCFF deve ser o **WACC**.
  final double discountRate;

  final TerminalValueMethod terminalMethod;

  /// Múltiplo EV/EBITDA de saída — usado quando [terminalMethod] é
  /// [TerminalValueMethod.exitMultiple].
  final double? exitMultiple;

  /// Margem de segurança sobre o preço justo, em fração.
  final double marginOfSafety;

  const DcfAssumptions({
    this.projectionYears = 5,
    required this.growthRate,
    required this.perpetualGrowth,
    required this.discountRate,
    this.terminalMethod = TerminalValueMethod.gordon,
    this.exitMultiple,
    this.marginOfSafety = 0.0,
  });

  DcfAssumptions copyWith({
    int? projectionYears,
    double? growthRate,
    double? perpetualGrowth,
    double? discountRate,
    TerminalValueMethod? terminalMethod,
    double? exitMultiple,
    double? marginOfSafety,
  }) =>
      DcfAssumptions(
        projectionYears: projectionYears ?? this.projectionYears,
        growthRate: growthRate ?? this.growthRate,
        perpetualGrowth: perpetualGrowth ?? this.perpetualGrowth,
        discountRate: discountRate ?? this.discountRate,
        terminalMethod: terminalMethod ?? this.terminalMethod,
        exitMultiple: exitMultiple ?? this.exitMultiple,
        marginOfSafety: marginOfSafety ?? this.marginOfSafety,
      );
}

/// Saída bruta de um DCF, antes de virar [ValuationResult].
class DcfOutcome {
  final List<double> projectedFlows;
  final List<double> discountedFlows;
  final double terminalValue;
  final double discountedTerminalValue;
  final double enterpriseValue;
  final double equityValue;
  final double fairValuePerShare;

  /// Parcela do valor total explicada pelo valor terminal.
  ///
  /// Acima de ~75% é sinal de alerta: o resultado passa a depender mais da
  /// premissa de perpetuidade do que da projeção explícita.
  final double terminalShare;

  const DcfOutcome({
    required this.projectedFlows,
    required this.discountedFlows,
    required this.terminalValue,
    required this.discountedTerminalValue,
    required this.enterpriseValue,
    required this.equityValue,
    required this.fairValuePerShare,
    required this.terminalShare,
  });
}

abstract final class DcfCalculator {
  /// Distância mínima entre taxa de desconto e crescimento perpétuo.
  ///
  /// A perpetuidade de Gordon explode quando `r → g`; sem um piso, um erro de
  /// 1 p.p. na premissa produz valores absurdos em vez de um erro visível.
  static const double minimumSpread = 0.005;

  /// DCF por FCFF, descontado ao WACC.
  ///
  /// `EV = Σ FCFF_t/(1+WACC)^t + VT/(1+WACC)^N`
  /// `Equity = EV − dívida líquida`
  static Result<DcfOutcome> fcff({
    required double baseFreeCashFlow,
    required DcfAssumptions assumptions,
    required double netDebt,
    required double sharesOutstanding,
    double? terminalEbitda,
  }) {
    if (sharesOutstanding <= 0) {
      return const Err(InsufficientData(
        'Quantidade de ações em circulação indisponível ou inválida.',
      ));
    }
    if (assumptions.projectionYears < 1) {
      return const Err(InvalidInput('Anos de projeção deve ser ao menos 1.'));
    }
    if (assumptions.discountRate <= 0) {
      return const Err(InvalidInput('Taxa de desconto deve ser positiva.'));
    }
    if (baseFreeCashFlow <= 0) {
      return const Err(InsufficientData(
        'Fluxo de caixa livre base não positivo: DCF não é aplicável. '
        'Considere um modelo alternativo.',
      ));
    }

    final r = assumptions.discountRate;
    final g = assumptions.growthRate;
    final n = assumptions.projectionYears;

    final projected = <double>[];
    final discounted = <double>[];
    var flow = baseFreeCashFlow;
    var sumDiscounted = 0.0;

    for (var t = 1; t <= n; t++) {
      flow = flow * (1.0 + g);
      final pv = flow / math.pow(1.0 + r, t);
      projected.add(flow);
      discounted.add(pv);
      sumDiscounted += pv;
    }

    final terminal = _terminalValue(
      finalFlow: flow,
      assumptions: assumptions,
      terminalEbitda: terminalEbitda,
    );
    if (terminal.isErr) return Err(terminal.failureOrNull!);

    final terminalValue = terminal.unwrap();
    final discountedTerminal = terminalValue / math.pow(1.0 + r, n);

    final enterpriseValue = sumDiscounted + discountedTerminal;
    final equityValue = enterpriseValue - netDebt;
    final perShare = equityValue / sharesOutstanding;

    if (!perShare.isFinite) {
      return const Err(ComputationFailure(
        'Valor por ação não finito: verifique as premissas.',
      ));
    }

    return Ok(DcfOutcome(
      projectedFlows: projected,
      discountedFlows: discounted,
      terminalValue: terminalValue,
      discountedTerminalValue: discountedTerminal,
      enterpriseValue: enterpriseValue,
      equityValue: equityValue,
      fairValuePerShare: perShare,
      terminalShare:
          enterpriseValue > 0 ? discountedTerminal / enterpriseValue : 0.0,
    ));
  }

  /// DCF simplificado sobre lucro por ação, descontado ao **Ke**.
  ///
  /// Usado quando não há demonstrativos suficientes para montar o FCFF.
  /// Produz diretamente o valor do equity por ação, sem passar por EV.
  static Result<DcfOutcome> earningsPerShare({
    required double baseEps,
    required DcfAssumptions assumptions,
  }) {
    if (baseEps <= 0) {
      return const Err(InsufficientData(
        'LPA base não positivo: modelo por lucro não é aplicável.',
      ));
    }
    if (assumptions.discountRate <= 0) {
      return const Err(InvalidInput('Taxa de desconto deve ser positiva.'));
    }

    final r = assumptions.discountRate;
    final g = assumptions.growthRate;
    final n = assumptions.projectionYears;

    final projected = <double>[];
    final discounted = <double>[];
    var eps = baseEps;
    var sumDiscounted = 0.0;

    for (var t = 1; t <= n; t++) {
      eps = eps * (1.0 + g);
      final pv = eps / math.pow(1.0 + r, t);
      projected.add(eps);
      discounted.add(pv);
      sumDiscounted += pv;
    }

    final spread = math.max(r - assumptions.perpetualGrowth, minimumSpread);
    final terminalValue = eps * (1.0 + assumptions.perpetualGrowth) / spread;
    final discountedTerminal = terminalValue / math.pow(1.0 + r, n);
    final perShare = sumDiscounted + discountedTerminal;

    return Ok(DcfOutcome(
      projectedFlows: projected,
      discountedFlows: discounted,
      terminalValue: terminalValue,
      discountedTerminalValue: discountedTerminal,
      enterpriseValue: perShare,
      equityValue: perShare,
      fairValuePerShare: perShare,
      terminalShare: perShare > 0 ? discountedTerminal / perShare : 0.0,
    ));
  }

  /// Modelo de crescimento de Gordon sobre dividendos: `P = D₁ / (Ke − g)`.
  static Result<double> gordonGrowth({
    required double lastDividendPerShare,
    required double costOfEquity,
    required double growthRate,
  }) {
    if (lastDividendPerShare <= 0) {
      return const Err(InsufficientData(
        'Sem histórico de dividendos: modelo de Gordon não é aplicável.',
      ));
    }
    final spread = costOfEquity - growthRate;
    if (spread < minimumSpread) {
      return const Err(ComputationFailure(
        'Custo de capital não supera o crescimento perpétuo por margem '
        'suficiente: a perpetuidade diverge.',
      ));
    }
    return Ok(lastDividendPerShare * (1.0 + growthRate) / spread);
  }

  static Result<double> _terminalValue({
    required double finalFlow,
    required DcfAssumptions assumptions,
    double? terminalEbitda,
  }) {
    switch (assumptions.terminalMethod) {
      case TerminalValueMethod.gordon:
        final spread =
            assumptions.discountRate - assumptions.perpetualGrowth;
        if (spread < minimumSpread) {
          return const Err(ComputationFailure(
            'Taxa de desconto não supera o crescimento perpétuo por margem '
            'suficiente: o valor terminal de Gordon diverge. Reduza o '
            'crescimento perpétuo ou use múltiplo de saída.',
          ));
        }
        return Ok(finalFlow * (1.0 + assumptions.perpetualGrowth) / spread);

      case TerminalValueMethod.exitMultiple:
        final multiple = assumptions.exitMultiple;
        if (multiple == null || multiple <= 0) {
          return const Err(InsufficientData(
            'Múltiplo de saída não informado.',
          ));
        }
        if (terminalEbitda == null || terminalEbitda <= 0) {
          return const Err(InsufficientData(
            'EBITDA terminal indisponível para aplicar múltiplo de saída.',
          ));
        }
        return Ok(terminalEbitda * multiple);
    }
  }
}
