import '../../entities/valuation.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';

/// Premissas de uma rodada de DCF.
class DcfAssumptions {
  /// Anos de projeção explícita.
  ///
  /// Dez por decisão 25. Com cinco, o valor terminal carregava de 63,5% a 80,0%
  /// do preço justo, e a parte da conta apoiada em dado observado decidia pouco.
  final int projectionYears;

  /// Crescimento do **primeiro** ano projetado, em fração.
  ///
  /// Não é constante ao longo da projeção: decai linearmente até
  /// [perpetualGrowth]. Ver [growthAt].
  final double growthRate;

  /// Crescimento na perpetuidade, em fração.
  ///
  /// **Com [neutralTerminalReturn] ligado, ele não afeta o valor terminal** —
  /// ver [DcfCalculator.terminalValue]. Continua governando o decaimento do
  /// período explícito e permanece como banda de sanidade.
  final double perpetualGrowth;

  /// Taxa de desconto do **primeiro** ano, em fração. WACC na via da firma, Ke
  /// na do acionista, montados sobre a taxa livre de risco **corrente**.
  ///
  /// Não é constante ao longo da projeção: decai até [terminalDiscountRate].
  /// Ver [discountRateAt].
  final double discountRate;

  /// Taxa de desconto de **equilíbrio**, usada na perpetuidade e como destino do
  /// decaimento, em fração.
  ///
  /// É o mesmo custo de capital montado sobre a taxa livre de risco estrutural —
  /// a média decenal do CDI — em vez da corrente. Existe porque o modelo não tem
  /// curva de juros: sem ela, um indexador *overnight* precificava fluxo
  /// perpétuo, e no topo do ciclo monetário isso esmagava todo valor terminal.
  ///
  /// Como `K_e = R_f + β·prêmio` e `WACC = w_E K_e + w_D K_d(1−T)` são afins em
  /// `R_f`, decair o custo de capital linearmente é **idêntico** a decair a taxa
  /// livre de risco e remontar o custo a cada ano — e dispensa carregar a
  /// estrutura de capital até aqui.
  final double terminalDiscountRate;

  /// Retorno sobre a base de capital: ROIC na via da firma, ROE na do
  /// acionista.
  ///
  /// **É dele que sai a retenção, ano a ano.** O fluxo descontado é
  /// `lucro × (1 − b_t)` com `b_t = g_t / retorno`: crescer exige reinvestir, e
  /// descontar o lucro inteiro **e** fazê-lo crescer conta o mesmo dinheiro duas
  /// vezes. A decisão 24 corrigiu isso do lado do acionista; a 25 estendeu ao da
  /// firma, onde o fluxo crescia sem que nada fosse retido.
  ///
  /// **A retenção acompanha o decaimento do crescimento.** Fixá-la no valor do
  /// primeiro ano faria a empresa continuar retendo para um crescimento que já
  /// caiu, deprimindo o fluxo justamente nos anos em que ele deveria se abrir —
  /// erro que a validação fora da amostra expôs como queda sistemática do preço
  /// justo. Zero desliga o freio.
  final double returnOnCapital;

  /// Retorno terminal igual ao custo de capital.
  ///
  /// Quando `true` — o padrão, por decisão 25 —, impõe `ROIC_∞ = WACC` e
  /// `ROE_∞ = Ke`, o que faz o valor terminal virar `fluxo_{N+1} / desconto` e
  /// **deixar de depender do crescimento perpétuo**. É a afirmação de que não há
  /// lucro econômico em perpetuidade: crescimento sem retorno excedente não cria
  /// valor.
  ///
  /// [terminalReturnOnCapital] tem precedência sobre este campo.
  final bool neutralTerminalReturn;

  /// Retorno preservado na perpetuidade, quando a vantagem competitiva é
  /// comprovada. `null` mantém o estado estacionário.
  ///
  /// Existe porque colapsar **toda** empresa em `ROIC_∞ = WACC` trata franquia
  /// duradoura e negócio comoditizado da mesma forma. Quando preenchido, o valor
  /// terminal volta à forma de Gordon com reinvestimento:
  ///
  /// ```
  /// VT = lucro_{N+1}·(1 − g_∞/ROIC_∞) / (r_∞ − g_∞)
  /// ```
  ///
  /// **O preço disso é declarado**: o terminal volta a depender de `g_∞`, que o
  /// retorno neutro havia eliminado. Por isso a ativação é restrita e cumulativa
  /// — ver `ValuationParameters.moatRetainedSpread` e as três condições que a
  /// cascata exige.
  final double? terminalReturnOnCapital;

