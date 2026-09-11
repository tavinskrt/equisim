import 'dart:math' as math;

import '../../entities/valuation.dart';
import '../../failures/failure.dart';
import '../../failures/result.dart';

/// Como o freio de reinvestimento é formado, em cada rodada.
///
/// **Existe para medir, não para escolher.** A política de produção é
/// [medido], e as outras são costuras de diagnóstico: elas permitem que
/// `tool/fluxo_explicito.dart` rode os contrafactuais **pela cascata real** —
/// as duas vias, a rota derivada, o caminho de taxas resolvido — em vez de
/// reimplementar a projeção. Reimplementá-la mede outro motor: em 10/09/2026 o
/// laço do utilitário usava o teto da economia como crescimento perpétuo em 78
/// dos 120 ativos e reinterpolava a taxa em vez de usar o caminho resolvido, e
/// nada acusava porque a conferência comparava o laço contra si mesmo.
enum ReinvestmentPolicy {
  /// `b_t = g_t / ROIC_t`, confinado em `[0; 0,95]`. O que a produção faz.
  medido,

  /// Sem freio: todo o lucro é distribuível.
  nenhum,

  /// `b_t = g_real,t / ROIC_t` — só o crescimento **real** exige capital novo.
  ///
  /// A hipótese: crescer nominalmente ao lado da inflação não pede
  /// investimento líquido, pede reposição a preço maior. Exige
  /// [DcfAssumptions.inflation].
  crescimentoReal,

  /// `b_t = g_t / ROIC_base`, sem a convergência do retorno ao custo de
  /// capital. Isola quanto do freio vem da convergência e quanto do nível.
  semConvergencia,

  /// `b_t = g_t / ROIC_t` **sem o teto de 0,95**, de modo que a retenção pode
  /// passar de 100% e o fluxo do ano ficar negativo.
  ///
  /// É o que acontece de verdade com quem cresce mais do que o retorno
  /// financia: o capital novo vem de fora. O teto de produção esconde isso.
  semTeto,
}

/// Quando o caixa do exercício chega, para efeito de desconto.
enum CashTiming {
  /// Tudo no último dia do ano. É a convenção que o motor usava até 10/09/2026,
  /// e sob a qual `FCFF/WACC ≡ FCFE/Ke` é **identidade algébrica exata**.
  fimDeAno,

  /// Distribuído ao longo do ano, representado pelo meio dele. Produção.
  meioDeAno,
}

/// Premissas de uma rodada de DCF.
class DcfAssumptions {
  /// Teto da retenção, e por consequência do crescimento financiável.
  ///
  /// Retenção de 100% significaria não distribuir nada para sempre, e o valor
  /// do fluxo seria zero por construção.
  static const double maxRetention = 0.95;

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

  /// Caminho explícito da taxa de desconto, do ano 1 ao ano N.
  ///
  /// **Existe porque a alavancagem não é constante.** A interpolação linear
  /// entre a taxa corrente e a de equilíbrio supõe que só a taxa livre de risco
  /// se move; medido em 10/09/2026, `D/V` sai de 0,29 no ano zero para 0,38 no
  /// ano dez, e com ela se movem `Ke` e `WACC`. Ver
  /// [`identidade_das_vias.md`](../../../../../docs/validacao/identidade_das_vias.md).
  ///
  /// Nulo mantém a interpolação de dois pontos, que é o comportamento
  /// anterior. Preenchido, precisa ter exatamente [projectionYears] posições —
  /// [DcfCalculator] recusa quando não tem.
  final List<double>? discountRatePath;

  /// Política do freio de reinvestimento. [ReinvestmentPolicy.medido] em
  /// produção; as outras são costuras de diagnóstico.
  final ReinvestmentPolicy reinvestmentPolicy;

