import { useCallback, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router';

import { Ticker } from '../../core';

/** O endereço da página do ativo (decisão 155). */
export const assetPath = (t: Ticker) => `/ativo/${t.value}`;

/**
 * Abre o Raio-X de um ativo: a navegação para a página dele. O Voltar do
 * navegador — e o da página — devolve à área de onde ele foi aberto.
 */
export function useOpenAsset() {
  const navigate = useNavigate();
  return useCallback((t: Ticker) => navigate(assetPath(t)), [navigate]);
}

/** O parâmetro com que o Raio-X abria sobre a área corrente, até a decisão 155. */
export const legacyAssetParam = 'ativo';

/**
 * Link antigo continua valendo: `?ativo=PETR4` em qualquer área vira
 * `/ativo/PETR4`, sem deixar o endereço velho no histórico.
 */
export function useLegacyAssetRedirect() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const raw = params.get(legacyAssetParam);
  useEffect(() => {
    if (raw === null) return;
    const ticker = Ticker.tryParse(raw);
    if (ticker !== null) navigate(assetPath(ticker), { replace: true });
  }, [raw, navigate]);
}
