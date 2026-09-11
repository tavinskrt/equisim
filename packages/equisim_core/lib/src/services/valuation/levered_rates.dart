/// Custo de capital que acompanha a alavancagem ano a ano.
library;

import '../../failures/failure.dart';
import '../../failures/result.dart';
import '../metrics/beta_shrinkage.dart';
import 'dcf.dart';

/// Caminho de taxas e de valores resolvido pelo ponto fixo.
class LeveredRates {
  /// `Ke` do ano 1 ao ano N.
  final List<double> costOfEquity;

  /// `WACC` do ano 1 ao ano N.
  final List<double> wacc;

  /// Valor da firma do ano 0 ao ano N — `N + 1` posições.
  final List<double> enterpriseValue;

  /// Capital próprio do ano 0 ao ano N.
  final List<double> equity;

  /// Dívida líquida do ano 0 ao ano N.
  final List<double> debt;

  /// `Ke` de equilíbrio, na alavancagem do ano N.
  final double terminalCostOfEquity;

  /// `WACC` de equilíbrio, na alavancagem do ano N.
  final double terminalWacc;

  /// Iterações consumidas pelo ponto fixo.
  final int iterations;

  /// `true` quando o critério de parada foi alcançado antes do teto.
  final bool converged;

  const LeveredRates({
    required this.costOfEquity,
    required this.wacc,
    required this.enterpriseValue,
    required this.equity,
    required this.debt,
    required this.terminalCostOfEquity,
    required this.terminalWacc,
    required this.iterations,
    required this.converged,
  });

  /// Participação do capital próprio no ano [t], ou `null` quando ela não tem
  /// sentido.
  ///
  /// **Nulo em vez de `NaN`, e a diferença importa.** Com caixa líquido maior
  /// que o próprio negócio, `E + D` fica não positivo e a razão deixa de ter
  /// significado — não é "zero por cento", é "a pergunta não se aplica". O
  /// sentinela de ponto flutuante atravessava a formatação e chegava ao aviso
  /// do usuário como `NaN%`; o nulo obriga quem lê a decidir o que dizer.
  double? equityShareAt(int t) {
    if (t < 0 || t >= enterpriseValue.length) return null;
    final v = enterpriseValue[t];
    if (!v.isFinite || v <= 0) return null;
    final s = equity[t] / v;
    return s.isFinite ? s : null;
  }
}

/// Resolve `Ke` e `WACC` ano a ano contra a alavancagem que a própria avaliação
/// produz.
///
/// **Por que existe.** Um `WACC` único ao longo da projeção **é** a hipótese de
/// `D/V` constante. A projeção da dívida do motor cresce com a base de capital,
/// e o valor da firma cresce a outra taxa — medido em 10/09/2026, `D/V` sai de
/// 0,2868 no ano zero para 0,3789 no ano dez. As duas coisas se contradiziam, e
/// a contradição estava invisível porque nada verificava as duas rotas de
/// avaliação uma contra a outra. Ver
/// [`identidade_das_vias.md`](../../../../../docs/validacao/identidade_das_vias.md).
///
/// **O caminho escolhido foi o da fidelidade**: aceitar que a alavancagem muda
/// e reprecificar o custo do capital próprio a cada ano, em vez de forçar a
/// dívida a seguir o valor. É o que exige o beta **desalavancado** da decisão
/// 40 — sem `β_U` não há como realavancar.
///
/// ```
/// β_L,t  = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
/// Ke_t   = Rf_t + β_L,t · prêmio
/// WACC_t = Ke_t·(E/V)_{t−1} + Kd·(1 − τ)·(D/V)_{t−1}
/// ```
///
/// **A circularidade é resolvida por ponto fixo**, e não por aproximação: as
/// taxas dependem dos valores, que dependem das taxas. Cada iteração reavalia
/// a firma com o caminho de taxas da anterior e recalcula a alavancagem de
/// cada ano; o critério de parada é o valor da firma no ano zero parar de se
/// mover.
abstract final class LeveredCostOfCapital {
  /// Teto de iterações do ponto fixo.
  static const int maxIterations = 100;