  /// Margem de segurança sobre o preço justo, em fração.
  final double marginOfSafety;

  /// Declara as premissas. **Não valida** — a consistência entre desconto e
  /// crescimento é conferida em [DcfCalculator], que devolve [Result].
  const DcfAssumptions({
    this.projectionYears = 10,
    required this.growthRate,
    required this.perpetualGrowth,
    required this.discountRate,
    double? terminalDiscountRate,
    this.returnOnCapital = 0.0,
    this.neutralTerminalReturn = true,
    this.terminalReturnOnCapital,
    this.marginOfSafety = 0.0,
  }) : terminalDiscountRate = terminalDiscountRate ?? discountRate;

  /// Fração percorrida da janela explícita no ano [t]: 0 no ano 1, 1 no ano N.
  double _step(int t) =>
      projectionYears <= 1 ? 1.0 : (t - 1) / (projectionYears - 1);

  /// Taxa de desconto do ano [t], decaindo de [discountRate] até
  /// [terminalDiscountRate].
  ///
  /// ```
  /// r_t = r_spot − (r_spot − r_∞) · (t − 1)/(N − 1)
  /// ```
  ///
  /// É a estrutura a termo que o modelo não tinha. Note que `r_t` é taxa **do
  /// período**, não taxa à vista de vértice: o desconto composto acumula os
  /// fatores ano a ano, e não eleva `r_t` a `t`.
  double discountRateAt(int t) =>
      discountRate - (discountRate - terminalDiscountRate) * _step(t);

  /// Retorno sobre o capital no ano [t], convergindo do observado ao custo de
  /// capital do próprio ano.
  ///
  /// ```
  /// ROIC_t = ROIC_base − (ROIC_base − r_t) · (t − 1)/(N − 1)
  /// ```
  ///
  /// **Por que converge.** Manter o retorno no pico histórico enquanto o
  /// crescimento já decai faz a retenção `b_t = g_t/ROIC` cair duas vezes, e o
  /// fluxo livre dos anos finais sobe sem que nada na economia justifique. Pior:
  /// o retorno saltava do nível histórico direto para o custo de capital na
  /// perpetuidade, uma descontinuidade sem conteúdo econômico. Convergindo, o
  /// último ano explícito **encontra** o estado estacionário — `b_N = g_∞/r_∞` é
  /// exatamente a retenção que o terminal supõe.
  ///
  /// Devolve zero quando não há retorno utilizável, o que desliga o freio.
  double returnOnCapitalAt(int t) {
    if (returnOnCapital <= 0) return 0.0;
    final destino = discountRateAt(t);
    return returnOnCapital - (returnOnCapital - destino) * _step(t);
  }

  /// Retenção aplicada ao ano [t], pela relação `b_t = g_t / ROIC_t`.
  ///
  /// Confinada a `[0, 0,95]`: retenção de 100% significaria não distribuir nada
  /// para sempre, e o valor do fluxo seria zero por construção. Devolve zero sem
  /// retorno utilizável, o que desliga o freio e é a leitura conservadora na
  /// direção oposta — declarada no resultado.
  double retentionAt(int t) {
    final roic = returnOnCapitalAt(t);
    if (roic <= 0) return 0.0;
    final g = growthAt(t);
    if (g <= 0) return 0.0;
    final b = g / roic;
    return b.clamp(0.0, 0.95);
  }

  /// Crescimento aplicado ao ano [t], contado a partir de 1.
  ///
  /// Decai linearmente de [growthRate] até [perpetualGrowth] ao longo da
  /// projeção:
  ///
  /// ```
  /// g_t = g − (g − g_∞) · (t − 1)/(N − 1)
  /// ```
  ///
  /// A queda em degrau que existia antes — crescimento constante por cinco anos
  /// e corte no sexto — não tem conteúdo econômico: vantagem competitiva se
  /// desgasta conforme a concorrência entra, não termina numa data.
  double growthAt(int t) {
    if (projectionYears <= 1) return perpetualGrowth;
    final passo = (t - 1) / (projectionYears - 1);
    return growthRate - (growthRate - perpetualGrowth) * passo;
  }

