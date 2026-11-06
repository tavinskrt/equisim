import { comparePortfolios, correlationOf, requestedWindow } from '../../app/backtest';
import { portfolioKey, services } from '../../app/hooks';
import { useQuery } from '../../app/query';
import { usePreferences } from '../../app/state/preferences-store';
import { useStudy } from '../../app/state/study-store';

/**
 * A comparação Principal × Reserva, uma ação de cada ativo no início da janela
 * (decisão 161). A chave carrega tudo de que o resultado depende — as duas
 * composições e a janela —, então mudar um ativo refaz a simulação e voltar à
 * composição anterior reaproveita a que já rodou. A meta não entra: o plano de
 * aportes não compra nada aqui.
 */
export function useComparison() {
  const principal = useStudy((s) => s.study.principal);
  const reserve = useStudy((s) => s.study.reserve);
  const settings = usePreferences((s) => s.backtest);
  const empty = principal.isEmpty && reserve.isEmpty;
  const key = empty ? null : `backtest:${settings.windowYears}:${portfolioKey(principal)}|${portfolioKey(reserve)}`;
  return useQuery(key, () => {
    const s = services();
    return comparePortfolios({
      principal,
      reserve,
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
