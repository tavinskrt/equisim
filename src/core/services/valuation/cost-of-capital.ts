/**
 * Custo de capital: CAPM, prêmio de crédito sintético e WACC.
 */

import { DartEnum } from '../../lang/dart-enum';

/**
 * Como o custo de capital foi obtido — rastreabilidade exigida pela
 * reprodutibilidade acadêmica.
 */
export class BetaSource extends DartEnum {
  /** Calculado pelo próprio domínio contra o ^BVSP, janela declarada. */
  static readonly computed = new BetaSource('computed', 0);

  /** Arbitrado pelo usuário. */
  static readonly manual = new BetaSource('manual', 1);

  /**
   * Regressão **encolhida** em direção ao prior transversal, por precisão.
   *
   * Só aparece quando o encolhimento de fato moveu o número — peso do
   * estimador individual abaixo de 1. Medido em 10/09/2026: 23 dos 363
   * papéis, com peso mediano de 0,98 no universo inteiro.
   */
  static readonly shrunk = new BetaSource('shrunk', 2);

  static readonly values: readonly BetaSource[] = [BetaSource.computed, BetaSource.manual, BetaSource.shrunk];

  protected get typeName(): string {
    return 'BetaSource';
  }
}

/** Como o prêmio de risco de mercado foi definido. */
export class MarketPremiumSource extends DartEnum {
  /**
   * Parametrizado: os 5,5% de [CapmInputs.defaultMarketPremium]. Desde a
   * decisão 142 é o recuo, quando a série do prêmio implícito não chega.
   */
  static readonly parameterized = new MarketPremiumSource('parameterized', 0);

  /** Média histórica do índice na janela declarada. */
  static readonly historical = new MarketPremiumSource('historical', 1);

  /**
   * Média de dez anos do prêmio implícito no preço da bolsa — o padrão desde
   * a decisão 142. Ver `ImpliedPremiumPackage`.
   */
  static readonly impliedNormalized = new MarketPremiumSource('impliedNormalized', 2);

  static readonly values: readonly MarketPremiumSource[] = [
    MarketPremiumSource.parameterized,
    MarketPremiumSource.historical,
    MarketPremiumSource.impliedNormalized,
  ];

  protected get typeName(): string {
    return 'MarketPremiumSource';
  }
}

/** Insumos do CAPM. */
export class CapmInputs {
  /** Taxa livre de risco anual, em fração. Deve vir do CDI observado. */
  readonly riskFreeRate: number;

  /** Sensibilidade do ativo ao mercado. `1.0` significa neutro. */
  readonly beta: number;

  /**
   * Origem de [beta] — entra nos avisos do resultado, porque um beta
   * arbitrado e um calculado não sustentam a mesma conclusão.
   */
  readonly betaSource: BetaSource;

  /** Prêmio de risco de mercado (Rm − Rf) anual, em fração. */
  readonly marketPremium: number;

  /** Origem de [marketPremium]. */
  readonly premiumSource: MarketPremiumSource;

  /**
   * Declara os insumos. Não valida faixa — beta negativo e prêmio nulo são
   * entradas legítimas para análise de sensibilidade.
   */
  constructor(args: {
    riskFreeRate: number;
    beta: number;
    marketPremium: number;
    betaSource?: BetaSource;
    premiumSource?: MarketPremiumSource;
  }) {
    this.riskFreeRate = args.riskFreeRate;
    this.beta = args.beta;
    this.marketPremium = args.marketPremium;
    this.betaSource = args.betaSource ?? BetaSource.computed;
    this.premiumSource = args.premiumSource ?? MarketPremiumSource.parameterized;
  }

  /**
   * Prêmio parametrizado: 5,5% a.a., ponto médio da faixa de 5–6% que foi o
   * parâmetro do projeto até a decisão 142.
   *
   * **Desde ela, é recuo e referência**, e não o prêmio do aplicativo: o
   * prêmio é a média de dez anos do prêmio implícito no preço da bolsa
   * (`ImpliedPremiumPackage`), e este valor só entra quando a série não
   * chega — declarado — e nas medições que comparam com a montagem antiga.
   */
  static readonly defaultMarketPremium = 0.055;

