import type { Portfolio } from '../../entities/portfolio';
import type { ValuationResult } from '../../entities/valuation';
import { clamp } from '../../lang/num';
import type { Ticker } from '../../value-objects/ticker';
import { CapmInputs } from '../valuation/cost-of-capital';
import { Inference } from '../valuation/inference';
import { TransversalScore, TransversalSignals, type TransversalOrdering } from './transversal-ordering';

/** Retorno esperado de um ativo pelo estimador transversal. */
export class CrossSectionalReturn {
  /** Escore robusto do potencial contra a seção, já confinado ao teto. */
  readonly z: number;

  /** Retorno esperado ao ano, em fração. */
  readonly expected: number;

  /**
   * `true` quando o piso de zero foi aplicado.
   *
   * Só acontece se `z_cap · prêmio > CDI` — com o CDI brasileiro na casa de
   * dois dígitos e prêmio de 5,5%, não acontece. Fica declarado porque, se
   * acontecer, a ordenação entre os ativos do piso se perde, e quem lê o
   * resultado precisa saber disso em vez de deduzir de empates suspeitos.
   */
  readonly floored: boolean;

  /**
   * `true` quando a âncora foi o custo de capital próprio do ativo, e não o
   * CDI de recuo.
   *
   * Sai porque a diferença entre as duas é o prêmio de risco inteiro, e o
   * leitor precisa poder distinguir um número do outro (decisão 58).
   */
  readonly anchoredOnCostOfEquity: boolean;

  constructor(args: { z: number; expected: number; floored: boolean; anchoredOnCostOfEquity?: boolean }) {
    this.z = args.z;
    this.expected = args.expected;
    this.floored = args.floored;
    this.anchoredOnCostOfEquity = args.anchoredOnCostOfEquity ?? false;
  }
}

/**
 * Converte *upside* de valuation em taxa anual comparável à meta.
 *
 * **Problema de unidade que isto resolve**: o upside do DCF é uma valorização
 * *total* (ex.: +40%) sem prazo definido, enquanto a rentabilidade requerida é
 * uma taxa *por período* (ex.: 12% a.a.). Comparar os dois diretamente não
 * significa nada — é preciso declarar em quanto tempo o preço converge para o
 * valor justo.
 *
 *     r_esperado = (1 + upside)^(1/H) − 1
 *
 * **O retorno é só de preço.** O trabalho não modela provento, e a estimativa
 * é portanto conservadora: um acionista que receba dividendo obtém mais que
 * isto. Ver `docs/decisoes/023-remocao-de-proventos.md`.
 */
