import { useMemo } from 'react';

import {
  type FeasibilityVerdict,
  type FinancialGoal,
  type GoalAlignment,
  type MarketAnchors,
  type Portfolio,
  type Result,
  type Ticker,
  TransversalSignals,
  type ValuationResult,
} from '../core';
import { PortfolioStudyCodec } from '../data/persistence/portfolio-codec';
import { queryClient, useQuery } from './query';
import { getRuntime } from './runtime';
import type { Services } from './services';
import { usePreferences } from './state/preferences-store';
import { feasibilityWith, goalAlignment, valuateOutcome } from './valuation';

/** A raiz de dependências montada na partida. */
export function services(): Services {
  return getRuntime().services;
}

/**
 * As chaves do cache de consultas. **A chave é o contrato**: duas telas que
 * pedem a mesma avaliação usam a mesma chave e veem o mesmo número — e o
 * painel de logs recebe um evento, e não dois.
 */
export const QueryKeys = {
  anchors: 'anchors',
  skill: 'skill',
  premium: 'premium',
  curve: 'curve',
  betaPrior: 'beta-prior',
  bands: 'bands',
  universe: 'universe',
  profile: (t: Ticker) => `profile:${t.value}`,
  history: (t: Ticker) => `history:${t.value}`,
  valuation: (t: Ticker, monteCarlo: boolean) => `valuation:${monteCarlo ? 'mc' : 'd'}:${t.value}`,
};

/**
 * A avaliação de um ativo pelo cache — a mesma para o Raio-X e para a linha da
 * carteira. Vem como `Result`: a recusa (fora da Porta 0, sem cotação) chega à
 * tela com o motivo.
 */
export function fetchValuationOutcome(t: Ticker, monteCarlo: boolean): Promise<Result<ValuationResult>> {
  return queryClient.fetch(QueryKeys.valuation(t, monteCarlo), () =>
    valuateOutcome(services(), t, { ...usePreferences.getState().valuation, monteCarlo }),
  );
}

/** A avaliação, ou `null` quando os dados não a sustentam. */
export async function fetchValuation(t: Ticker, monteCarlo: boolean): Promise<ValuationResult | null> {
  const outcome = await fetchValuationOutcome(t, monteCarlo);
  return outcome.isOk ? outcome.unwrap() : null;
}

export function useValuation(ticker: Ticker | null) {
  const monteCarlo = usePreferences((s) => s.valuation.monteCarlo);
  return useQuery(ticker === null ? null : QueryKeys.valuation(ticker, monteCarlo), () =>
    fetchValuationOutcome(ticker!, monteCarlo),
  );
}

export function useAnchors() {
  return useQuery<MarketAnchors>(QueryKeys.anchors, () => services().marketAnchors());
}

export function useSkill() {
  return useQuery(QueryKeys.skill, () => services().skillReading());
}

export function usePremium() {
  return useQuery(QueryKeys.premium, () => services().marketPremiumReading());
}

export function useCurve() {
  return useQuery(QueryKeys.curve, () => services().riskFreeCurveReading());
}

export function useCalibratedBands() {
  return useQuery(QueryKeys.bands, () => services().calibratedBands());
}

export function useUniverse() {
  return useQuery(QueryKeys.universe, () => services().universe());
}

export function useProfile(ticker: Ticker | null) {
  return useQuery(ticker === null ? null : QueryKeys.profile(ticker), () => services().profile(ticker!));
}

/** O perfil pelo cache: setor e nome antes de incluir o ativo, para o alerta de concentração operar. */
export function fetchProfile(t: Ticker) {
  return queryClient.fetch(QueryKeys.profile(t), () => services().profile(t));
}

/** Identidade de uma carteira para a chave: ativos **e** pesos. */
export function portfolioKey(p: Portfolio): string {
  return [...p.entries.values()].map((e) => `${e.ticker.value}:${e.weight.value.toFixed(6)}`).join(',');
}

export function goalKey(goal: FinancialGoal | null): string {
  return goal === null ? 'sem-meta' : JSON.stringify(PortfolioStudyCodec.encodeGoal(goal));
}

/**
 * As avaliações dos ativos de uma carteira, em sequência — a ordem dos eventos
 * no painel de logs é a ordem da carteira. Cada ativo passa pelo cache por
 * ativo, então reordenar a carteira não refaz conta nenhuma.
 */
export function usePortfolioValuations(portfolio: Portfolio) {
  const monteCarlo = usePreferences((s) => s.valuation.monteCarlo);
  const tickers = portfolio.tickers;
  const key = tickers.length === 0 ? 'pv:vazia' : `pv:${monteCarlo ? 'mc' : 'd'}:${tickers.map((t) => t.value).join(',')}`;
  return useQuery(key, async () => {
    const out = new Map<Ticker, ValuationResult>();
    for (const t of tickers) {
      const v = await fetchValuation(t, monteCarlo);
      if (v !== null) out.set(t, v);
    }
    return out as ReadonlyMap<Ticker, ValuationResult>;
  });
}

/** Os sinais transversais (item B1) dos ativos de uma carteira. */
export function usePortfolioSignals(portfolio: Portfolio) {
  const tickers = portfolio.tickers;
  const key = `signals:${tickers.map((t) => t.value).join(',')}`;
  return useQuery(key, async () => {
    const out = new Map<Ticker, TransversalSignals>();
    for (const t of tickers) {
      const history = await queryClient.fetch(QueryKeys.history(t), () => services().fundamentals.history(t));
      if (history.isErr) continue;
      out.set(t, TransversalSignals.fromHistory(history.unwrap()));
    }
    return out as ReadonlyMap<Ticker, TransversalSignals>;
  });
}

/** A situação da carteira frente à meta (cartão da meta e barra de contexto). */
export function useGoalAlignment(portfolio: Portfolio, goal: FinancialGoal | null) {
  const monteCarlo = usePreferences((s) => s.valuation.monteCarlo);
  const key = goal === null || portfolio.isEmpty ? null : `align:${monteCarlo ? 'mc' : 'd'}:${portfolioKey(portfolio)}:${goalKey(goal)}`;
  return useQuery<GoalAlignment | null>(key, async () => {
    const tickers = portfolio.tickers;
    const valuations = new Map<Ticker, ValuationResult>();
    for (const t of tickers) {
      const v = await fetchValuation(t, monteCarlo);
      if (v !== null) valuations.set(t, v);
    }
    return goalAlignment({ services: services(), portfolio, goal, valuations });
  });
}

/**
 * A viabilidade da meta, **síncrona** depois das âncoras: o aviso de meta
 * irreal acompanha o arraste do controle, sem esperar avaliação nenhuma.
 */
export function useFeasibility(goal: FinancialGoal | null): FeasibilityVerdict | null {
  const anchors = useAnchors();
  return useMemo(
    () => (goal === null || anchors.status !== 'success' ? null : feasibilityWith(goal, anchors.data)),
    [goal, anchors.status, anchors.data],
  );
}
