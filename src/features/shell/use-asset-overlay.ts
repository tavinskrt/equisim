import { useCallback } from 'react';
import { useSearchParams } from 'react-router';

import { Ticker } from '../../core';

/** O parâmetro de busca que abre o Raio-X sobre a área corrente. */
export const assetParam = 'ativo';

/**
 * Abre e fecha o Raio-X. Ele mora **na URL** (`?ativo=PETR4`): o voltar do
 * navegador fecha o painel, e o link copiado abre no mesmo ativo.
 */
export function useAssetOverlay() {
  const [params, setParams] = useSearchParams();
  const raw = params.get(assetParam);
  const ticker = raw === null ? null : Ticker.tryParse(raw);

  const open = useCallback(
    (t: Ticker) => {
      setParams((p) => {
        const next = new URLSearchParams(p);
        next.set(assetParam, t.value);
        return next;
      });
    },
    [setParams],
  );

  const close = useCallback(() => {
    setParams(
      (p) => {
        const next = new URLSearchParams(p);
        next.delete(assetParam);
        return next;
      },
      { replace: true },
    );
  }, [setParams]);

  return { ticker, open, close };
}