  /// Cópia com os campos informados substituídos.
  DcfAssumptions copyWith({
    int? projectionYears,
    double? growthRate,
    double? perpetualGrowth,
    double? discountRate,
    double? terminalDiscountRate,
    double? returnOnCapital,
    bool? neutralTerminalReturn,
    double? terminalReturnOnCapital,
    double? marginOfSafety,
  }) =>
      DcfAssumptions(
        projectionYears: projectionYears ?? this.projectionYears,
        growthRate: growthRate ?? this.growthRate,
        perpetualGrowth: perpetualGrowth ?? this.perpetualGrowth,
        discountRate: discountRate ?? this.discountRate,
        terminalDiscountRate:
            terminalDiscountRate ?? this.terminalDiscountRate,
        returnOnCapital: returnOnCapital ?? this.returnOnCapital,
        neutralTerminalReturn:
            neutralTerminalReturn ?? this.neutralTerminalReturn,
        terminalReturnOnCapital:
            terminalReturnOnCapital ?? this.terminalReturnOnCapital,
        marginOfSafety: marginOfSafety ?? this.marginOfSafety,
      );
}

/// Saída bruta de um DCF, antes de virar [ValuationResult].
class DcfOutcome {
  /// Fluxos distribuíveis do ano 1 ao ano N, **antes** de descontar.
  final List<double> projectedFlows;

  /// Os mesmos fluxos a valor presente, alinhados posição a posição.
  final List<double> discountedFlows;

  /// Valor terminal no ano N, em valor futuro.
  final double terminalValue;

  /// Valor terminal trazido a presente.
  final double discountedTerminalValue;

  /// Valor da firma, ou o valor por papel quando o fluxo já é do acionista.
  final double enterpriseValue;

  /// Valor do equity: [enterpriseValue] menos a dívida líquida.
  final double equityValue;

  /// Preço justo por papel.
  final double fairValuePerShare;

  /// Parcela do valor total explicada pelo valor terminal.
  final double terminalShare;

  /// Participação do equity no valor da firma.
  ///
  /// É a **pós-condição** da via da firma: quando a dívida líquida quase consome
  /// o valor da firma, o que sobra é resíduo de subtração, não avaliação. O erro
  /// relativo do preço por papel é o do valor da firma amplificado por
  /// `EV/(EV − D)` — medido na RENT3, um fator de 138 vezes.
  ///
  /// Vale `1.0` na via do acionista, que não tem ponte.
  final double equityShare;

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
    this.equityShare = 1.0,
  });
}

/// Os dois modelos de fluxo descontado do pacote.
///
/// A simetria entre eles é deliberada e é o que a decisão 25 introduziu: nas
/// duas vias o fluxo é `lucro × (1 − retenção)`, o crescimento decai até a
/// perpetuidade, e o terminal supõe retorno igual ao custo de capital.
abstract final class DcfCalculator {
  /// Distância mínima entre taxa de desconto e crescimento perpétuo.
  ///
  /// Só age quando [DcfAssumptions.neutralTerminalReturn] está desligado: com
  /// retorno terminal neutro, o crescimento sai da fórmula e a perpetuidade não
  /// diverge.
  static const double minimumSpread = 0.005;