  /** Ke = Rf + β · (Rm − Rf) */
  get costOfEquity(): number {
    return this.riskFreeRate + this.beta * this.marketPremium;
  }

  /**
   * Os mesmos insumos com outra taxa livre de risco.
   *
   * Existe para montar o custo de capital **de equilíbrio**: o mesmo beta e o
   * mesmo prêmio, sobre a taxa estrutural em vez da corrente. É o que sustenta
   * a estrutura a termo do desconto sem duplicar a montagem do WACC.
   */
  withRiskFree(rate: number): CapmInputs {
    return new CapmInputs({
      riskFreeRate: rate,
      beta: this.beta,
      marketPremium: this.marketPremium,
      betaSource: this.betaSource,
      premiumSource: this.premiumSource,
    });
  }
}

/** Faixa de prêmio por alavancagem. */
export interface LeverageSpreadBand {
  readonly maxLeverage: number;
  readonly spread: number;
}

/** Faixa de prêmio por cobertura de juros. */
export interface CoverageSpreadBand {
  readonly minCoverage: number;
  readonly spread: number;
}

/**
 * Custo de capital da empresa.
 *
 * **Ponto metodológico**: FCFF é fluxo disponível a *todos* os provedores de
 * capital e por isso deve ser descontado ao **WACC**, não ao Ke. Descontar
 * FCFF ao custo de capital próprio superestimaria a taxa e subavaliaria a
 * empresa — erro comum e facilmente cobrável em banca. O Ke sozinho só é
 * consistente com FCFE.
 */
export class CostOfCapital {
  readonly capm: CapmInputs;

  /**
   * Custo da dívida antes de impostos **como observado**, em fração.
   *
   * Vem de `despesa financeira ÷ dívida bruta`, e a fonte torna essa razão
   * pouco confiável: a despesa financeira publicada nem sempre é o juro da
   * dívida, e a dívida bruta nem sempre está completa. Medido em 21/08/2026:
   * PETR4 saiu com 0,9% a.a. e WEGE3 com 47,3% a.a. — nenhum dos dois é um
   * custo de dívida. Por isso o valor usado no WACC é [effectiveCostOfDebt],
   * não este.
   *
   * **`null` quando a despesa financeira não está publicada** (item B26). A
   * ausência não é custo zero nem cobertura ruim: sem ela a cobertura de juros
   * não é medível, e o prêmio sintético sai só da alavancagem.
   */
  readonly costOfDebt: number | null;

  /** Alíquota efetiva de imposto, em fração. */
  readonly taxRate: number;

  /** Valor de mercado do equity. */
  readonly equityValue: number;

  /**
   * Dívida **líquida** dos pesos: bruta menos caixa e aplicações.
   *
   * **É a mesma dívida da ponte e da realavancagem, e passou a ser** (decisão
   * 104). Antes daqui saíam pesos de dívida bruta enquanto o capital próprio
   * era apurado subtraindo a líquida, e a decisão 54 desalavancava o beta
   * contra a líquida: as três pontas do mesmo modelo usavam duas réguas.
   *
   * **A escolha é da convenção que o resto do motor já usa**, e não uma
   * preferência de estilo. O fluxo da firma é operacional — não tem o
   * rendimento do caixa —, de modo que o valor que ele desconta é o dos ativos
   * operacionais, e o capital que os financia é `E + D_líquida`. Descontar a
   * esse valor um WACC com peso de dívida **bruta** conta o caixa duas vezes:
   * uma barateando a taxa, outra somando-se ao capital próprio na ponte.
   *
   * **Pode ser negativa**, e aí o peso da dívida é negativo e o WACC fica
   * acima do `Ke`. Não é anomalia: com caixa líquido, o ativo operacional
   * sozinho é mais arriscado que a companhia inteira, que é a mesma leitura
   * que o `β_U` da decisão 54 faz ao desalavancar contra a líquida.
   */
  readonly debtValue: number;