  /// Critério de parada: variação relativa do valor no ano zero.
  static const double tolerance = 1e-10;

  /// Amortecimento aplicado à atualização do caminho de capital próprio.
  ///
  /// **Meio a meio, e é conservador.** Sem amortecimento o ponto fixo oscila
  /// em ativo muito alavancado, onde uma queda de `E` eleva `Ke`, que derruba
  /// `E` de novo. A média com a iteração anterior transforma a oscilação em
  /// convergência, ao custo de mais iterações.
  static const double damping = 0.5;

  /// Resolve o caminho de taxas.
  ///
  /// - [baseProfit]: NOPAT do exercício-base, já normalizado.
  /// - [assumptions]: premissas **sem** caminho de desconto; ele é o que se
  ///   resolve aqui. `discountRate` e `terminalDiscountRate` entram como
  ///   chute inicial.
  /// - [netDebt]: dívida líquida no ano zero.
  /// - [unleveredBeta]: `β_U` do ativo, da decisão 40.
  /// - [riskFreePath]: taxa livre de risco do ano 1 ao ano N.
  /// - [terminalRiskFree]: taxa livre de risco de equilíbrio.
  /// - [marketPremium], [costOfDebt], [taxRate]: parâmetros do CAPM e da
  ///   dívida.
  ///
  /// Devolve falha quando a avaliação intermediária não é possível — o que
  /// inclui o caso em que a alavancagem cresce a ponto de o capital próprio
  /// desaparecer.
  static Result<LeveredRates> solve({
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebt,
    required double unleveredBeta,
    required List<double> riskFreePath,
    required double terminalRiskFree,
    required double marketPremium,
    required double costOfDebt,
    required double taxRate,
  }) {
    final n = assumptions.projectionYears;
    if (n < 1) {
      return const Err(InvalidInput('Anos de projeção deve ser ao menos 1.'));
    }
    if (riskFreePath.length != n) {
      return const Err(InvalidInput(
        'Caminho da taxa livre de risco precisa de uma taxa por ano '
        'projetado.',
      ));
    }
    if (!unleveredBeta.isFinite || unleveredBeta < 0) {
      return const Err(InvalidInput(
        'Beta desalavancado indisponível: a realavancagem não é possível.',
      ));
    }

    // A dívida segue a base de capital, que é o que a projeção faz crescer.
    // **É esta a premissa que a rota (b) preserva** — a alternativa seria
    // amarrá-la ao valor, e aí a alavancagem seria constante por construção.
    final divida = <double>[netDebt];
    for (var t = 1; t <= n; t++) {
      divida.add(divida[t - 1] * (1 + assumptions.growthAt(t)));
    }

    final kdLiquido = costOfDebt * (1 - taxRate);

    // Chute inicial: as taxas que a interpolação de dois pontos daria.
    var ke = <double>[
      for (var t = 1; t <= n; t++) assumptions.discountRateAt(t),
    ];
    var wacc = [...ke];
    var keTerminal = assumptions.terminalDiscountRate;
    var waccTerminal = assumptions.terminalDiscountRate;
    List<double>? equityAnterior;

    var iteracoes = 0;
    var convergiu = false;
    var valorAnterior = double.nan;
    late List<double> ev;
    late List<double> equity;

    while (iteracoes < maxIterations) {
      iteracoes++;

      final avaliacao = DcfCalculator.firm(
        baseProfit: baseProfit,
        assumptions: assumptions.copyWith(
          discountRatePath: wacc,
          terminalDiscountRate: waccTerminal,
        ),
        netDebt: 0,
        sharesOutstanding: 1,
      );
      if (avaliacao.isErr) {
        return Err(ComputationFailure(
          '${avaliacao.failureOrNull!.message} (iteração $iteracoes)',
        ));
      }
      final o = avaliacao.unwrap();

      // Valor da firma ano a ano, por acumulação regressiva: o valor no início
      // de um ano é o fluxo daquele ano mais o valor no fim, descontado à taxa
      // daquele ano.
      final v = List<double>.filled(n + 1, 0);
      // O terminal entra levantado por meio ano, pela mesma razão que os
      // fluxos: sem isso o valor que alimenta a alavancagem seria o de
      // convenção de fim de ano, e a razão `D/E` sairia de um valor que a
      // avaliação não usa.
      v[n] = o.terminalValue * assumptions.lift(waccTerminal);
      for (var t = n; t >= 1; t--) {
        final r = wacc[t - 1];
        v[t - 1] = o.projectedFlows[t - 1] * assumptions.lift(r) / (1 + r) +
            v[t] / (1 + r);
      }
      ev = v;

      final e = <double>[for (var t = 0; t <= n; t++) v[t] - divida[t]];
      // Amortecimento contra oscilação em ativo muito alavancado.
      if (equityAnterior != null) {
        for (var t = 0; t <= n; t++) {
          e[t] = damping * e[t] + (1 - damping) * equityAnterior[t];
        }
      }
      equity = e;
      equityAnterior = [...e];

      // Realavancagem: cada ano usa a estrutura do **início** do ano.
      final novoKe = <double>[];
      final novoWacc = <double>[];
      for (var t = 1; t <= n; t++) {
        final eAnterior = e[t - 1];
        final dAnterior = divida[t - 1];
        if (!eAnterior.isFinite || eAnterior <= 0) {
          // **O momento importa.** Falhar na primeira iteração diz que a
          // própria interpolação de dois pontos — que é o recuo — já produz
          // capital próprio negativo com esta dívida; falhar depois diz que o
          // ponto fixo passou por um iterado inviável e a conclusão sobre o
          // ativo é mais fraca. Sem essa distinção o recuo parece legítimo nos
          // dois casos.
          return Err(ComputationFailure(
            'O capital próprio desaparece dentro da projeção (ano ${t - 1}, '
            'iteração $iteracoes): a realavancagem não tem sentido econômico, '
            'e o ativo não é avaliável por fluxo descontado nesta estrutura de '
            'capital.',
          ));
        }
        final de = dAnterior / eAnterior;
        final fator =
            BetaShrinkage.leverageFactor(debtToEquity: de, taxRate: taxRate);
        if (fator == null) {
          return const Err(ComputationFailure(
            'Fator de alavancagem não finito na realavancagem.',
          ));
        }
        final keT = riskFreePath[t - 1] + unleveredBeta * fator * marketPremium;
        // `D` é dívida **líquida** e pode ser negativa: empresa de caixa
        // líquido tem `E + D` menor que `E`, e no limite não positivo. Sem esta
        // guarda o peso do capital próprio divide por zero, e o `WACC` do ano
        // sai infinito sem que nada acuse.
        final vT = eAnterior + dAnterior;
        if (!vT.isFinite || vT <= 0) {
          return const Err(ComputationFailure(
            'Valor da firma não positivo dentro da projeção: o caixa líquido '
            'supera o próprio valor, e o peso do capital no custo médio deixa '
            'de ter sentido.',
          ));
        }
        final pesoE = (eAnterior / vT).clamp(0.0, 1.0).toDouble();
        novoKe.add(keT);
        novoWacc.add(keT * pesoE + kdLiquido * (1 - pesoE));
      }
      ke = novoKe;
      wacc = novoWacc;

      // Equilíbrio: a estrutura do ano N é a que vale na perpetuidade.
      final eN = e[n];
      final dN = divida[n];
      if (eN <= 0) {
        return Err(ComputationFailure(
          'Capital próprio não positivo no fim da projeção (iteração '
          '$iteracoes).',
        ));
      }
      final fatorN = BetaShrinkage.leverageFactor(
        debtToEquity: dN / eN,
        taxRate: taxRate,
      );
      if (fatorN == null) {
        return const Err(ComputationFailure(
          'Fator de alavancagem terminal não finito.',
        ));
      }
      keTerminal = terminalRiskFree + unleveredBeta * fatorN * marketPremium;
      final vN = eN + dN;
      if (!vN.isFinite || vN <= 0) {
        return const Err(ComputationFailure(
          'Valor da firma não positivo no fim da projeção: o peso do capital '
          'no custo médio de equilíbrio deixa de ter sentido.',
        ));
      }
      final pesoEN = (eN / vN).clamp(0.0, 1.0).toDouble();
      waccTerminal = keTerminal * pesoEN + kdLiquido * (1 - pesoEN);

      final valor = e[0];
      if (valorAnterior.isFinite && valorAnterior.abs() > 0) {
        if ((valor - valorAnterior).abs() / valorAnterior.abs() < tolerance) {
          convergiu = true;
          valorAnterior = valor;
          break;
        }
      }
      valorAnterior = valor;
    }

    return Ok(LeveredRates(
      costOfEquity: List.unmodifiable(ke),
      wacc: List.unmodifiable(wacc),
      enterpriseValue: List.unmodifiable(ev),
      equity: List.unmodifiable(equity),
      debt: List.unmodifiable(divida),
      terminalCostOfEquity: keTerminal,
      terminalWacc: waccTerminal,
      iterations: iteracoes,
      converged: convergiu,
    ));
  }