  /// Valor terminal no ano N.
  ///
  /// **Com retorno terminal neutro** — `ROIC_∞ = WACC` ou `ROE_∞ = Ke` — a
  /// álgebra colapsa e o crescimento desaparece:
  ///
  /// ```
  /// VT = fluxo_{N+1}/(r − g)       com  fluxo_{N+1} = lucro_{N+1}(1 − g/ROIC)
  /// com ROIC = r:  fluxo_{N+1} = lucro_{N+1}(r − g)/r
  /// ⟹ VT = lucro_{N+1}(r − g) / [r(r − g)] = lucro_{N+1} / r
  /// ```
  ///
  /// É o que blinda o resultado da premissa de crescimento perpétuo — a parte da
  /// avaliação que carregava de 63% a 80% do valor deixa de depender dela.
  ///
  /// - [finalProfit]: lucro do ano N, **antes** da retenção.
  static Result<double> terminalValue({
    required double finalProfit,
    required DcfAssumptions assumptions,
  }) {
    final r = assumptions.terminalDiscountRate;
    final g = assumptions.perpetualGrowth;
    final proximo = finalProfit * (1 + g);

    if (r <= 0) {
      return const Err(InvalidInput('Taxa de desconto deve ser positiva.'));
    }

    // Vantagem competitiva residual: parte do retorno excedente sobrevive à
    // perpetuidade, e o terminal volta à forma de Gordon com reinvestimento.
    final moat = assumptions.terminalReturnOnCapital;
    if (moat != null) {
      if (moat <= 0) {
        return const Err(InvalidInput(
          'Retorno terminal deve ser positivo quando declarado.',
        ));
      }
      final spread = r - g;
      if (spread < minimumSpread) {
        return const Err(ComputationFailure(
          'Taxa de desconto de equilíbrio não supera o crescimento perpétuo '
          'por margem suficiente: o valor terminal diverge.',
        ));
      }
      final reinvestimento = (g / moat).clamp(0.0, 0.95);
      return Ok(proximo * (1 - reinvestimento) / spread);
    }

    if (assumptions.neutralTerminalReturn) return Ok(proximo / r);

    final spread = r - g;
    if (spread < minimumSpread) {
      return const Err(ComputationFailure(
        'Taxa de desconto não supera o crescimento perpétuo por margem '
        'suficiente: o valor terminal diverge. Reduza o crescimento perpétuo '
        'ou adote retorno terminal neutro.',
      ));
    }
    final retencaoPerpetua =
        assumptions.retentionAt(assumptions.projectionYears);
    return Ok(proximo * (1 - retencaoPerpetua) / spread);
  }

  /// DCF sobre o fluxo da firma, descontado ao WACC.
  ///
  /// `FCFF_t = NOPAT_t × (1 − RI)`, com `NOPAT` crescendo pelo decaimento de
  /// [DcfAssumptions.growthAt]. O freio de reinvestimento é a novidade da
  /// decisão 25: antes o fluxo livre crescia sem que nada fosse retido para
  /// financiar o crescimento, o que contava o mesmo dinheiro duas vezes.
  ///
  /// - [baseProfit]: NOPAT do exercício-base, já normalizado. Deve ser positivo.
  /// - [netDebt]: dívida líquida a descontar do valor da firma.
  /// - [sharesOutstanding]: papéis na unidade negociada. Deve ser positivo.
  static Result<DcfOutcome> firm({
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebt,
    required double sharesOutstanding,
  }) {
    if (sharesOutstanding <= 0) {
      return const Err(InsufficientData(
        'Quantidade de papéis em circulação indisponível ou inválida.',
      ));
    }
    if (baseProfit <= 0) {
      return const Err(InsufficientData(
        'Lucro operacional base não positivo: a via da firma não é aplicável.',
      ));
    }

    final projetado = _project(baseProfit, assumptions);
    if (projetado.isErr) return Err(projetado.failureOrNull!);
    final p = projetado.unwrap();

    final ev = p.somaDescontada + p.terminalDescontado;
    final equity = ev - netDebt;
    final porPapel = equity / sharesOutstanding;

    if (!porPapel.isFinite) {
      return const Err(ComputationFailure(
        'Valor por papel não finito: verifique as premissas.',
      ));
    }

    return Ok(DcfOutcome(
      projectedFlows: p.fluxos,
      discountedFlows: p.descontados,
      terminalValue: p.terminal,
      discountedTerminalValue: p.terminalDescontado,
      enterpriseValue: ev,
      equityValue: equity,
      fairValuePerShare: porPapel,
      terminalShare: ev > 0 ? p.terminalDescontado / ev : 0.0,
      equityShare: ev > 0 ? equity / ev : 0.0,
    ));
  }