  /// Inflação do ano, usada **apenas** por
  /// [ReinvestmentPolicy.crescimentoReal].
  final double? inflation;

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
    this.discountRatePath,
    this.reinvestmentPolicy = ReinvestmentPolicy.medido,
    this.inflation,
    this.cashTiming = CashTiming.meioDeAno,
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
  double discountRateAt(int t) {
    final caminho = discountRatePath;
    if (caminho != null && t >= 1 && t <= caminho.length) {
      return caminho[t - 1];
    }
    return discountRate - (discountRate - terminalDiscountRate) * _step(t);
  }

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
    if (reinvestmentPolicy == ReinvestmentPolicy.nenhum) return 0.0;
    final roic = reinvestmentPolicy == ReinvestmentPolicy.semConvergencia
        ? returnOnCapital
        : returnOnCapitalAt(t);
    if (roic <= 0) return 0.0;
    var g = growthAt(t);
    if (reinvestmentPolicy == ReinvestmentPolicy.crescimentoReal) {
      final pi = inflation;
      // Sem inflação declarada não há crescimento real a apurar, e inventar um
      // seria medir outra coisa: vale o nominal.
      if (pi != null && pi.isFinite && pi > -1) g = (1 + g) / (1 + pi) - 1;
    }
    if (g <= 0) return 0.0;
    final b = g / roic;
    if (reinvestmentPolicy == ReinvestmentPolicy.semTeto) return b;
    return b.clamp(0.0, maxRetention);
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
    final g = projectionYears <= 1
        ? perpetualGrowth
        : growthRate -
            (growthRate - perpetualGrowth) * ((t - 1) / (projectionYears - 1));
    return sustainable(g, returnOnCapitalAt(t));
  }

  /// Convenção de chegada do caixa. [CashTiming.meioDeAno] em produção.
  final CashTiming cashTiming;

  /// Levantamento de meio de ano do ano com taxa [rate], ou 1 sob
  /// [CashTiming.fimDeAno].
  double lift(double rate) =>
      cashTiming == CashTiming.meioDeAno ? midYearLift(rate) : 1.0;

  /// Fator de **meio de ano**: `√(1 + r)`.
  ///
  /// **O caixa de um exercício não chega no dia 31 de dezembro.** Descontar o
  /// fluxo inteiro do ano no fim dele cobra doze meses de espera por dinheiro
  /// que, em média, chegou no sexto — e o erro é sistemático e sempre na mesma
  /// direção: subestima. Com desconto de 13%, meio ano vale 6,3% do valor, e
  /// isso incide sobre a avaliação inteira, período explícito e perpetuidade.
  ///
  /// **É aproximação, e a exata seria outra.** O ano 1 conta a partir do
  /// último exercício publicado, e na data da avaliação parte dele já correu —
  /// tratar o período parcial exigiria data de fechamento por empresa, que a
  /// fonte dá, e um fluxo proporcional, que ela não dá. A convenção de meio de
  /// ano é a aproximação padrão para exatamente esse caso, e erra menos que
  /// supor que tudo chega no último dia.
  static double midYearLift(double rate) =>
      rate > -1 ? math.sqrt(1 + rate) : 1.0;

  /// Confina [growth] ao que [returnOnCapital] financia: `g ≤ b_max · ROIC`.
  ///
  /// **É a identidade `g = b·ROIC`, aplicada na premissa em vez da
  /// consequência.** Sem ela o motor projetava crescimento que o próprio
  /// retorno não paga e depois truncava a conta do financiamento em
  /// [maxRetention] — de modo que o lucro compunha à taxa cheia enquanto só
  /// 95% dele era cobrado. Medido em 10/09/2026: 14 dos 116 ativos com retorno
  /// utilizável tinham `g > ROIC`, e **os 14 estavam no teto da retenção**. Na
  /// FESA4 o freio pedia 6,8 vezes o lucro operacional; na MOVI3, crescimento
  /// de 31,8% sobre retorno de 13,4%.
  ///
  /// Sem retorno utilizável não há teto a aplicar, e o crescimento passa
  /// inteiro — a mesma direção conservadora ao contrário que [retentionAt] já
  /// adota, e que o resultado declara em texto.
  static double sustainable(double growth, double returnOnCapital) {
    if (returnOnCapital <= 0 || !returnOnCapital.isFinite) return growth;
    final teto = maxRetention * returnOnCapital;
    return growth > teto ? teto : growth;
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
    List<double>? discountRatePath,
    ReinvestmentPolicy? reinvestmentPolicy,
    double? inflation,
    CashTiming? cashTiming,
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
        discountRatePath: discountRatePath ?? this.discountRatePath,
        reinvestmentPolicy: reinvestmentPolicy ?? this.reinvestmentPolicy,
        inflation: inflation ?? this.inflation,
        cashTiming: cashTiming ?? this.cashTiming,
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

  /// Parcela do **valor do capital próprio** explicada pelo valor terminal.
  ///
  /// **A referência é o capital próprio nas três rotas** — ponte, rota
  /// derivada e via do acionista —, e é o que a decisão 51 uniformizou. A
  /// pergunta que ela responde é quanto do **preço** repousa sobre a
  /// perpetuidade, e o preço é o do acionista.
  ///
  /// **Pode passar de 100%.** Quando o terminal descontado supera o capital
  /// próprio — dívida grande, participação fina —, passar é o próprio sinal, e
  /// truncar em 1 esconderia o caso mais frágil.
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
      // O mesmo confinamento da projeção explícita, pela mesma razão: sem ele
      // a perpetuidade cresce a uma taxa que o retorno terminal não financia,
      // e a conta do financiamento é truncada no teto. Vem **antes** da guarda
      // do spread: confinar o crescimento só o afasta da taxa, e checar o
      // spread contra o `g` não confinado recusaria avaliação que fecha.
      final gInf = DcfAssumptions.sustainable(g, moat);
      final spread = r - gInf;
      if (spread < minimumSpread) {
        return const Err(ComputationFailure(
          'Taxa de desconto de equilíbrio não supera o crescimento perpétuo '
          'por margem suficiente: o valor terminal diverge.',
        ));
      }
      final reinvestimento =
          (gInf / moat).clamp(0.0, DcfAssumptions.maxRetention);
      return Ok(finalProfit * (1 + gInf) * (1 - reinvestimento) / spread);
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
    double minorityInterest = 0,
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
    // **A demonstração consolida 100% das controladas; o acionista da
    // controladora não é dono de tudo.** O fluxo descontado é o consolidado,
    // e a parte dos não controladores sai antes da divisão por papel. Ela
    // **não** entra em [equityShare]: a alavancagem da firma é `D/(D+E)` com
    // o capital próprio inteiro, e tirar os minoritários dali os trataria como
    // dívida.
    final doControlador = equity - _naoNegativo(minorityInterest);
    final porPapel = doControlador / sharesOutstanding;

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
      equityValue: doControlador,
      fairValuePerShare: porPapel,
      // **Contra o capital próprio, e não contra o valor da firma**
      // (decisão 51). A pergunta que a ressalva `terminalPesado` faz é quanto
      // do **preço** repousa sobre a perpetuidade, e o preço é o capital
      // próprio: a dívida é subtração fixa, de modo que o terminal contribui
      // com o valor descontado inteiro dele para o que sobra ao acionista.
      // Medir contra `EV` subdeclara exatamente onde o capital próprio é fino
      // — que é onde a estimativa é mais frágil. Pode passar de 100%, e passar
      // é o próprio sinal.
      terminalShare:
          doControlador > 0 ? p.terminalDescontado / doControlador : 0.0,
      equityShare: ev > 0 ? equity / ev : 0.0,
    ));
  }

  /// O valor, ou zero quando ele é negativo ou não finito.
  ///
  /// Participação de não controladores negativa existe — controlada com
  /// patrimônio negativo —, e subtraí-la **aumentaria** o valor do
  /// controlador. Enquanto o motor não modelar a obrigação de aportar, tratar
  /// isso como zero é a leitura conservadora.
  static double _naoNegativo(double v) => v.isFinite && v > 0 ? v : 0.0;

  /// DCF sobre o fluxo do acionista **derivado do da firma**, descontado ao Ke.
  ///
  /// `FCFE_t = FCFF_t − D_{t−1}·[Kd·(1−τ) − g_t]`
  ///
  /// **Por que existe, e o que ela não é.** A via do acionista que a decisão 25
  /// criou parte do LPA publicado — outro dado, de outras linhas —, e por isso
  /// discorda da via da firma além de 1,5× em 55 de 92 ativos
  /// ([decisão 39](../../../../../docs/decisoes/039-as-duas-vias-sao-modelos-independentes.md)).
  /// Esta **não é uma segunda opinião**: é a mesma avaliação por uma rota que
  /// não passa pela subtração `EV − D`, e por isso não sofre a amplificação de
  /// `1/participação` quando o capital próprio é fino.
  ///
  /// **A identidade que ela precisa satisfazer, e que é testável.** Sob
  /// alavancagem constante, com `V = E + D` no ano N:
  ///
  /// ```
  /// FCFE_{N+1} = FCFF_{N+1} − D·[Kd(1−τ) − g]
  ///            = (WACC − g)·V − D·Kd(1−τ) + D·g
  ///            = Ke·E − g·E  =  E·(Ke − g)
  /// ```
  ///
  /// de modo que `TV_equity = FCFE_{N+1}/(Ke − g) = E = TV_firma − D`. A
  /// igualdade é **exata**, e o que ela exige é que o `WACC` tenha sido montado
  /// com os pesos `E/V` e `D/V` **do próprio modelo**. Com peso de equity vindo
  /// do valor de mercado — que é o que `CostOfCapital` faz hoje — ela deixa de
  /// fechar na proporção em que o preço justo discorda do preço.
  ///
  /// - [baseProfit]: NOPAT do exercício-base, já normalizado.
  /// - [netDebt]: dívida líquida no ano zero. Cresce com [DcfAssumptions.growthAt],
  ///   que é a hipótese de alavancagem constante.
  /// - [costOfDebt]: `Kd` **antes** do escudo fiscal.
  /// - [taxRate]: alíquota do escudo, a marginal.
  /// - [equityDiscountRate]: `Ke` do primeiro ano.
  /// - [terminalEquityDiscountRate]: `Ke` de equilíbrio. Decai linearmente do
  ///   primeiro ao último, como o desconto da firma.
  static Result<DcfOutcome> equityFromFirm({
    required double baseProfit,
    required DcfAssumptions assumptions,
    required double netDebt,
    required double sharesOutstanding,
    required double costOfDebt,
    required double taxRate,
    required double equityDiscountRate,
    required double terminalEquityDiscountRate,
    List<double>? equityDiscountRatePath,
    double minorityInterest = 0,
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
    if (equityDiscountRate <= 0 || terminalEquityDiscountRate <= 0) {
      return const Err(InvalidInput(
        'Custo do capital próprio deve ser positivo.',
      ));
    }
    final caminhoKe = equityDiscountRatePath;
    if (caminhoKe != null) {
      if (caminhoKe.length != assumptions.projectionYears) {
        return const Err(InvalidInput(
          'Caminho de custo do capital próprio com tamanho diferente do '
          'horizonte: cada ano projetado precisa da sua taxa.',
        ));
      }
      for (final k in caminhoKe) {
        if (!k.isFinite || k <= 0) {
          return const Err(InvalidInput(
            'Caminho de custo do capital próprio com taxa não positiva.',
          ));
        }
      }
    }

    // O fluxo da firma vem da mesma projeção que a via A usa — é isso que faz
    // desta rota a mesma avaliação, e não outra.
    final projetado = _project(baseProfit, assumptions);
    if (projetado.isErr) return Err(projetado.failureOrNull!);
    final p = projetado.unwrap();

    final kdLiquido = costOfDebt * (1 - taxRate);
    final n = assumptions.projectionYears;

    /// `Ke` do ano [t].
    ///
    /// Com caminho explícito, é ele — e é o que a identidade exige quando a
    /// alavancagem muda ano a ano. Sem caminho, decai linearmente como o
    /// desconto da firma decai, que é o comportamento de dois pontos.
    double keAt(int t) {
      final caminho = equityDiscountRatePath;
      if (caminho != null && t >= 1 && t <= caminho.length) {
        return caminho[t - 1];
      }
      final passo = n <= 1 ? 1.0 : (t - 1) / (n - 1);
      return equityDiscountRate -
          (equityDiscountRate - terminalEquityDiscountRate) * passo;
    }

    final fluxos = <double>[];
    final descontados = <double>[];
    var soma = 0.0;
    var fator = 1.0;
    var divida = netDebt;

    for (var t = 1; t <= n; t++) {
      final ke = keAt(t);
      fator *= 1 + ke;
      final g = assumptions.growthAt(t);
      // `D_{t−1}` é a dívida no **início** do ano: o juro incide sobre ela, e o
      // acréscimo de dívida do ano é `D_{t−1}·g`.
      final fcfe = p.fluxos[t - 1] - divida * (kdLiquido - g);
      fluxos.add(fcfe);
      final vp = fcfe * assumptions.lift(ke) / fator;
      descontados.add(vp);
      soma += vp;
      divida = divida * (1 + g);
    }

    // Terminal do acionista, pela mesma identidade: o fluxo do ano N+1 menos o
    // serviço líquido da dívida, capitalizado a `Ke_∞ − g_∞`.
    final gInf = assumptions.perpetualGrowth;
    final spread = terminalEquityDiscountRate - gInf;
    if (spread < minimumSpread) {
      return const Err(ComputationFailure(
        'Custo do capital próprio de equilíbrio não supera o crescimento '
        'perpétuo por margem suficiente: o valor terminal do acionista '
        'diverge.',
      ));
    }
    final fcffTerminal = p.terminal * (assumptions.terminalDiscountRate - gInf);
    final fcfeTerminal = fcffTerminal - divida * (kdLiquido - gInf);
    final vt = fcfeTerminal / spread;
    // A perpetuidade também é feita de fluxos que chegam ao longo do ano, e o
    // mesmo levantamento vale para ela — sob a taxa de equilíbrio, que é a que
    // a capitaliza.
    final vtDescontado =
        vt * assumptions.lift(terminalEquityDiscountRate) / fator;

    final equity = soma + vtDescontado;
    // O fluxo do acionista derivado do da firma continua consolidando 100% das
    // controladas: a parte dos não controladores sai aqui, como sai na ponte.
    final doControlador = equity - _naoNegativo(minorityInterest);
    final porPapel = doControlador / sharesOutstanding;
    if (!porPapel.isFinite) {
      return const Err(ComputationFailure(
        'Valor por papel não finito: verifique as premissas.',
      ));
    }

    final ev = equity + netDebt;
    return Ok(DcfOutcome(
      projectedFlows: fluxos,
      discountedFlows: descontados,
      terminalValue: vt,
      discountedTerminalValue: vtDescontado,
      enterpriseValue: ev,
      equityValue: doControlador,
      fairValuePerShare: porPapel,
      terminalShare: doControlador > 0 ? vtDescontado / doControlador : 0.0,
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
    final caminho = a.discountRatePath;
    if (caminho != null) {
      if (caminho.length != a.projectionYears) {
        return const Err(InvalidInput(
          'Caminho de desconto com tamanho diferente do horizonte: cada ano '
          'projetado precisa da sua taxa.',
        ));
      }
      for (final r in caminho) {
        if (!r.isFinite || r <= 0) {
          return const Err(InvalidInput(
            'Caminho de desconto com taxa não positiva.',
          ));
        }
      }
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
      final r = a.discountRateAt(t);
      fator *= 1 + r;
      lucro *= 1 + a.growthAt(t);
      final distribuivel = lucro * (1 - a.retentionAt(t));
      // Meio de ano: o fluxo do ano chega, em média, no meio dele.
      final vp = distribuivel * a.lift(r) / fator;
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
      // A perpetuidade também é feita de fluxos distribuídos no ano, e recebe
      // o mesmo levantamento — sob a taxa de equilíbrio, que é a que a
      // capitaliza.
      terminalDescontado: vt * a.lift(a.terminalDiscountRate) / fator,
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
