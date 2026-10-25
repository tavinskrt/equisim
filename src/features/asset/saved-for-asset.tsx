import type { ValuationResult } from '../../core';
import { useSavedValuations } from '../../app/state/saved-valuations-store';
import { Panel } from '../../ui/card';
import { SavedValuationItem } from '../valuations/saved-valuation-item';

/**
 * Os valuations que o usuário confirmou para este ativo (decisão 150), logo
 * abaixo do preço do motor com que eles se comparam. Sem nenhum, não ocupa
 * espaço.
 */
export function SavedForAsset({ result }: { result: ValuationResult }) {
  const status = useSavedValuations((s) => s.status);
  const records = useSavedValuations((s) => s.records).filter((r) => r.ticker === result.ticker);

  if (status === 'error' && records.length === 0) {
    return (
      <Panel title="Seus valuations salvos">
        <p className="text-body-sm text-fg-2">
          Não foi possível carregar os seus valuations salvos agora. Os que você confirmar continuam indo ao painel de logs.
        </p>
      </Panel>
    );
  }
  if (records.length === 0) return null;
  return (
    <Panel
      title="Seus valuations salvos"
      subtitle={`${records.length} confirmado(s) na edição, do mais recente ao mais antigo. Cada um também está no painel de logs.`}
    >
      <div className="divide-y divide-divider">
        {records.map((r) => (
          <SavedValuationItem key={r.id} record={r} todayLane={result.manual?.lane ?? null} />
        ))}
      </div>
    </Panel>
  );
}