export const ExpectedReturn = {
  /**
   * Horizonte de convergência padrão, em meses.
   *
   * **36 meses, por decisão 25.** Os 12 meses anteriores acompanhavam a
   * convenção de mercado para preço-alvo, mas tornavam a anualização a
   * identidade — `(1 + u)^(1/1) − 1 = u` —, de modo que o *upside* bruto virava
   * retorno esperado sem nenhuma transformação. A PETR4, com +209,2% de
   * *upside*, entrava na média ponderada da carteira como 209,2% ao ano.
   *
   * É parâmetro declarado, não constante escondida: deve aparecer junto do
   * resultado.
   */
  defaultHorizonMonths: 36,

  /** Anualiza um upside total sobre o horizonte [horizonMonths]. */
  annualizedFromUpside(upside: number, options: { horizonMonths?: number } = {}): number {
    const horizonMonths = options.horizonMonths ?? ExpectedReturn.defaultHorizonMonths;
    if (horizonMonths <= 0) return 0.0;
    const growth = 1.0 + upside;
    if (growth <= 0) return -1.0;
    const years = horizonMonths / 12.0;
    return Math.pow(growth, 1.0 / years) - 1.0;
  },

  // ------------------------------------------ Retorno esperado transversal --

  /**
   * Teto do escore, em desvios robustos.
   *
   * **Confina a cauda, não a ordenação.** A distribuição de potencial dos 120
   * avaliados vai de −95,5% a +477,3%: sem teto, um único ativo de cauda
   * direita levaria o escore a mais de dez desvios e sozinho definiria o
   * retorno esperado da carteira inteira. Com dois desvios e prêmio de 5,5%, a
   * banda de retorno esperado é de CDI ± 11 p.p. — o suficiente para separar o
   * muito descontado do muito esticado sem que a ponta decida a conta.
   */
  defaultZCap: 2.0,

  /**
   * Retorno esperado transversal de um conjunto de ativos avaliados.
   *
   * **Por que não é a anualização do potencial.** `(1 + u)^(1/H) − 1` é uma
   * afirmação de nível: com potencial mediano de −39,4% no universo elegível,
   * ela devolve −15,4% ao ano para o ativo *mediano* — e num otimizador de
   * média-variância isso não ordena mal, ele simplesmente não aloca. O nível do
   * potencial carrega tudo o que a estrutura a termo e o terminal neutro
   * impõem de conservadorismo ao custo de capital brasileiro; a **ordenação**
   * entre ativos, não.
   *
   * Este estimador usa só a ordenação, **em torno do custo de capital próprio
   * de cada ativo**:
   *
   *     E[R_i] = Ke_i + z_i · prêmio,    z_i = (u_i − mediana(u)) / MAD*(u)
   *
   * O ativo mediano da seção recebe o **próprio `Ke`** — `Rf + β_i·prêmio`,
   * que é o retorno esperado incondicional dele —; quem está descontado em
   * relação aos pares recebe mais, e quem está esticado recebe menos. **O
   * preço justo do ativo individual não é tocado** — ele continua saindo do
   * DCF, e é ele que a tela de avaliação mostra. Esta é a projeção de
   * otimização, e só ela.
   *
   * **O prêmio pressupõe que a ordenação informa, e para o potencial isso não
   * está demonstrado**: condicionado ao book-to-market, ele não passa no
   * critério da decisão 96. Por isso o aplicativo não usa mais este estimador:
   * usa [forPortfolioOrdered], com o prêmio da ordenação que a validação
   * comprovou, ou sem prêmio (decisão 103). Este fica para as ferramentas de
   * validação que medem o potencial sozinho.
   *
   * **A âncora era o CDI, e isso subtraía o prêmio de risco inteiro**
   * (decisão 58). Sem `Ke` disponível para um ativo, a âncora dele recua para
   * [spotRiskFree] — o comportamento anterior, e o resultado declara em
   * [CrossSectionalReturn.anchoredOnCostOfEquity].
   *
   * Escala robusta e não desvio-padrão pelo mesmo motivo da Guarda 3: com
   * ponto de ruptura de 50%, a cauda de potencial não infla o denominador e
   * achata todo mundo no centro.
   *
   * - [upsides]: potenciais dos ativos a estimar.
   * - [costOfEquity]: custo do capital próprio de cada ativo. É a âncora.
   * - [spotRiskFree]: CDI corrente, em fração ao ano. Âncora de recuo.
   * - [riskPremium]: prêmio de risco de mercado. O padrão é o mesmo parâmetro
   *   do CAPM que desconta o fluxo.
   * - [reference]: seção transversal que define mediana e escala. Omitida, cai
   *   para os próprios [upsides].
   * - [zCap]: teto do escore em desvios robustos.
   */
  crossSection(args: {
    upsides: ReadonlyMap<Ticker, number>;
    spotRiskFree: number;
    costOfEquity?: ReadonlyMap<Ticker, number> | null;
    riskPremium?: number;
    reference?: Iterable<number> | null;
    zCap?: number;
  }): Map<Ticker, CrossSectionalReturn> {
    const riskPremium = args.riskPremium ?? CapmInputs.defaultMarketPremium;
    const zCap = args.zCap ?? ExpectedReturn.defaultZCap;
    const crossSection = [...(args.reference ?? args.upsides.values())];
    const center = Inference.median(crossSection);
    const scale = Inference.scaledMad(crossSection);

    const output = new Map<Ticker, CrossSectionalReturn>();
    for (const [key, value] of args.upsides) {
      // Sem escala estimável — seção curta demais ou colapsada num ponto — não
      // há distância a medir, e todo mundo recebe a âncora. É a leitura neutra:
      // afirmar ordenação onde a seção não a sustenta seria inventar prêmio.
      const z = center === null || scale === null ? 0.0 : clamp((value - center) / scale, -zCap, zCap);
      // **A bandeira sai de haver `Ke`, e não de comparar as duas âncoras.**
      // Um `Ke` numericamente igual ao CDI é possível — beta zero, ou
      // coincidência de arredondamento — e compará-los declararia recuo onde
      // não houve.
      const ke = args.costOfEquity?.get(key);
      const hasKe = ke !== undefined && Number.isFinite(ke) && ke > 0;
      const anchor = hasKe ? ke : args.spotRiskFree;
      const raw = anchor + z * riskPremium;
      output.set(
        key,
        new CrossSectionalReturn({
          z,
          expected: raw < 0 ? 0.0 : raw,
          floored: raw < 0,
          anchoredOnCostOfEquity: hasKe,
        }),
      );
    }
    return output;
  },

  /**
   * Retorno esperado da carteira pelo estimador transversal.
   *
   * Média dos ativos ponderada pelos pesos, com os pesos sem avaliação
   * descartados e os remanescentes reescalados — a mesma convenção de
   * [coverage], para que a cobertura continue significando o mesmo.
   */
  forPortfolioCrossSectional(args: {
    portfolio: Portfolio;
    valuations: ReadonlyMap<Ticker, ValuationResult>;
    spotRiskFree: number;
    riskPremium?: number;
    reference?: Iterable<number> | null;
    zCap?: number;
  }): number {
    const { portfolio, valuations } = args;
    const upsides = new Map<Ticker, number>();
    for (const entry of portfolio.entries.values()) {
      const v = valuations.get(entry.ticker);
      if (v !== undefined) upsides.set(entry.ticker, v.upside);
    }
    if (upsides.size === 0) return 0.0;

    const costOfEquity = new Map<Ticker, number>();
    for (const [key, value] of valuations) {
      if (value.diagnostics !== null) costOfEquity.set(key, value.diagnostics.costOfEquity);
    }
    const estimated = ExpectedReturn.crossSection({
      upsides,
      spotRiskFree: args.spotRiskFree,
      costOfEquity,
      riskPremium: args.riskPremium ?? CapmInputs.defaultMarketPremium,
      reference: args.reference ?? [...valuations.values()].map((v) => v.upside),
      zCap: args.zCap ?? ExpectedReturn.defaultZCap,
    });

    let weighted = 0.0;
    let covered = 0.0;
    for (const entry of portfolio.entries.values()) {
      const r = estimated.get(entry.ticker);
      if (r === undefined) continue;
      weighted += entry.weight.value * r.expected;
      covered += entry.weight.value;
    }
    return covered <= 0 ? 0.0 : weighted / covered;
  },

  /**
   * Retorno esperado da carteira com o prêmio da **ordenação medida** (item B1).
   *
   * `E[R_i] = Ke_i + z_i · prêmio`, com `z_i` o escore de [ordering] contra a
   * seção dos sinais da carteira — ver [TransversalScore]. **Sem ordenação não
   * há prêmio**: `E[R_i] = Ke_i`. É o caso em que nenhuma das ordenações
   * passou no critério da decisão 96, e afirmar desconto relativo como prêmio
   * seria afirmar habilidade que a validação não mediu.
   *
   * Os pesos e a cobertura seguem [forPortfolioCrossSectional]: só entra o
   * ativo com avaliação, que é o que dá o `Ke`. O ativo avaliado sem o sinal
   * que a ordenação pede recebe escore zero — a âncora, sem prêmio nem
   * desconto —, e não sai da conta.
   *
   * - [signals]: os sinais de cada ativo da carteira. O potencial que não vier
   *   aqui é lido da avaliação.
   */
  forPortfolioOrdered(args: {
    portfolio: Portfolio;
    valuations: ReadonlyMap<Ticker, ValuationResult>;
    signals: ReadonlyMap<Ticker, TransversalSignals>;
    ordering: TransversalOrdering | null;
    spotRiskFree: number;
    riskPremium?: number;
  }): number {
    const { portfolio, valuations, signals, ordering } = args;
    const riskPremium = args.riskPremium ?? CapmInputs.defaultMarketPremium;
    const crossSection = new Map<Ticker, TransversalSignals>();
    for (const entry of portfolio.entries.values()) {
      const v = valuations.get(entry.ticker);
      if (v === undefined) continue;
      const s = signals.get(entry.ticker);
      crossSection.set(
        entry.ticker,
        new TransversalSignals({
          potential: s?.potential ?? v.upside,
          bookToMarket: s?.bookToMarket ?? null,
          earningsYield: s?.earningsYield ?? null,
        }),
      );
    }
    if (crossSection.size === 0) return 0.0;
    const scores: ReadonlyMap<Ticker, number> =
      ordering === null ? new Map<Ticker, number>() : TransversalScore.scores(crossSection, ordering);

    let weighted = 0.0;
    let covered = 0.0;
    for (const entry of portfolio.entries.values()) {
      const v = valuations.get(entry.ticker);
      if (v === undefined) continue;
      const ke = v.diagnostics?.costOfEquity;
      const anchor = ke !== undefined && Number.isFinite(ke) && ke > 0 ? ke : args.spotRiskFree;
      const raw = anchor + (scores.get(entry.ticker) ?? 0.0) * riskPremium;
      weighted += entry.weight.value * (raw < 0 ? 0.0 : raw);
      covered += entry.weight.value;
    }
    return covered <= 0 ? 0.0 : weighted / covered;
  },

  /** Fração do peso da carteira que possui valuation disponível. */
  coverage(args: { portfolio: Portfolio; valuations: ReadonlyMap<Ticker, ValuationResult> }): number {
    let covered = 0.0;
    for (const entry of args.portfolio.entries.values()) {
      if (args.valuations.has(entry.ticker)) {
        covered += entry.weight.value;
      }
    }
    return covered;
  },
};