  /**
   * Cobertura de juros, `EBIT ÷ despesa financeira`. `null` quando não medível.
   *
   * Decide a alíquota do escudo fiscal — ver [effectiveTaxShield] — e, **quando
   * a despesa financeira é utilizável**, entra também no prêmio de crédito, em
   * união com a alavancagem (ver [syntheticSpread]).
   *
   * No escudo a contaminação por arrendamento e variação cambial não atrapalha,
   * porque as duas também são dedutíveis e a pergunta ali é se há lucro
   * tributável que absorva a dedução.
   */
  readonly interestCoverage: number | null;

  /**
   * Alavancagem, `dívida líquida ÷ EBITDA`. `null` sem EBITDA positivo.
   *
   * **Decide o prêmio de crédito** — ver [syntheticSpread]. Substituiu a
   * cobertura de juros nesse papel em 08/09/2026, e o motivo está medido no
   * doc de [syntheticSpread].
   */
  readonly netDebtToEbitda: number | null;

  /**
   * Caixa e aplicações, em valor absoluto — a parcela do lado direito que
   * **rende**, em vez de custar (lente `metodo`, 21/09/2026).
   *
   * **Por que ele entra separado.** A dívida dos pesos é a líquida (decisão
   * 104), e colapsar bruta e caixa numa grandeza só faz o caixa ser
   * remunerado ao custo de **empréstimo**: com caixa maior que a dívida, o
   * peso fica negativo e `− w·K_d` credita ao acionista um prêmio de crédito
   * que o caixa não rende. O efeito é um WACC baixo demais e um preço justo
   * alto demais, exatamente nos balanços mais líquidos.
   *
   * Com ele, a perna do financiamento se abre em duas — `+ D_bruta·K_d(1−escudo)`
   * e `− Caixa·R_f(1−τ)` —, sobre o mesmo denominador `E + D_líquida`. Sem ele
   * — `null` —, vale a forma anterior, que é a que quem monta o custo à mão
   * obtém.
   */
  readonly cashValue: number | null;

  /**
   * `false` quando a companhia **não tem dívida contratada**, e o que resta do
   * lado direito do balanço é caixa.
   *
   * **O que muda é o `K_d`**: sem dívida não há prêmio de crédito a cobrar, e
   * o que sobra é rendimento de caixa — a taxa livre de risco é o que caixa
   * rende (decisão 58). Os **pesos continuam existindo**, e são negativos: o
   * caixa é dívida líquida negativa, e a apuração do capital próprio o devolve
   * ao acionista (decisão 104). Degenerar para o `Ke` aqui contaria o caixa
   * duas vezes, que é exatamente o defeito que a decisão 104 corrigiu para
   * quem tem dívida.
   */
  readonly hasContractedDebt: boolean;

  /**
   * Taxa livre de risco contra a qual a despesa financeira observada é julgada
   * utilizável — ver [syntheticSpread]. `null` usa a do [capm].
   *
   * Existe separada da taxa do CAPM porque as duas respondem a perguntas
   * diferentes: a do CAPM é a taxa que se supõe, e muda com o cenário e com a
   * perpetuidade; esta é a do ambiente em que a despesa foi incorrida, e é
   * fato do dado. Medida contra a do cenário, a faixa andava com a taxa e o
   * custo da dívida saltava — o preço justo subia com o capital mais caro
   * (item B10).
   */
  readonly creditReferenceRate: number | null;