  /// DCF sobre o fluxo do acionista, descontado ao Ke.
  ///
  /// `Dividendo_t = LPA_t × (1 − b)`, o que **é** um modelo de desconto de
  /// dividendos — mas com o dividendo obtido pela identidade da retenção, e não
  /// por dado publicado de provento. É o que o mantém compatível com a decisão
  /// 23: nada da cadeia removida por ela é reaberto.
  ///
  /// Não há ponte de dívida líquida: o fluxo já é do acionista, e subtraí-la
  /// aqui a contaria duas vezes.
  ///
  /// - [baseProfit]: lucro por papel do exercício-base, já normalizado.
  static Result<DcfOutcome> shareholder({
    required double baseProfit,
    required DcfAssumptions assumptions,
  }) {
    if (baseProfit <= 0) {
      return const Err(InsufficientData(
        'Lucro base não positivo: a via do acionista não é aplicável.',
      ));
    }

    final projetado = _project(baseProfit, assumptions);
    if (projetado.isErr) return Err(projetado.failureOrNull!);
    final p = projetado.unwrap();

    final porPapel = p.somaDescontada + p.terminalDescontado;
    if (!porPapel.isFinite) {
      return const Err(ComputationFailure(
        'Valor por papel não finito: verifique as premissas.',
      ));
    }

    return Ok(DcfOutcome(
      projectedFlows: p.fluxos,
      discountedFlows: p.descontados,
      terminalValue: p.terminal,
      discountedTerminalValue: p.terminalDescontado,
      enterpriseValue: porPapel,
      equityValue: porPapel,
      fairValuePerShare: porPapel,
      terminalShare: porPapel > 0 ? p.terminalDescontado / porPapel : 0.0,
    ));
  }

  /// Taxa de retenção implícita num crescimento, pela relação `g = retorno × b`.
  ///
  /// Continua existindo, mas o sentido de uso se inverteu com a decisão 25:
  /// antes derivava a retenção de um crescimento estimado por regressão; agora
  /// serve de conferência, porque o crescimento já **sai** da retenção
  /// observada. Alimentado com `g = retorno × b`, devolve exatamente o `b` que
  /// entrou — é o laço se fechando.
  ///
  /// Devolve `null` quando a relação não se sustenta: sem retorno utilizável, ou
  /// com crescimento que exigiria reter todo o lucro.
  static double? retentionFor({
    required double growth,
    required double? returnOnCapital,
  }) {
    if (returnOnCapital == null || returnOnCapital <= 0) return null;
    if (!returnOnCapital.isFinite) return null;
    if (growth <= 0) return 0.0;
    final b = growth / returnOnCapital;
    return b >= 1.0 ? null : b;
  }

  static Result<_Projection> _project(
    double baseProfit,
    DcfAssumptions a,
  ) {
    if (a.projectionYears < 1) {
      return const Err(InvalidInput('Anos de projeção deve ser ao menos 1.'));
    }
    if (a.discountRate <= 0 || a.terminalDiscountRate <= 0) {
      return const Err(InvalidInput('Taxa de desconto deve ser positiva.'));
    }

    final fluxos = <double>[];
    final descontados = <double>[];
    var lucro = baseProfit;
    var soma = 0.0;

    // O fator de desconto **acumula** as taxas de cada ano, porque `r_t` é taxa
    // do período e não taxa à vista de vértice. Elevar `r_t` a `t` trataria a
    // curva como se cada ano fosse descontado do zero à sua própria taxa, o que
    // é outra coisa — e desconta o ano 10 a uma taxa que só vale no ano 10.
    var fator = 1.0;

    for (var t = 1; t <= a.projectionYears; t++) {
      fator *= 1 + a.discountRateAt(t);
      lucro *= 1 + a.growthAt(t);
      final distribuivel = lucro * (1 - a.retentionAt(t));
      final vp = distribuivel / fator;
      fluxos.add(distribuivel);
      descontados.add(vp);
      soma += vp;
    }

    final terminal = terminalValue(finalProfit: lucro, assumptions: a);
    if (terminal.isErr) return Err(terminal.failureOrNull!);
    final vt = terminal.unwrap();

    return Ok(_Projection(
      fluxos: fluxos,
      descontados: descontados,
      somaDescontada: soma,
      terminal: vt,
      terminalDescontado: vt / fator,
    ));
  }
}

class _Projection {
  final List<double> fluxos;
  final List<double> descontados;
  final double somaDescontada;
  final double terminal;
  final double terminalDescontado;

  const _Projection({
    required this.fluxos,
    required this.descontados,
    required this.somaDescontada,
    required this.terminal,
    required this.terminalDescontado,
  });
}
