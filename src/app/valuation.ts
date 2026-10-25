import {
  err,
  EvaluateGoalAlignment,
  ExpectedReturn,
  type FeasibilityVerdict,
  type FinancialGoal,
  GoalFeasibility,
  type GoalAlignment,
  type Portfolio,
  PrepareValuationInputs,
  type Result,
  RequiredReturnSolver,
  type Ticker,
  TransversalSignals,
  type ValuationResult,
} from '../core';
import type { Services } from './services';

/**
 * Preferências de avaliação.
 *
 * **Só [monteCarlo] tem controle na interface**; os demais ficam nos padrões —
 * parâmetros declarados do modelo, e não configuráveis em tempo de execução.
 */
export interface ValuationSettings {
  /** Alterna entre as três faixas nomeadas e a distribuição sorteada. */
  readonly monteCarlo: boolean;
  /** Sorteios de Monte Carlo; também decide se a avaliação vai a um Worker. */
  readonly samples: number;
  /** Margem de segurança sobre o preço justo. Zero: a margem é decisão do investidor. */
  readonly marginOfSafety: number;
  /**
   * Anos de projeção explícita. **Dez, como o núcleo e como a decisão 25**:
   * com cinco, o número da tela não era o número validado.
   */
  readonly projectionYears: number;
  /** Prazo em que se assume a convergência do preço ao justo. */
  readonly convergenceHorizonMonths: number;
}

export const defaultValuationSettings: ValuationSettings = {
  monteCarlo: false,
  samples: 10000,
  marginOfSafety: 0.0,
  projectionYears: 10,
  convergenceHorizonMonths: ExpectedReturn.defaultHorizonMonths,
};

/**
 * Avalia um ativo isolado. `null` quando os dados não sustentam a avaliação —
 * a falha do preparo já foi ao painel de logs pelo próprio preparo (item D4).
 */
export async function valuate(
  services: Services,
  ticker: Ticker,
  settings: ValuationSettings = defaultValuationSettings,
): Promise<ValuationResult | null> {
  const outcome = await valuateOutcome(services, ticker, settings);
  return outcome.isOk ? outcome.unwrap() : null;
}

/**
 * A avaliação **com o motivo da recusa**: a tela diz por que um ativo ficou
 * sem preço justo (fora da Porta 0, sem cotação, demonstrativo curto) em vez
 * de um traço mudo.
 */
export async function valuateOutcome(
  services: Services,
  ticker: Ticker,
  settings: ValuationSettings = defaultValuationSettings,
): Promise<Result<ValuationResult>> {
  const [anchors, capital, premium, curve, officialShares, distressed, stateControlled, concessionEnd, dividends, betaPrior, declaredSharesPerUnit, peerMultiples] =
    await Promise.all([
      services.marketAnchors(),
      services.capitalEvents(ticker),
      // O prêmio de mercado é a média de dez anos do prêmio implícito no preço
      // da bolsa (decisão 142); sem pacote, os 5,5%, ressalvados.
      services.marketPremiumReading(),
      services.riskFreeCurveReading(),
      services.officialShares(ticker),
      services.distressedRegistry(),
      services.stateControlled(ticker),
      services.concessionEnd(ticker),
      services.dividends(ticker),
      services.betaPriorReading(),
      services.declaredSharesPerUnit(ticker),
      services.peerMultiples(ticker),
    ]);

  const inputs = await PrepareValuationInputs.call({
    ticker,
    prices: services.prices,
    fundamentals: services.fundamentals,
    benchmark: services.benchmark,
    asOf: services.clock(),
    // O CAPM olha para frente: a taxa livre de risco do desconto é a corrente,
    // não a média decenal usada para julgar a viabilidade da meta.
    riskFreeRate: anchors.currentRiskFreeRate,
    marketPremium: premium.premium,
    premiumSource: premium.source,
    marginOfSafety: settings.marginOfSafety,
    projectionYears: settings.projectionYears,
    // Desconto nominal exige crescimento perpétuo nominal.
    perpetualGrowthCap: anchors.nominalEconomyGrowth,
    // Âncora top-down da Saída 2 (decisão 25).
    inflation: anchors.inflationCagr,
    // A curva dos prefixados do Tesouro é o padrão (decisão 84); sem curva
    // recente, a cascata recua para o decaimento do CDI e diz isso.
    riskFreeCurve: curve.curve,
    terminalRiskFreeRate: anchors.riskFreeCagr,
    // Contagem oficial da B3: o árbitro do divisor por papel (decisão 83).
    officialShares,
    isDistressed: distressed.contains(ticker.value),
    // O controle estatal: só a ressalva, sem mudar o preço (item B46).
    stateControlled,
    // Só encurta a projeção quando o contrato acaba dentro dela (decisão 88).
    concessionEnd,
    // O beta sai do retorno total, a convenção do Ibovespa (decisão 89).
    dividends,
    // O prior transversal do beta (item B11, decisão 105).
    betaPrior: betaPrior.prior,
    // A composição declarada da unit (item B16, decisão 106).
    declaredSharesPerUnit,
    // A segunda leitura, por múltiplos de pares (item B5, decisão 118).
    peerMultiples,
    // Os eventos de capital completam o ajuste da série e o patrimônio da
    // ponte (itens B28 e B29).
    shareEvents: capital.shareEvents,
    shareIssues: capital.issues,
  });
  if (inputs.isErr) return err(inputs.failureOrNull!);

  // O que a cascata não enxerga — CVM ausente ou defasada, curva ausente,
  // prior ausente, prêmio parametrizado. **Entram antes da cascata** (item
  // D4): acrescentadas ao resultado pronto, faltariam no rastro exportado.
  const notes = [
    await services.cvmCoverageNote(ticker),
    curve.note,
    betaPrior.note,
    premium.note,
  ].filter((n): n is string => n !== null);

  const prepared = inputs.unwrap();
  const result = await services.runner.run({
    // As do preparo primeiro, e as da camada de dados depois.
    inputs: prepared.withContextNotes([...prepared.contextNotes, ...notes]),
    monteCarlo: settings.monteCarlo,
    samples: settings.samples,
  });
  return result;
}