  /**
   * Declara a estrutura de capital. Todos os valores monetários devem estar
   * na **mesma escala** — misturar reais com milhares distorce os pesos.
   */
  constructor(args: {
    capm: CapmInputs;
    costOfDebt: number | null;
    taxRate: number;
    equityValue: number;
    debtValue: number;
    interestCoverage?: number | null;
    netDebtToEbitda?: number | null;
    creditReferenceRate?: number | null;
    hasContractedDebt?: boolean;
    cashValue?: number | null;
  }) {
    this.capm = args.capm;
    this.costOfDebt = args.costOfDebt;
    this.taxRate = args.taxRate;
    this.equityValue = args.equityValue;
    this.debtValue = args.debtValue;
    this.interestCoverage = args.interestCoverage ?? null;
    this.netDebtToEbitda = args.netDebtToEbitda ?? null;
    this.creditReferenceRate = args.creditReferenceRate ?? null;
    this.hasContractedDebt = args.hasContractedDebt ?? true;
    this.cashValue = args.cashValue ?? null;
  }

  /**
   * Prêmio de crédito máximo admitido sobre a taxa livre de risco.
   *
   * Dez pontos percentuais acomodam desde a empresa de primeira linha até a
   * alavancada; acima disso a empresa não estaria se financiando.
   */
  static readonly maxCreditSpread = 0.1;

  /** Ke, repassado do CAPM. Atalho para `capm.costOfEquity`. */
  get costOfEquity(): number {
    return this.capm.costOfEquity;
  }

  /**
   * Prêmio de crédito por faixa de **alavancagem** — classificação sintética.
   *
   * **Por que a razão observada não serve.** `despesa financeira ÷ dívida
   * bruta` é inutilizável na maioria dos casos: medido sobre o universo
   * elegível, **70 dos 120 avaliados** caíam fora da banda defensável, com
   * valores de até 100% ao ano. O numerador não é juro de dívida — carrega
   * arrendamento (IFRS 16 / CPC 06 R2), variação cambial e monetária.
   *
   * **Por que a cobertura de juros também não serve.** Ela foi o primeiro
   * substituto, e herdava o defeito: a despesa contaminada está no denominador
   * dela. Medido em 08/09/2026 sobre os mesmos avaliados, o resultado era
   * sistematicamente errado, e errado contra as empresas mais sólidas:
   *
   * | Ativo | Cobertura | Dívida líq./EBITDA | Prêmio pela cobertura |
   * |---|---|---|---|
   * | ABEV3 | 3,77x | **−0,57x** (caixa líquido) | 2,4 p.p. |
   * | WEGE3 | 3,68x | **−0,30x** (caixa líquido) | 2,4 p.p. |
   * | RADL3 | 1,50x | **0,70x** | 7,5 p.p. |
   * | SAPR11 | 0,76x | **0,60x** | **10,0 p.p.** (o teto) |
   * | AZZA3 | 1,26x | **1,17x** | 7,5 p.p. |
   *
   * Empresa com caixa líquido pagando prêmio de dois pontos e saneamento
   * regulado com 0,6x de alavancagem pagando o teto não é ordenação de crédito
   * — é o eco da contaminação.
   *
   * **A alavancagem não passa pela despesa financeira.** Dívida líquida e
   * EBITDA são os mesmos campos que a ponte de equity e a base de capital já
   * usam. A distribuição no universo avaliado é bem-comportada: mediana de
   * 1,64x, p90 de 3,55x, três ativos acima de 4x e dezoito com caixa líquido.
   *
   * As faixas seguem a convenção de covenant do crédito corporativo
   * brasileiro, e o teto continua sendo [maxCreditSpread].
   */
  static readonly creditSpreads: readonly LeverageSpreadBand[] = [
    { maxLeverage: 0.0, spread: 0.01 },
    { maxLeverage: 1.0, spread: 0.013 },
    { maxLeverage: 2.0, spread: 0.018 },
    { maxLeverage: 2.5, spread: 0.024 },
    { maxLeverage: 3.0, spread: 0.031 },
    { maxLeverage: 3.5, spread: 0.04 },
    { maxLeverage: 4.0, spread: 0.055 },
    { maxLeverage: 5.0, spread: 0.075 },
  ];

