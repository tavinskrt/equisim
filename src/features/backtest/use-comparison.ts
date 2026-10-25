import { comparePortfolios, correlationOf, requestedWindow } from '../../app/backtest';
import { goalKey, portfolioKey, services } from '../../app/hooks';
import { useQuery } from '../../app/query';
import { usePreferences } from '../../app/state/preferences-store';
import { useStudy } from '../../app/state/study-store';

/**
 * A comparação Principal × Reserva sob o plano da meta. A chave carrega tudo
 * de que o resultado depende — as duas composições **com os pesos**, o plano e
 * os parâmetros —, então mudar um peso refaz a simulação e voltar ao peso
 * anterior reaproveita a que já rodou.
 */
export function useComparison() {
  const principal = useStudy((s) => s.study.principal);
  const reserve = useStudy((s) => s.study.reserve);
  const goal = useStudy((s) => s.study.goal);
  const settings = usePreferences((s) => s.backtest);
  const empty = principal.isEmpty && reserve.isEmpty;
  const key =
    empty || goal === null
      ? null
      : `backtest:${settings.windowYears}:${settings.contributionDay}:${portfolioKey(principal)}|${portfolioKey(reserve)}:${goalKey(goal)}`;
  return useQuery(key, () => {
    const s = services();
    return comparePortfolios({
      principal,
      reserve,
      goal,
      settings,
      prices: s.prices,
      today: s.clock(),
      riskFreeRateFor: (w) => s.riskFreeRateForWindow(w),
    });
  });
}

/**
 * A matriz de correlação dos ativos da **Principal**, na janela pedida — como
 * no aplicativo Flutter. A Reserva fica de fora: a pergunta é se a carteira
 * que se tem diversifica, e não se os candidatos andam juntos.
 */
export function useCorrelation() {
  const principal = useStudy((s) => s.study.principal);
  const windowYears = usePreferences((s) => s.backtest.windowYears);
  const tickers = principal.tickers;
  const key = tickers.length < 2 ? null : `correlation:${windowYears}:${tickers.map((t) => t.value).join(',')}`;
  return useQuery(key, () => {
    const s = services();
    return correlationOf({ tickers, window: requestedWindow(s.clock(), windowYears), prices: s.prices });
  });
}
