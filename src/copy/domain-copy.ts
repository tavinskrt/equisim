// Rótulos de tela dos enums do núcleo (item B21, decisão 125).
//
// O núcleo diz **o que** é; a apresentação diz **como se lê**. Moram fora da
// interface React porque as ferramentas de `tool/` que escrevem relatório usam
// os mesmos rótulos.
import type {
  ManualGroup,
  ManualTerminal,
  MultipleKind,
  MultipleRefusal,
  ScenarioBand,
  TransversalOrdering,
  ValuationCaveat,
  ValuationModel,
} from '../core';

function lookup(table: Readonly<Record<string, string>>, value: { readonly name: string }): string {
  return table[value.name] ?? value.name;
}

const models: Record<string, string> = {
  dcfFcff: 'DCF por fluxo da firma',
  dcfEarnings: 'DCF sobre lucro distribuível',
};

/**
 * O nome da faixa de cenário, **pelas premissas, e não pelo resultado**
 * (decisão 148): com a empresa rendendo abaixo do custo de capital, as
 * premissas mais brandas podem valer menos que as mais duras.
 */
const bands: Record<string, string> = {
  bear: 'Premissas mais duras',
  base: 'Premissas do motor',
  bull: 'Premissas mais brandas',
};

/** A ressalva, como oração que completa «o número é frágil porque…». */
const caveats: Record<string, string> = {
  heavyTerminal: 'o valor terminal domina o preço justo',
  unidentifiedGrowth: 'o crescimento não é identificável no histórico',
  uncertainScale: 'a base societária publicada é ambígua',
  strongNormalizedBase: 'a base depende de forte correção de um só exercício',
  migratedLane: 'a via de avaliação mudou no meio do cálculo',
  fragileBridge: 'o preço por papel é resíduo de uma subtração frágil',
  mergedLanes: 'o preço justo combina as duas vias',
  rebuiltBase: 'o fluxo-base vem do ciclo, e não do exercício observado',
  fixedTerm: 'o negócio opera sob contrato de prazo determinado',
  stateControl: 'o controle é estatal, e o risco do controlador público não está na taxa',
};

/** A ordenação transversal, como objeto de «o prêmio sai de…». */
const orderings: Record<string, string> = {
  composite: 'o composto de potencial, valor patrimonial e lucro sobre o preço',
  bookToMarket: 'o valor patrimonial sobre o preço',
  potential: 'o potencial do valuation',
};

const multiples: Record<string, string> = {
  priceToEarnings: 'P/L',
  priceToBook: 'P/VP',
  evToEbitda: 'EV/EBITDA',
};

const refusals: Record<string, string> = {
  insufficientPeers: 'pares insuficientes no setor',
  nonPositiveBase: 'a grandeza de baixo não é positiva',
  missingBase: 'a grandeza de baixo não está publicada',
  financialInstitution: 'EBITDA não descreve instituição financeira',
  nonPositiveBridge: 'a ponte deixa o acionista em valor não positivo',
};

/** O grupo de premissas, como degrau de «onde você discorda do motor». */
const groups: Record<string, string> = {
  profit: 'Lucro de partida',
  growth: 'Crescimento',
  reinvestment: 'Reinvestimento',
  rate: 'Taxa de desconto',
  perpetuity: 'Crescimento na perpetuidade',
  newCapital: 'Retorno do capital novo',
};

/** Como a perpetuidade do cálculo do usuário foi formada. */
const terminals: Record<string, string> = {
  neutral: 'lucro do ano 11 ÷ taxa',
  advantage: 'Gordon com o retorno do capital novo',
  fixedFraction: 'Gordon com a parcela fixa',
  contract: 'capital devolvido no fim do contrato',
};

export const DomainCopy = {
  model: (m: ValuationModel): string => lookup(models, m),
  band: (b: ScenarioBand): string => lookup(bands, b),
  caveat: (c: ValuationCaveat): string => lookup(caveats, c),
  ordering: (o: TransversalOrdering): string => lookup(orderings, o),
  multiple: (k: MultipleKind): string => lookup(multiples, k),
  refusal: (r: MultipleRefusal): string => lookup(refusals, r),
  group: (g: ManualGroup): string => lookup(groups, g),
  terminal: (t: ManualTerminal): string => lookup(terminals, t),
} as const;