  /**
   * Prêmio de crédito para a alavancagem informada.
   *
   * Devolve [maxCreditSpread] sem alavancagem medível — o que inclui EBITDA
   * não positivo — e acima da última faixa: os dois casos são o de quem não
   * sustenta o próprio endividamento.
   */
  static leverageSpread(leverage: number | null): number {
    if (leverage === null || !Number.isFinite(leverage)) return CostOfCapital.maxCreditSpread;
    for (const band of CostOfCapital.creditSpreads) {
      if (leverage <= band.maxLeverage) return band.spread;
    }
    return CostOfCapital.maxCreditSpread;
  }

  /**
   * Prêmio de crédito por faixa de cobertura de juros, no formato de
   * Damodaran.
   *
   * **Só vale quando a despesa financeira é utilizável** — ver
   * [syntheticSpread]. Ela mede o que a alavancagem não mede: a empresa
   * consegue pagar o juro que contratou, e não só quanto deve.
   */
  static readonly coverageSpreads: readonly CoverageSpreadBand[] = [
    { minCoverage: 8.5, spread: 0.01 },
    { minCoverage: 6.5, spread: 0.013 },
    { minCoverage: 5.5, spread: 0.016 },
    { minCoverage: 4.25, spread: 0.02 },
    { minCoverage: 3.0, spread: 0.024 },
    { minCoverage: 2.5, spread: 0.031 },
    { minCoverage: 2.0, spread: 0.04 },
    { minCoverage: 1.5, spread: 0.055 },
    { minCoverage: 1.25, spread: 0.075 },
    { minCoverage: 0.8, spread: 0.09 },
  ];

  /** Prêmio de crédito para a cobertura informada. */
  static coverageSpread(coverage: number | null): number {
    if (coverage === null || !Number.isFinite(coverage)) return CostOfCapital.maxCreditSpread;
    for (const band of CostOfCapital.coverageSpreads) {
      if (coverage >= band.minCoverage) return band.spread;
    }
    return CostOfCapital.maxCreditSpread;
  }

  /**
   * Prêmio de crédito aplicado, pelas duas razões e por quem pode falar.
   *
   * **As duas medem coisas diferentes e falham de jeitos diferentes.**
   * A alavancagem mede o estoque da dívida e usa dado limpo; a cobertura mede
   * a capacidade de serviço e usa a despesa financeira, que a fonte contamina
   * com arrendamento e variação cambial. Usar só uma delas erra dos dois
   * lados, e as duas medições estão registradas:
   *
   * - **Só cobertura:** a ABEV3 e a WEGE3, de caixa líquido, pagavam prêmio de
   *   2,4 p.p.; a SAPR11, com 0,60x de alavancagem, pagava o **teto** de
   *   10 p.p. porque a cobertura contaminada dela dava 0,76x.
   * - **Só alavancagem:** a MOVI3, cujo EBIT não cobre o juro que ela de fato
   *   paga — despesa de R$ 3,59 bi sobre R$ 21,9 bi de dívida, 16,4% ao ano,
   *   plenamente plausível —, ganhava 5 p.p. de desconto e o potencial dela
   *   saltava de +170% para +622%.
   *
   * **Quem decide se a cobertura pode falar é a própria despesa financeira.**
   * Quando a razão observada `despesa ÷ dívida` cai dentro da banda
   * defensável, a despesa é juro de dívida e a cobertura é informação: vale a
   * **mais exigente** das duas, porque estoque alto e serviço apertado são
   * riscos que se somam. Quando cai fora, a despesa está medindo outra coisa e
   * a cobertura sai da conta: sobra a alavancagem, que não passa por ela.
   *
   * **Sem a despesa, a cobertura sai da conta, e não entra no teto** (item
   * B26). A tabela de cobertura devolve o prêmio máximo para cobertura não
   * medível, e deixá-la falar puniria com 10 p.p. uma empresa cujo único
   * problema é um campo em branco na fonte.
   */
  static syntheticSpread(args: {
    leverage: number | null;
    coverage: number | null;
    observedCostOfDebt: number | null;
    riskFreeRate: number;
  }): number {
    const leverageSpreadValue = CostOfCapital.leverageSpread(args.leverage);
    const observed = args.observedCostOfDebt;
    const usableExpense =
      observed !== null &&
      observed >= args.riskFreeRate &&
      observed <= args.riskFreeRate + CostOfCapital.maxCreditSpread;
    if (!usableExpense) return leverageSpreadValue;
    const coverageSpreadValue = CostOfCapital.coverageSpread(args.coverage);
    return coverageSpreadValue > leverageSpreadValue ? coverageSpreadValue : leverageSpreadValue;
  }

