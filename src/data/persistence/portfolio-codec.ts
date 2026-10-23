import {
  Asset,
  clamp,
  FinancialGoal,
  isJsonObject,
  Money,
  Portfolio,
  PortfolioEntry,
  type PortfolioKind,
  Sector,
  Ticker,
  toInt,
  Weight,
} from '../../core';

/** Posição gravada no documento do estudo. */
export interface EncodedEntry {
  ticker: string;
  weight: number;
  name: string;
  sectorKey?: string;
  sectorLabel?: string;
  industry?: string;
}

/** Meta gravada, com os valores em **centavos inteiros**. */
export interface EncodedGoal {
  initialCents: number;
  monthlyCents: number;
  months: number;
  targetCents: number;
}

const stringOrNull = (v: unknown): string | null => (typeof v === 'string' ? v : null);
const numberOrNull = (v: unknown): number | null => (typeof v === 'number' ? v : null);

/**
 * Conversão entre o domínio e o formato de documento do estudo.
 *
 * Separado dos armazenamentos de propósito: serialização é lógica pura e
 * merece teste próprio, sem precisar de um Firestore de mentira. É onde moram
 * as decisões que preservam a integridade dos dados na ida e na volta — e é a
 * mesma para o Firestore e para o modo local.
 */
export const PortfolioStudyCodec = {
  /**
   * Serializa as posições de uma carteira.
   *
   * Grava apenas o que não é derivável: identidade, peso e rótulos. Setor e
   * subsetor são **omitidos** quando ausentes, em vez de gravados como nulo,
   * para que a volta os reconstrua como [Sector.unknown] sem ambiguidade.
   * Identidade da carteira (`id`, `name`, `kind`) fica fora — é do documento
   * que a contém.
   */
  encodePortfolio(portfolio: Portfolio): EncodedEntry[] {
    const out: EncodedEntry[] = [];
    for (const entry of portfolio.entries.values()) {
      const row: EncodedEntry = { ticker: entry.ticker.value, weight: entry.weight.value, name: entry.asset.name };
      if (!entry.sector.isUnknown) {
        row.sectorKey = entry.sector.key;
        row.sectorLabel = entry.sector.label;
      }
      if (entry.asset.industry !== null) row.industry = entry.asset.industry;
      out.push(row);
    }
    return out;
  },

  /**
   * Reconstrói a carteira a partir do documento gravado.
   *
   * **Tolerante e silencioso**: entradas que não sejam objeto, com ticker
   * inválido ou sem peso numérico são **descartadas**, e um [raw] que não seja
   * lista devolve carteira vazia. Nunca lança.
   *
   * A consequência é que uma carteira gravada com dado corrompido volta menor
   * do que foi salva, sem pesos somando 100% — `Portfolio.hasValidWeights`
   * passa a ser `false`, e é por esse caminho que a inconsistência aparece,
   * não por exceção aqui.
   *
   * Pesos são travados em `[0, 1]` na volta, o que impede [Weight.fraction] de
   * lançar sobre valor corrompido.
   */
  decodePortfolio(raw: unknown, args: { id: string; name: string; kind: PortfolioKind }): Portfolio {
    const entries = new Map<Ticker, PortfolioEntry>();
    if (Array.isArray(raw)) {
      for (const item of raw) {
        if (!isJsonObject(item)) continue;
        const ticker = Ticker.tryParse(stringOrNull(item['ticker']) ?? '');
        if (ticker === null) continue;
        const weight = numberOrNull(item['weight']);
        if (weight === null || Number.isNaN(weight)) continue;
        const sectorKey = stringOrNull(item['sectorKey']);
        entries.set(
          ticker,
          new PortfolioEntry({
            asset: new Asset({
              ticker,
              name: stringOrNull(item['name']) ?? ticker.value,
              sector:
                sectorKey === null
                  ? Sector.unknown
                  : Sector.fromKey(sectorKey, { label: stringOrNull(item['sectorLabel']) ?? sectorKey }),
              industry: stringOrNull(item['industry']),
            }),
            weight: Weight.fraction(clamp(weight, 0.0, 1.0)),
          }),
        );
      }
    }
    return new Portfolio({ id: args.id, name: args.name, kind: args.kind, entries });
  },

  /**
   * Valores monetários viajam em **centavos inteiros**, como no domínio.
   * Serializar reais em ponto flutuante reintroduziria exatamente o erro de
   * arredondamento que o tipo `Money` existe para eliminar.
   */
  encodeGoal(goal: FinancialGoal): EncodedGoal {
    return {
      initialCents: goal.initialContribution.cents,
      monthlyCents: goal.monthlyContribution.cents,
      months: goal.months,
      targetCents: goal.targetWealth.cents,
    };
  },

  /**
   * Reconstrói a meta a partir do documento gravado.
   *
   * Devolve `null` quando [raw] não é objeto ou não traz `months` — o prazo é
   * o único campo sem padrão defensável. Valores monetários ausentes voltam
   * como zero, o que produz uma meta que `RequiredReturnSolver.solve` recusa
   * com [InvalidInput], em vez de uma meta silenciosamente errada.
   *
   * **Usa `FinancialGoal.unvalidated` de propósito.** O documento pode ter
   * sido gravado antes de `FinancialGoal.create` existir, e recusar a leitura
   * aqui apagaria da tela um estudo que o usuário salvou. O plano defeituoso
   * atravessa e é recusado no ponto em que vira número, com o motivo à vista.
   */
  decodeGoal(raw: unknown): FinancialGoal | null {
    if (!isJsonObject(raw)) return null;
    const months = numberOrNull(raw['months']);
    if (months === null || !Number.isFinite(months)) return null;
    const cents = (key: string): number => {
      const v = numberOrNull(raw[key]);
      return v === null || !Number.isFinite(v) ? 0 : toInt(v);
    };
    return FinancialGoal.unvalidated({
      initialContribution: new Money(cents('initialCents')),
      monthlyContribution: new Money(cents('monthlyCents')),
      months: toInt(months),
      targetWealth: new Money(cents('targetCents')),
    });
  },
} as const;
