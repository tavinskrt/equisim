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

  /// Como calcular o valor terminal. Padrão [TerminalValueMethod.gordon].
  final TerminalValueMethod terminalMethod;

  /// Múltiplo EV/EBITDA de saída — usado quando [terminalMethod] é
  /// [TerminalValueMethod.exitMultiple].
  final double? exitMultiple;

  /// Margem de segurança sobre o preço justo, em fração.
  final double marginOfSafety;

  /// Declara as premissas. **Não valida** — a consistência entre desconto e
  /// crescimento perpétuo é conferida em [DcfCalculator], que devolve [Result].
  const DcfAssumptions({
    this.projectionYears = 5,
    required this.growthRate,
    required this.perpetualGrowth,
    required this.discountRate,
    this.terminalMethod = TerminalValueMethod.gordon,
    this.exitMultiple,
    this.marginOfSafety = 0.0,
  });

  /// Cópia com os campos informados substituídos.
  ///
  /// **Não permite anular [exitMultiple]**: passar `null` preserva o valor
  /// atual, como em todo `copyWith` de argumento anulável. É o suficiente aqui
  /// porque o motor de cenários só desloca crescimento e desconto.
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
  /// Fluxos projetados do ano 1 ao ano N, **antes** de descontar.
  final List<double> projectedFlows;

  /// Os mesmos fluxos trazidos a valor presente, alinhados posição a posição
  /// com [projectedFlows].
  final List<double> discountedFlows;

  /// Valor terminal no ano N, em valor futuro.
  final double terminalValue;

  /// Valor terminal trazido a presente.
  final double discountedTerminalValue;

  /// Valor da firma: soma dos fluxos descontados mais o terminal descontado.
  ///
  /// No modelo por LPA não há EV de verdade — o campo repete
  /// [fairValuePerShare], porque o cálculo já parte do acionista.
  final double enterpriseValue;

  /// Valor do equity: [enterpriseValue] menos a dívida líquida.
  final double equityValue;

  /// Preço justo por papel. É o número que vira `ValuationResult.fairValue`,
  /// depois de convertido para a unidade de negociação quando o ativo é unit.
  final double fairValuePerShare;

  /// Parcela do valor total explicada pelo valor terminal.
  ///
  /// Acima de ~75% é sinal de alerta: o resultado passa a depender mais da
  /// premissa de perpetuidade do que da projeção explícita.
  final double terminalShare;

  /// Agrupa a saída já calculada.
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

/// Os três modelos de fluxo descontado do pacote.
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
  ///
  /// - [baseFreeCashFlow]: fluxo de caixa livre do exercício-base, já
  ///   normalizado por `BaseFlowNormalizer`. Deve ser positivo.
  /// - [assumptions]: crescimento, desconto e método terminal. O desconto
  ///   **precisa ser o WACC** — Ke aqui subavalia a empresa.
  /// - [netDebt]: dívida líquida a descontar do EV. Negativa em empresa com
  ///   caixa líquido.
  /// - [sharesOutstanding]: papéis em circulação. Deve ser positivo.
  /// - [terminalEbitda]: EBITDA do ano terminal. Obrigatório apenas quando
  ///   [assumptions] pede múltiplo de saída.
  ///
  /// Devolve [InsufficientData] para ações em circulação ausentes ou fluxo-base
  /// não positivo; [InvalidInput] para menos de um ano de projeção ou desconto
  /// não positivo; [ComputationFailure] quando a perpetuidade diverge (spread
  /// menor que [minimumSpread]) ou o valor por ação não é finito.
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
  ///
  /// - [baseEps]: lucro por ação do exercício-base. Deve ser positivo.
  /// - [assumptions]: o desconto aqui **precisa ser Ke**, não WACC — o fluxo já
  ///   é do acionista.
  ///
  /// Devolve [InsufficientData] para LPA não positivo e [InvalidInput] para
  /// desconto não positivo.
  ///
  /// **Difere de [fcff] no tratamento do spread:** em vez de recusar quando
  /// `r − g_∞` fica abaixo de [minimumSpread], aplica o mínimo como piso e
  /// segue. O resultado é limitado em vez de ausente, o que é aceitável num
  /// modelo já declarado como simplificado — mas significa que este método
  /// **nunca** falha por divergência de perpetuidade.
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
  ///
  /// - [lastDividendPerShare]: proventos dos últimos doze meses por papel.
  ///   Deve ser positivo.
  /// - [costOfEquity]: Ke anual em fração.
  /// - [growthRate]: crescimento perpétuo dos dividendos, em fração.
  ///
  /// Retorna o preço justo por papel.
  ///
  /// Devolve [InsufficientData] sem histórico de dividendos e
  /// [ComputationFailure] quando `Ke − g` fica abaixo de [minimumSpread] — aqui
  /// a divergência **é** recusada, ao contrário de [earningsPerShare], porque
  /// não há período explícito para amortecer a perpetuidade.
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