  /**
   * Custo da dívida efetivamente aplicado: `Rf + spread(cobertura)`.
   *
   * **É sempre a classificação sintética, e a uniformidade é o ponto.** A
   * alternativa — usar o observado quando ele cai dentro da banda defensável e
   * a tabela quando cai fora — reintroduz exatamente o defeito que este motor
   * passou a caçar: um corte binário sobre grandeza contínua.
   *
   * **O observado não sobrevive ao exame.** `despesa financeira ÷ dívida
   * bruta` caía fora da banda em 70 dos 120 avaliados, e dentro dela carrega
   * dois vieses de sinais opostos: para cima, arrendamento (IFRS 16 / CPC 06
   * R2) e variação cambial, que não são captação; para baixo, dívida antiga a
   * taxa velha e dívida que a fonte não publica no denominador. Nenhum dos dois
   * é o que o WACC pede, que é o custo **marginal** de captar hoje.
   *
   * As duas razões respondem a essa pergunta com dado do próprio exercício, e
   * a própria despesa financeira arbitra qual delas pode falar — ver
   * [syntheticSpread]. O observado continua sendo medido e entra no resultado
   * como conferência — ver [costOfDebtWasClamped].
   */
  get effectiveCostOfDebt(): number {
    return this.hasContractedDebt
      ? this.capm.riskFreeRate +
          CostOfCapital.syntheticSpread({
            leverage: this.netDebtToEbitda,
            coverage: this.interestCoverage,
            observedCostOfDebt: this.costOfDebt,
            riskFreeRate: this.creditReferenceRate ?? this.capm.riskFreeRate,
          })
      : // Sem dívida contratada não há prêmio de crédito: o que o peso negativo
        // remunera é caixa, e caixa rende a taxa livre de risco (decisão 58).
        this.capm.riskFreeRate;
  }

  /**
   * `true` quando o observado se afasta materialmente do estimado.
   *
   * Existe para que a interface declare a substituição em vez de apresentar o
   * número estimado como se fosse o medido. O corte de 1 p.p. é o passo da
   * própria tabela de prêmios: abaixo dele os dois números diriam a mesma
   * coisa.
   */
  get costOfDebtWasClamped(): boolean {
    const observed = this.costOfDebt;
    return observed !== null && Math.abs(this.effectiveCostOfDebt - observed) > 0.01;
  }

  /** Capital total: equity mais dívida. Denominador dos pesos do WACC. */
  get totalCapital(): number {
    return this.equityValue + this.debtValue;
  }

  /**
   * Participação do capital próprio. **Degenera para `1.0`** quando o capital
   * total é não positivo — sem estrutura conhecida, o WACC vira Ke, que é a
   * hipótese conservadora.
   */
  get equityShare(): number {
    return this.totalCapital > 0 ? this.equityValue / this.totalCapital : 1.0;
  }

  /**
   * Participação da dívida. Degenera para `0.0` no mesmo caso, mantendo
   * `equityShare + debtShare == 1`.
   */
  get debtShare(): number {
    return this.totalCapital > 0 ? this.debtValue / this.totalCapital : 0.0;
  }