/**
 * Avaliações dos ativos de uma carteira, em sequência.
 *
 * Com teto de 15 ativos e ~2,6 ms por avaliação, a execução sequencial custa
 * dezenas de milissegundos — e a sequência mantém a ordem dos eventos no
 * painel de logs igual à ordem da carteira.
 */
export async function portfolioValuations(
  tickers: readonly Ticker[],
  valuateOne: (t: Ticker) => Promise<ValuationResult | null>,
): Promise<Map<Ticker, ValuationResult>> {
  const out = new Map<Ticker, ValuationResult>();
  for (const t of tickers) {
    const v = await valuateOne(t);
    if (v !== null) out.set(t, v);
  }
  return out;
}

/**
 * Os sinais transversais dos ativos (item B1): book-to-market e lucro sobre o
 * preço do último exercício publicado, pela mesma conta das coortes.
 */
export async function portfolioSignals(
  services: Services,
  tickers: readonly Ticker[],
): Promise<Map<Ticker, TransversalSignals>> {
  const out = new Map<Ticker, TransversalSignals>();
  for (const t of tickers) {
    const history = await services.fundamentals.history(t);
    if (history.isErr) continue;
    out.set(t, TransversalSignals.fromHistory(history.unwrap()));
  }
  return out;
}

/**
 * Situação da carteira frente à meta. A ordenação do prêmio é a que a
 * validação escolheu (item B1), e o prêmio do escore é o mesmo do desconto
 * (decisão 142).
 */
export async function goalAlignment(args: {
  services: Services;
  portfolio: Portfolio;
  goal: FinancialGoal | null;
  valuations: ReadonlyMap<Ticker, ValuationResult>;
}): Promise<GoalAlignment | null> {
  const { services, portfolio, goal, valuations } = args;
  if (goal === null || portfolio.isEmpty) return null;
  const [anchors, skill, signals, premium] = await Promise.all([
    services.marketAnchors(),
    services.skillReading(),
    portfolioSignals(services, portfolio.tickers),
    services.marketPremiumReading(),
  ]);
  const result = EvaluateGoalAlignment.call({
    portfolio,
    goal,
    valuations,
    anchors,
    ordering: skill?.premiumOrdering ?? null,
    signals,
    riskPremium: premium.premium,
  });
  return result.isOk ? result.unwrap() : null;
}

/**
 * Viabilidade da meta, **independente das avaliações**: o aviso de meta
 * irreal aparece enquanto o usuário digita, antes de escolher qualquer ativo.
 */
export async function goalFeasibility(services: Services, goal: FinancialGoal | null): Promise<FeasibilityVerdict | null> {
  if (goal === null) return null;
  const anchors = await services.marketAnchors();
  return feasibilityWith(goal, anchors);
}

/** A viabilidade com as âncoras já em mãos — síncrona, para o arraste dos controles. */
export function feasibilityWith(
  goal: FinancialGoal,
  anchors: Awaited<ReturnType<Services['marketAnchors']>>,
): FeasibilityVerdict {
  const required = RequiredReturnSolver.solve(goal);
  if (required.isErr) return GoalFeasibility.unsolvable({ anchors });
  return GoalFeasibility.assess({ required: required.unwrap(), anchors, goal });
}
