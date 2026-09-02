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

  /// Taxa de retenção implícita num crescimento, pela relação de crescimento
  /// sustentável `g = ROE × b`.
  ///
  /// - [growth]: crescimento pretendido, em fração.
  /// - [returnOnEquity]: retorno sobre o patrimônio líquido, em fração.
  ///
  /// **Por que isto existe.** Um lucro que cresce exige reinvestimento: parte
  /// dele fica na empresa para financiar o capital de giro e o imobilizado que
  /// sustentam o crescimento. Descontar o lucro **inteiro** como se todo ele
  /// chegasse ao acionista *e* fazê-lo crescer conta o mesmo dinheiro duas
  /// vezes, e infla o preço justo.
  ///
  /// Devolve a fração retida em `[0, 1)`, ou `null` quando a relação não se
  /// sustenta: sem ROE utilizável, ou com um crescimento que exigiria reter
  /// **todo** o lucro (`b ≥ 1`) — caso em que o crescimento não é financiável
  /// pelo próprio resultado e a premissa está errada, não apertada.
  static double? retentionFor({
    required double growth,
    required double? returnOnEquity,
  }) {
    if (returnOnEquity == null || returnOnEquity <= 0) return null;
    if (!returnOnEquity.isFinite) return null;
    if (growth <= 0) return 0.0;
    final retention = growth / returnOnEquity;
    return retention >= 1.0 ? null : retention;
  }

  /// DCF simplificado sobre lucro por ação, descontado ao **Ke**.
  ///
  /// Usado quando não há demonstrativos suficientes para montar o FCFF.
  /// Produz diretamente o valor do equity por ação, sem passar por EV.
  ///
  /// - [baseEps]: lucro por ação do exercício-base. Deve ser positivo.
  /// - [assumptions]: o desconto aqui **precisa ser Ke**, não WACC — o fluxo já
  ///   é do acionista.
  /// - [returnOnEquity]: ROE observado, em fração. É o que permite descontar
  ///   apenas a parte **distribuível** do lucro; ver abaixo.
  ///
  /// Devolve [InsufficientData] para LPA não positivo e [InvalidInput] para
  /// desconto não positivo.
  ///
  /// **O fluxo descontado é `LPA × (1 − b)`, não o LPA inteiro.** A retenção
  /// `b` sai de [retentionFor] sobre o ROE informado, uma para o período
  /// explícito e outra para a perpetuidade. Sem isso o modelo distribuía todo
  /// o lucro e ainda o fazia crescer — dupla contagem que inflava o preço
  /// justo de toda empresa em crescimento.
  ///
  /// **Sem ROE utilizável, o crescimento é zerado** e o modelo vira *earnings
  /// power value*: lucro estacionário, valor `LPA / Ke`. É a leitura honesta
  /// quando não há como saber quanto do lucro precisa ficar na empresa —
  /// conservadora por construção, e declarada no resultado.
  ///
  /// **Difere de [fcff] no tratamento do spread:** em vez de recusar quando
  /// `r − g_∞` fica abaixo de [minimumSpread], aplica o mínimo como piso e
  /// segue. O resultado é limitado em vez de ausente, o que é aceitável num
  /// modelo já declarado como simplificado — mas significa que este método
  /// **nunca** falha por divergência de perpetuidade.
  static Result<DcfOutcome> earningsPerShare({
    required double baseEps,
    required DcfAssumptions assumptions,
    double? returnOnEquity,
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
    final n = assumptions.projectionYears;

    // As duas retenções precisam existir juntas: crescer no explícito e não no
    // terminal (ou o inverso) misturaria os dois regimes na mesma conta.
    final explicitRetention = retentionFor(
      growth: assumptions.growthRate,
      returnOnEquity: returnOnEquity,
    );
    final perpetualRetention = retentionFor(
      growth: assumptions.perpetualGrowth,
      returnOnEquity: returnOnEquity,
    );
    final financiable =
        explicitRetention != null && perpetualRetention != null;

    final g = financiable ? assumptions.growthRate : 0.0;
    final gPerpetual = financiable ? assumptions.perpetualGrowth : 0.0;
    final payout = financiable ? 1.0 - explicitRetention : 1.0;
    final terminalPayout = financiable ? 1.0 - perpetualRetention : 1.0;

    final projected = <double>[];
    final discounted = <double>[];
    var eps = baseEps;
    var sumDiscounted = 0.0;

    for (var t = 1; t <= n; t++) {
      eps = eps * (1.0 + g);
      final distributable = eps * payout;
      final pv = distributable / math.pow(1.0 + r, t);
      projected.add(distributable);
      discounted.add(pv);
      sumDiscounted += pv;
    }

    final spread = math.max(r - gPerpetual, minimumSpread);
    final terminalValue = eps * (1.0 + gPerpetual) * terminalPayout / spread;
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