  /// Resolve o `Ke` ano a ano **pelo lado do capital próprio**, sem passar pelo
  /// valor da firma.
  ///
  /// **Por que existe.** A [solve] precisa do valor da firma para conhecer a
  /// alavancagem, e por isso só serve à via da firma. Medido em 10/09/2026: a
  /// via do acionista avalia sozinha 33 dos 120 ativos — instituição
  /// financeira, lucro operacional não sustentado e estrutura de capital
  /// recusada — e em **nenhum** deles a via da firma produz caminho de taxas
  /// para emprestar. Ou o `Ke` da via do acionista é resolvido pelos fluxos
  /// dela mesma, ou continua supondo a alavancagem de hoje perene, que é
  /// exatamente a hipótese que a decisão 41 mediu e descartou.
  ///
  /// A recorrência é a mesma, com o valor vindo do fluxo do acionista:
  ///
  /// ```
  /// E_t     = (LPA_t + E_{t+1}) / (1 + Ke_t)
  /// β_L,t   = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
  /// Ke_t    = Rf_t + β_L,t · prêmio
  /// ```
  ///
  /// **Tudo por papel.** [baseProfit] é o lucro por papel e [netDebtPerShare] é
  /// a dívida líquida dividida pela mesma contagem: `D/E` é razão, e resolvê-la
  /// na escala por papel evita carregar a contagem de ações para dentro do
  /// ponto fixo.
  ///
  /// O [LeveredRates] devolvido descreve a via do acionista, e nela **não há
  /// custo médio**: `wacc` repete `costOfEquity` e `terminalWacc` repete
  /// `terminalCostOfEquity`, porque a taxa que desconta o fluxo é o próprio
  /// `Ke`. `enterpriseValue` sai como `E + D`, que é o valor da firma
  /// *implicado* por esta via — não um valor descontado de fluxo de firma.
  static Result<LeveredRates> solveEquity({
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebtPerShare,
    required double unleveredBeta,
    required List<double> riskFreePath,
    required double terminalRiskFree,
    required double marketPremium,
    required double taxRate,
  }) {
    final n = assumptions.projectionYears;
    if (n < 1) {
      return const Err(InvalidInput('Anos de projeção deve ser ao menos 1.'));
    }
    if (riskFreePath.length != n) {
      return const Err(InvalidInput(
        'Caminho da taxa livre de risco precisa de uma taxa por ano '
        'projetado.',
      ));
    }
    if (!unleveredBeta.isFinite || unleveredBeta < 0) {
      return const Err(InvalidInput(
        'Beta desalavancado indisponível: a realavancagem não é possível.',
      ));
    }

    // A dívida segue a base de capital, como na via da firma — a premissa é a
    // mesma, e trocá-la aqui faria as duas vias divergirem por construção.
    final divida = <double>[netDebtPerShare];
    for (var t = 1; t <= n; t++) {
      divida.add(divida[t - 1] * (1 + assumptions.growthAt(t)));
    }

    var ke = <double>[
      for (var t = 1; t <= n; t++) assumptions.discountRateAt(t),
    ];
    var keTerminal = assumptions.terminalDiscountRate;
    List<double>? equityAnterior;

    var iteracoes = 0;
    var convergiu = false;
    var valorAnterior = double.nan;
    late List<double> equity;

    while (iteracoes < maxIterations) {
      iteracoes++;

      final avaliacao = DcfCalculator.shareholder(
        baseProfit: baseProfit,
        assumptions: assumptions.copyWith(
          discountRatePath: ke,
          terminalDiscountRate: keTerminal,
        ),
      );
      if (avaliacao.isErr) {
        return Err(ComputationFailure(
          '${avaliacao.failureOrNull!.message} (iteração $iteracoes)',
        ));
      }
      final o = avaliacao.unwrap();

      // Capital próprio ano a ano, por acumulação regressiva — a mesma da via
      // da firma, com o fluxo do acionista no lugar do da firma.
      final e = List<double>.filled(n + 1, 0);
      e[n] = o.terminalValue * assumptions.lift(keTerminal);
      for (var t = n; t >= 1; t--) {
        final r = ke[t - 1];
        e[t - 1] = o.projectedFlows[t - 1] * assumptions.lift(r) / (1 + r) +
            e[t] / (1 + r);
      }
      if (equityAnterior != null) {
        for (var t = 0; t <= n; t++) {
          e[t] = damping * e[t] + (1 - damping) * equityAnterior[t];
        }
      }
      equity = e;
      equityAnterior = [...e];

      final novoKe = <double>[];
      for (var t = 1; t <= n; t++) {
        final eAnterior = e[t - 1];
        if (!eAnterior.isFinite || eAnterior <= 0) {
          return Err(ComputationFailure(
            'O capital próprio desaparece dentro da projeção (ano ${t - 1}, '
            'iteração $iteracoes): a realavancagem não tem sentido econômico.',
          ));
        }
        final fator = BetaShrinkage.leverageFactor(
          debtToEquity: divida[t - 1] / eAnterior,
          taxRate: taxRate,
        );
        if (fator == null) {
          return const Err(ComputationFailure(
            'Fator de alavancagem não finito na realavancagem.',
          ));
        }
        novoKe.add(riskFreePath[t - 1] + unleveredBeta * fator * marketPremium);
      }
      ke = novoKe;

      final eN = e[n];
      if (!eN.isFinite || eN <= 0) {
        return Err(ComputationFailure(
          'Capital próprio não positivo no fim da projeção (iteração '
          '$iteracoes).',
        ));
      }
      final fatorN = BetaShrinkage.leverageFactor(
        debtToEquity: divida[n] / eN,
        taxRate: taxRate,
      );
      if (fatorN == null) {
        return const Err(ComputationFailure(
          'Fator de alavancagem terminal não finito.',
        ));
      }
      keTerminal = terminalRiskFree + unleveredBeta * fatorN * marketPremium;

      final valor = e[0];
      if (valorAnterior.isFinite && valorAnterior.abs() > 0) {
        if ((valor - valorAnterior).abs() / valorAnterior.abs() < tolerance) {
          convergiu = true;
          valorAnterior = valor;
          break;
        }
      }
      valorAnterior = valor;
    }

    return Ok(LeveredRates(
      costOfEquity: List.unmodifiable(ke),
      wacc: List.unmodifiable(ke),
      enterpriseValue: List.unmodifiable(
        [for (var t = 0; t <= n; t++) equity[t] + divida[t]],
      ),
      equity: List.unmodifiable(equity),
      debt: List.unmodifiable(divida),
      terminalCostOfEquity: keTerminal,
      terminalWacc: keTerminal,
      iterations: iteracoes,
      converged: convergiu,
    ));
  }
}
