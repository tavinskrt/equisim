import type { ValuationResult } from '../../core';
import { DomainCopy, Fmt } from '../../copy';
import { Panel } from '../../ui/card';
import { Metric, MetricRow } from '../../ui/metric';

/**
 * A segunda leitura, por múltiplos de pares (item B5, decisão 118). Fica
 * **depois** da sensibilidade: é o teste de sanidade sobre o nível, e não um
 * preço que compete com o do fluxo descontado.
 */
export function PeerCard({ result }: { result: ValuationResult }) {
  const t = result.triangulation;
  if (t === null) return null;
  const applied = t.readings.filter((r) => r.applied);
  const refused = t.readings.filter((r) => !r.applied);
  return (
    <Panel
      title="Segunda leitura — múltiplos de pares"
      subtitle="Teste de sanidade sobre o nível; o preço justo continua sendo o do fluxo descontado"
    >
      {applied.length === 0 ? (
        <p className="text-body-sm text-fg-2">
          Nenhum múltiplo se aplicou a este ativo.{' '}
          {t.readings.map((r) => `${DomainCopy.multiple(r.kind)}: ${r.refusal === null ? '—' : DomainCopy.refusal(r.refusal)}`).join('; ')}.
        </p>
      ) : (
        <div className="space-y-4">
          <MetricRow>
            {applied.map((r) => (
              <Metric
                key={r.kind.name}
                label={DomainCopy.multiple(r.kind)}
                value={Fmt.money(r.fairValuePerShare!)}
                hint={`${Fmt.ratio(r.peer!.median, 1)}× em ${r.peer!.peers} pares`}
                size="sm"
              />
            ))}
          </MetricRow>
          <MetricRow>
            <Metric
              label="Mediana dos múltiplos"
              value={t.consolidated === null ? '—' : Fmt.money(t.consolidated)}
              hint={`das ${t.applied} leituras que se aplicaram`}
              size="sm"
            />
            <Metric
              label="Contra o fluxo descontado"
              value={t.divergence === null ? '—' : Fmt.percent(t.divergence, { decimals: 0 })}
              hint={t.diverges ? 'as duas leituras discordam' : 'as duas leituras concordam'}
              tone={t.diverges ? 'caution' : 'neutral'}
              size="sm"
            />
          </MetricRow>
          {refused.length > 0 && (
            <p className="text-body-sm text-fg-2">
              Fora:{' '}
              {refused.map((r) => `${DomainCopy.multiple(r.kind)} (${r.refusal === null ? '—' : DomainCopy.refusal(r.refusal)})`).join('; ')}.
            </p>
          )}
        </div>
      )}
    </Panel>
  );
}