  /**
   * Alíquota do escudo fiscal efetivamente aplicada.
   *
   * **É a estatutária limitada pela capacidade de usá-la.** A dedução de juros
   * só vale a alíquota cheia enquanto houver lucro tributável que a absorva:
   * com `EBIT < despesa financeira`, a parcela excedente não abate imposto no
   * exercício — vira prejuízo fiscal a compensar, cujo valor presente é menor.
   * É o tratamento de Damodaran, e a razão de a cobertura entrar aqui além de
   * entrar no prêmio de crédito.
   *
   * Sem cobertura medível vale a alíquota cheia, que é o caso normal de quem
   * cobre os juros com folga.
   */
  get effectiveTaxShield(): number {
    const c = this.interestCoverage;
    if (c === null || !Number.isFinite(c)) return this.taxRate;
    if (c >= 1.0) return this.taxRate;
    return this.taxRate * (c < 0 ? 0.0 : c);
  }

  /**
   * Participação da dívida **bruta**, sobre o mesmo capital total.
   *
   * `null` sem [cashValue]: sem saber quanto é caixa, a bruta não é
   * separável da líquida.
   */
  get grossDebtShare(): number | null {
    const cash = this.cashValue;
    if (cash === null || this.totalCapital <= 0) return null;
    return (this.debtValue + cash) / this.totalCapital;
  }

  /** Participação do caixa, sobre o mesmo capital total. `null` sem [cashValue]. */
  get cashShare(): number | null {
    const cash = this.cashValue;
    if (cash === null || this.totalCapital <= 0) return null;
    return cash / this.totalCapital;
  }

  /**
   * O que o caixa rende, líquido de imposto: a taxa livre de risco.
   *
   * **É rendimento, e é tributado** — ao contrário do juro da dívida, que é
   * dedutível. Por isso o fator aqui é `(1 − τ)` sobre a receita, e não o
   * escudo fiscal de [effectiveTaxShield].
   */
  get afterTaxCashYield(): number {
    return this.capm.riskFreeRate * (1.0 - this.taxRate);
  }

  /**
   * WACC bruto.
   *
   * ```
   * WACC = w_E·K_e + w_D,bruta·K_d·(1 − escudo) − w_caixa·R_f·(1 − τ)
   * ```
   *
   * com os três pesos sobre `E + D_líquida`. **Sem [cashValue] a forma colapsa
   * na anterior**, `w_E·K_e + w_D,líquida·K_d·(1 − escudo)`, que é o que quem
   * monta o custo à mão obtém — e que trata o caixa como dívida negativa
   * remunerada ao custo de empréstimo.
   */
  get rawWacc(): number {
    const wD = this.grossDebtShare;
    const wC = this.cashShare;
    const interest = this.effectiveCostOfDebt * (1.0 - this.effectiveTaxShield);
    if (wD === null || wC === null) {
      return this.equityShare * this.costOfEquity + this.debtShare * interest;
    }
    return this.equityShare * this.costOfEquity + wD * interest - wC * this.afterTaxCashYield;
  }

  /**
   * WACC aplicado ao desconto, nunca abaixo da taxa livre de risco.
   *
   * O benefício fiscal da dívida pode, na aritmética, empurrar o WACC abaixo
   * de Rf numa empresa muito alavancada. Descontar um fluxo de risco a menos
   * que o soberano não é custo de oportunidade defensável, e o efeito sobre a
   * perpetuidade é violento: é o que produzia preços justos várias vezes
   * acima do mercado. O piso mantém o número no terreno econômico, e
   * [waccWasFloored] existe para que a interface diga que isso aconteceu.
   */
  get wacc(): number {
    const raw = this.rawWacc;
    return raw < this.capm.riskFreeRate ? this.capm.riskFreeRate : raw;
  }

  /** `true` quando o piso de [wacc] precisou agir. */
  get waccWasFloored(): boolean {
    return this.rawWacc < this.capm.riskFreeRate;
  }
}
