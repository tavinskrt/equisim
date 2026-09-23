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
  /// O beta de equilíbrio, com a convergência do item B15 quando ela é imposta.
  ///
  /// `β_∞ = w·β_L,N + (1 − w)·1` — o ajuste de Blume. Sem imposição, o beta de
  /// equilíbrio é o realavancado do ano N, sem convergência: é o que a
  /// produção faz, e é a premissa que o B15 existe para declarar.
  static double _betaDeEquilibrio(double betaLevered, double? peso) =>
      peso == null ? betaLevered : peso * betaLevered + (1 - peso) * 1.0;

  /// A alavancagem imposta do B15 descreve uma estrutura possível?
  ///
  /// `D/E = −1` é caixa líquido igual ao capital próprio: o valor da firma
  /// zera, e o peso `1/(1 + D/E)` divide por zero. Abaixo disso o caixa supera
  /// o negócio e o peso fica negativo. Recusar é o certo — a imposição é de
  /// diagnóstico, e uma varredura que peça o impossível precisa ouvir isso em
  /// vez de receber `NaN`.
  static bool _alavancagemImpossivel(double? de) =>
      de != null && (!de.isFinite || 1 + de <= 0);

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
  /// - [marketPremium], [taxRate]: parâmetros do CAPM e do escudo fiscal.
  /// - [creditSpread]: **prêmio de crédito** sobre a taxa livre de risco, e não
  ///   o custo da dívida pronto. O `K_d` de cada ano é `Rf_t + spread`, e o de
  ///   equilíbrio é `Rf_∞ + spread` — a mesma classificação sintética que
  ///   `CostOfCapital.effectiveCostOfDebt` aplica, e a mesma leitura da decisão
  ///   31: o prêmio é da empresa e a taxa base é do ano. Antes entrava o custo
  ///   **observado**, `despesa financeira ÷ dívida bruta`, que a decisão 31
  ///   descartou por carregar arrendamento e variação cambial — e que não
  ///   decaía com a curva, de modo que a perpetuidade herdava o juro de hoje
  ///   (item B11).
  ///
  ///   **O prêmio é constante ao longo da projeção, e não por simplificação.**
  ///   Ele sai da dívida líquida sobre o EBITDA, e aqui a dívida cresce a
  ///   `g_t` — o mesmo ritmo do lucro projetado —, de modo que essa razão fica
  ///   **parada por construção** do ano 1 ao N. O que muda ano a ano é a
  ///   alavancagem **a mercado**, `D/E`, que move o beta e não a
  ///   classificação de crédito. Recalcular o prêmio a cada ano devolveria o
  ///   mesmo número (lente `metodo`, 22/09/2026; o teste
  ///   «a dívida cresce ao ritmo do lucro» cobra a premissa).
  ///
  /// - [terminalBetaWeight] e [terminalLeverage]: imposições de diagnóstico do
  ///   item B15, e `null` em produção. A primeira converge o beta **de
  ///   equilíbrio** em direção a 1 — `β_∞ = w·β_L,N + (1 − w)`, o ajuste de
  ///   Blume —; a segunda substitui a alavancagem do ano N pela informada. Elas
  ///   só tocam a perpetuidade: o caminho explícito continua saindo da
  ///   estrutura que a projeção produz.
  ///
  /// Devolve falha quando a avaliação intermediária não é possível — o que
  /// inclui o caso em que a alavancagem cresce a ponto de o capital próprio
  /// desaparecer.
  /// Distância relativa a partir da qual duas soluções do ponto fixo são
  /// **respostas diferentes**, e não o mesmo ponto alcançado por caminhos
  /// diferentes (item B18).
  ///
  /// Um décimo de por cento no valor do ano zero. O critério de parada é de
  /// 1e-10, de modo que duas convergências legítimas ficam muito abaixo disso;
  /// o corte existe para separar convergência de dois pontos fixos distintos,
  /// e não para acomodar imprecisão.
  static const double startIndependence = 0.001;

  /// Resolve o caminho de taxas, **de dois pontos de partida** (item B18).
  ///
  /// **Por que dois.** A versão anterior partia sempre da interpolação de dois
  /// pontos — o recuo que a decisão 41 substituiu — e recusava a estrutura de
  /// capital quando o capital próprio sumia já na primeira iteração. Medido em
  /// 20/09/2026, os 14 ativos que saíram do aplicativo ao ligar o prior foram
  /// recusados **todos** ali: o veredito era do chute, e não do ponto fixo.
  ///
  /// Aqui o ponto fixo é tentado de dois lugares:
  ///
  ///  1. a interpolação de dois pontos, que é o recuo;
  ///  2. o custo de capital **desalavancado** — `Rf_t + β_U·prêmio` —, que é o
  ///     mesmo caminho no limite de dívida zero, e portanto uma partida tão
  ///     legítima quanto a primeira.
  ///
  /// **Um ponto fixo é um ponto fixo**: quando as duas convergem, elas têm de
  /// convergir para o mesmo lugar, e [startIndependence] mede isso. Quando
  /// divergem, o resultado não é do modelo — é de onde a conta começou —, e o
  /// aviso diz isso. Quando só uma converge, vale ela: recusar por causa de um
  /// chute infeliz é justamente o defeito que o item nomeia.
  static Result<LeveredRates> solve({
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebt,
    required double unleveredBeta,
    required List<double> riskFreePath,
    required double terminalRiskFree,
    required double marketPremium,
    required double creditSpread,
    required double taxRate,
    double? cash,
    double? terminalBetaWeight,
    double? terminalLeverage,
    List<String>? warnings,
  }) {
    Result<LeveredRates> de(List<double>? inicial, double? terminalInicial) =>
        _tentar(
          waccInicial: inicial,
          waccTerminalInicial: terminalInicial,
          baseProfit: baseProfit,
          assumptions: assumptions,
          netDebt: netDebt,
          unleveredBeta: unleveredBeta,
          riskFreePath: riskFreePath,
          terminalRiskFree: terminalRiskFree,
          marketPremium: marketPremium,
          creditSpread: creditSpread,
          taxRate: taxRate,
          cash: cash,
          terminalBetaWeight: terminalBetaWeight,
          terminalLeverage: terminalLeverage,
        );

    final pelaInterpolacao = de(null, null);
    // O desalavancado: o mesmo caminho de `Ke` com `D/E = 0`, que é o limite
    // inferior de alavancagem do próprio modelo.
    final desalavancado = [
      for (final rf in riskFreePath) rf + unleveredBeta * marketPremium,
    ];
    final peloDesalavancado = de(
      desalavancado,
      terminalRiskFree + unleveredBeta * marketPremium,
    );

    final a = pelaInterpolacao.valueOrNull;
    final b = peloDesalavancado.valueOrNull;
    if (a == null && b == null) {
      // **A recusa é do ponto fixo, e o texto precisa dizer isso** (item B18).
      // Dizer só que a interpolação não fechou deixaria em pé a leitura de que
      // o veredito é do chute — que era, e deixou de ser.
      final motivo = pelaInterpolacao.failureOrNull?.message ?? '';
      return Err(ComputationFailure(
        '$motivo O ponto fixo foi tentado também a partir do custo de capital '
        'desalavancado, e não fecha de nenhuma das duas partidas: a recusa é '
        'do método, e não do chute.',
      ));
    }
    if (a == null) {
      warnings?.add(
        'O ponto fixo do custo de capital não fecha a partir da interpolação '
        'de dois pontos, e fecha a partir do custo desalavancado. O resultado '
        'é o do ponto fixo, e não o do chute — recusar aqui seria recusar por '
        'causa de onde a conta começou (item B18).',
      );
      return peloDesalavancado;
    }
    if (b == null) return pelaInterpolacao;

    final va = a.equity.isEmpty ? double.nan : a.equity.first;
    final vb = b.equity.isEmpty ? double.nan : b.equity.first;
    final distancia = (va.abs() > 0 && va.isFinite && vb.isFinite)
        ? (vb / va - 1).abs()
        : 0.0;
    if (distancia > startIndependence) {
      warnings?.add(
        'O ponto fixo do custo de capital chega a dois resultados conforme o '
        'chute de partida — ${(distancia * 100).toStringAsFixed(1)}% de '
        'diferença no capital próprio do ano zero. Vale o da interpolação, '
        'que é o caminho declarado, e esta divergência é ressalva do método '
        '(item B18).',
      );
    }
    return pelaInterpolacao;
  }

  /// Uma tentativa do ponto fixo, a partir de um caminho de partida.
  ///
  /// Separado de [solve] porque **o ponto fixo não pode depender de onde
  /// começa** (item B18): se a resposta muda com o chute, ela é do chute. A
  /// [solve] roda esta função de dois pontos de partida e compara.
  static Result<LeveredRates> _tentar({
    required List<double>? waccInicial,
    required double? waccTerminalInicial,
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebt,
    required double unleveredBeta,
    required List<double> riskFreePath,
    required double terminalRiskFree,
    required double marketPremium,
    required double creditSpread,
    required double taxRate,
    double? cash,
    double? terminalBetaWeight,
    double? terminalLeverage,
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
    if (_alavancagemImpossivel(terminalLeverage)) {
      return const Err(InvalidInput(
        'Alavancagem de equilíbrio imposta não descreve estrutura possível: '
        'com D/E de −1 ou menos o valor da firma não é positivo.',
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
    // **O caixa acompanha a mesma base, e por isso a líquida não muda**: as
    // duas metades crescem com o mesmo fator, e a diferença delas é a série de
    // [divida] acima. O que a separação muda é só a **composição da taxa** —
    // o caixa rende `R_f`, e não `R_f + spread` (lente `metodo`, 21/09/2026).
    // Sem `cash`, vale a forma anterior, que remunera a perna negativa ao
    // custo de empréstimo. Ver `CostOfCapital.rawWacc`.
    final caixa = cash == null ? null : <double>[cash];
    if (caixa != null) {
      for (var t = 1; t <= n; t++) {
        caixa.add(caixa[t - 1] * (1 + assumptions.growthAt(t)));
      }
    }

    // `K_d` do ano, líquido do escudo: o prêmio de crédito é constante e a
    // taxa base é a do ano, como em `CostOfCapital.effectiveCostOfDebt`.
    double kdLiquidoEm(double rf) => (rf + creditSpread) * (1 - taxRate);
    final kdTerminal = kdLiquidoEm(terminalRiskFree);

    // Chute inicial: o informado, ou as taxas que a interpolação de dois
    // pontos daria — que é o recuo, e o que a versão anterior usava sempre.
    var ke = waccInicial != null && waccInicial.length == n
        ? [...waccInicial]
        : <double>[
            for (var t = 1; t <= n; t++) assumptions.discountRateAt(t),
          ];
    var wacc = [...ke];
    var keTerminal = waccTerminalInicial ?? assumptions.terminalDiscountRate;
    var waccTerminal = keTerminal;
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
        // **O peso não é confinado em [0, 1]** (decisão 104): com caixa
        // líquido, `D` é negativa, o peso do capital próprio passa de 1 e o
        // `WACC` fica acima do `Ke` — que é o mesmo tratamento do WACC
        // estático. Confinar devolvia `WACC = Ke` e fazia as duas rotas
        // discordarem no mesmo ativo. O caso sem sentido — `E + D` não
        // positivo — já é recusado acima.
        final pesoE = eAnterior / vT;
        final juro = kdLiquidoEm(riskFreePath[t - 1]);
        novoKe.add(keT);
        if (caixa == null) {
          novoWacc.add(keT * pesoE + juro * (1 - pesoE));
        } else {
          // `w_bruta − w_caixa` é exatamente `1 − pesoE`: a separação redistribui
          // a mesma perna entre duas taxas, e não altera os pesos.
          final wBruta = (dAnterior + caixa[t - 1]) / vT;
          final wCaixa = caixa[t - 1] / vT;
          final rendimento = riskFreePath[t - 1] * (1 - taxRate);
          novoWacc.add(keT * pesoE + juro * wBruta - rendimento * wCaixa);
        }
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
      // **A alavancagem de equilíbrio é a do ano N**, e a imposição do B15 a
      // substitui quando a varredura quer testar outra.
      final deTerminal = terminalLeverage ?? dN / eN;
      final fatorN = BetaShrinkage.leverageFactor(
        debtToEquity: deTerminal,
        taxRate: taxRate,
      );
      if (fatorN == null) {
        return const Err(ComputationFailure(
          'Fator de alavancagem terminal não finito.',
        ));
      }
      keTerminal = terminalRiskFree +
          _betaDeEquilibrio(unleveredBeta * fatorN, terminalBetaWeight) *
              marketPremium;
      final vN = eN + dN;
      if (!vN.isFinite || vN <= 0) {
        return const Err(ComputationFailure(
          'Valor da firma não positivo no fim da projeção: o peso do capital '
          'no custo médio de equilíbrio deixa de ter sentido.',
        ));
      }
      final pesoEN = terminalLeverage == null
          ? eN / vN
          : 1 / (1 + terminalLeverage);
      // Mesma separação do ano a ano, na estrutura do ano N. Com `D/E`
      // imposto não há separação: a dívida ali é arbitrada, e não observada.
      if (caixa == null || terminalLeverage != null) {
        waccTerminal = keTerminal * pesoEN + kdTerminal * (1 - pesoEN);
      } else {
        waccTerminal = keTerminal * pesoEN +
            kdTerminal * ((dN + caixa[n]) / vN) -
            terminalRiskFree * (1 - taxRate) * (caixa[n] / vN);
      }

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
  /// **A dívida não cresce aqui**, ao contrário de [solve]: o fluxo desta via
  /// já retém lucro para financiar o crescimento, e emitir dívida junto seria
  /// financiá-lo duas vezes (item B11).
  ///
  /// O [LeveredRates] devolvido descreve a via do acionista, e nela **não há
  /// custo médio**: `wacc` repete `costOfEquity` e `terminalWacc` repete
  /// `terminalCostOfEquity`, porque a taxa que desconta o fluxo é o próprio
  /// `Ke`. `enterpriseValue` sai como `E + D`, que é o valor da firma
  /// *implicado* por esta via — não um valor descontado de fluxo de firma.
  /// **Também de duas partidas** (item B18), pela mesma razão de [solve]: a
  /// recusa não pode ser do chute. A segunda é o `Ke` desalavancado.
  static Result<LeveredRates> solveEquity({
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebtPerShare,
    required double unleveredBeta,
    required List<double> riskFreePath,
    required double terminalRiskFree,
    required double marketPremium,
    required double taxRate,
    double? terminalBetaWeight,
    double? terminalLeverage,
    List<String>? warnings,
  }) {
    Result<LeveredRates> de(List<double>? inicial, double? terminalInicial) =>
        _tentarEquity(
          keInicial: inicial,
          keTerminalInicial: terminalInicial,
          baseProfit: baseProfit,
          assumptions: assumptions,
          netDebtPerShare: netDebtPerShare,
          unleveredBeta: unleveredBeta,
          riskFreePath: riskFreePath,
          terminalRiskFree: terminalRiskFree,
          marketPremium: marketPremium,
          taxRate: taxRate,
          terminalBetaWeight: terminalBetaWeight,
          terminalLeverage: terminalLeverage,
        );

    final pelaInterpolacao = de(null, null);
    final desalavancado = [
      for (final rf in riskFreePath) rf + unleveredBeta * marketPremium,
    ];
    final peloDesalavancado = de(
      desalavancado,
      terminalRiskFree + unleveredBeta * marketPremium,
    );

    final a = pelaInterpolacao.valueOrNull;
    final b = peloDesalavancado.valueOrNull;
    if (a == null && b == null) {
      final motivo = pelaInterpolacao.failureOrNull?.message ?? '';
      return Err(ComputationFailure(
        '$motivo O ponto fixo foi tentado também a partir do custo de capital '
        'desalavancado, e não fecha de nenhuma das duas partidas: a recusa é '
        'do método, e não do chute.',
      ));
    }
    if (a == null) {
      warnings?.add(
        'O ponto fixo do custo do capital próprio não fecha a partir da '
        'interpolação de dois pontos, e fecha a partir do custo desalavancado. '
        'O resultado é o do ponto fixo, e não o do chute (item B18).',
      );
      return peloDesalavancado;
    }
    if (b == null) return pelaInterpolacao;

    final va = a.equity.isEmpty ? double.nan : a.equity.first;
    final vb = b.equity.isEmpty ? double.nan : b.equity.first;
    final distancia = (va.abs() > 0 && va.isFinite && vb.isFinite)
        ? (vb / va - 1).abs()
        : 0.0;
    if (distancia > startIndependence) {
      warnings?.add(
        'O ponto fixo do custo do capital próprio chega a dois resultados '
        'conforme o chute de partida — ${(distancia * 100).toStringAsFixed(1)}% '
        'de diferença no capital próprio do ano zero. Vale o da interpolação, '
        'e a divergência é ressalva do método (item B18).',
      );
    }
    return pelaInterpolacao;
  }

  static Result<LeveredRates> _tentarEquity({
    required List<double>? keInicial,
    required double? keTerminalInicial,
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebtPerShare,
    required double unleveredBeta,
    required List<double> riskFreePath,
    required double terminalRiskFree,
    required double marketPremium,
    required double taxRate,
    double? terminalBetaWeight,
    double? terminalLeverage,
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
    if (_alavancagemImpossivel(terminalLeverage)) {
      return const Err(InvalidInput(
        'Alavancagem de equilíbrio imposta não descreve estrutura possível: '
        'com D/E de −1 ou menos o valor da firma não é positivo.',
      ));
    }
    if (!unleveredBeta.isFinite || unleveredBeta < 0) {
      return const Err(InvalidInput(
        'Beta desalavancado indisponível: a realavancagem não é possível.',
      ));
    }

    // **A dívida fica constante em termos nominais, e a razão é o fluxo**
    // (item B11). Esta via desconta o lucro por papel com a retenção descontada
    // dele — `lucro × (1 − b)`, com `b = g/retorno` —, isto é, **o crescimento
    // já é financiado por lucro retido**. Fazer a dívida crescer a `g` junto
    // financiaria o mesmo crescimento duas vezes: a alavancagem subiria, o
    // `Ke` subiria com ela, e o acionista não receberia nada pela dívida nova
    // que a conta supõe emitida. Na via da firma a premissa oposta é
    // consistente porque lá o fluxo do acionista **credita** o `+ΔD`
    // (decisão 102); aqui não há onde creditá-lo.
    //
    // Medido em 20/09/2026, antes da correção: com `g = 8%` e `D/E` inicial de
    // 0,63, a razão ia a 0,81 no ano dez e o `Ke` subia de 19,73% a 20,20% —
    // o modelo **re**alavancava, e a leitura da lente `metodo`, de que ele
    // desalavancava, estava invertida. O que sobra agora é desalavancagem de
    // verdade: a dívida parada e o capital próprio crescendo pelo lucro retido.
    final divida = <double>[
      for (var t = 0; t <= n; t++) netDebtPerShare,
    ];

    var ke = keInicial != null && keInicial.length == n
        ? [...keInicial]
        : <double>[
            for (var t = 1; t <= n; t++) assumptions.discountRateAt(t),
          ];
    var keTerminal = keTerminalInicial ?? assumptions.terminalDiscountRate;
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
        debtToEquity: terminalLeverage ?? divida[n] / eN,
        taxRate: taxRate,
      );
      if (fatorN == null) {
        return const Err(ComputationFailure(
          'Fator de alavancagem terminal não finito.',
        ));
      }
      keTerminal = terminalRiskFree +
          _betaDeEquilibrio(unleveredBeta * fatorN, terminalBetaWeight) *
              marketPremium;

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
