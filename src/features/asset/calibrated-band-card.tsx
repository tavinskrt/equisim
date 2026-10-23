import type { ValuationResult } from '../../core';
import { BandCopy, Fmt } from '../../copy';
import { useCalibratedBands } from '../../app/hooks';
import { Panel } from '../../ui/card';
import { Metric, MetricRow } from '../../ui/metric';

/**
 * Onde o preço mais os proventos caíram, nas coortes (itens C2 e C2b). **É a
 * incerteza medida, e não a sensibilidade.** Sem pacote, o cartão não aparece.
 */
export function CalibratedBandCard({ result }: { result: ValuationResult }) {
  const tables = useCalibratedBands();
  if (tables.status !== 'success') return null;
  const bands = BandCopy.readings(result, tables.data);
  if (bands.length === 0) return null;
  return (
    <Panel title="Faixa calibrada" subtitle="Preço mais proventos no horizonte, medido nas coortes">
      <MetricRow className="sm:grid-cols-2">
        {bands.map((b) => (
          <Metric
            key={b.table.months}
            label={`Em ${b.table.months} meses`}
            value={`${Fmt.money(b.low.reais)} a ${Fmt.money(b.high.reais)}`}
            hint={`coortes de ${b.table.firstCohort} a ${b.table.lastCohort}`}
            size="sm"
          />
        ))}
      </MetricRow>
      <p className="mt-3 text-caption leading-relaxed text-fg-2">{BandCopy.reading(bands)}</p>
    </Panel>
  );
}
