import { curveLinear } from '@visx/curve';

import type { TrackingView } from '../../app/tracking';
import type { DateTime } from '../../core';
import { Fmt } from '../../copy';
import { ChartTooltip, Grid, Line, LineChart, TooltipContent, XAxis, YAxis } from '../../ui/charts/bklit';
import { ChartFrame, DataTable, type LegendItem } from '../../ui/charts/chart-frame';

/** Pontos que o gráfico desenha, no máximo: a forma não precisa de cada pregão, e o SVG fica leve. */
const MAX_POINTS = 260;

interface Series {
  readonly key: string;
  readonly label: string;
  readonly color: string;
  readonly values: readonly number[];
  readonly dashed?: boolean;
  readonly width?: number;
}

const colors: Record<string, string> = {
  exigido: 'var(--chart-1)',
  cdi: 'var(--chart-2)',
  ibov: 'var(--chart-3)',
  esperado: 'var(--chart-4)',
};

/** Os índices que o gráfico desenha: um a cada passo, mais o último pregão. */
function sampled(n: number): number[] {
  const step = Math.max(1, Math.ceil(n / MAX_POINTS));
  const out: number[] = [];
  for (let i = 0; i < n; i += step) out.push(i);
  if (out[out.length - 1] !== n - 1) out.push(n - 1);
  return out;
}

/** O último pregão de cada mês, para a tabela. */
function monthEnds(dates: readonly DateTime[]): number[] {
  const out: number[] = [];
  dates.forEach((d, i) => {
    const next = dates[i + 1];
    if (next === undefined || next.month !== d.month || next.year !== d.year) out.push(i);
  });
  return out;
}

/**
 * **A carteira realizada contra a Meta**: o patrimônio dia a dia da carteira
 * que compra o maior potencial, e os mesmos aportes, nas mesmas datas, no
 * caminho exigido pela meta, no esperado da carteira, no CDI e no Ibovespa
 * que de fato aconteceram (decisão 159).
 *
 * É a curva de acumulação da Meta com o eixo de datas reais: onde ela dizia
 * "em 5 anos", esta diz "de março de 2021 até hoje".
 */
export function TrackingChart({ view }: { view: TrackingView }) {
  const { outcome } = view;
  const series: Series[] = [
    // A carteira na cor do texto, e não na da marca: o verde já é o exigido,
    // como na curva de acumulação da Meta, e duas curvas verdes se confundem.
    { key: 'carteira', label: 'Carteira realizada', color: 'var(--fg)', values: outcome.wealth, width: 2.5 },
    ...view.curves.map((c) => ({ key: c.key, label: c.label, color: colors[c.key] ?? 'var(--fg-2)', values: c.values })),
    { key: 'aportes', label: 'Só os aportes', color: 'var(--fg-3)', values: outcome.contributed, dashed: true, width: 1.5 },
  ];
  const idx = sampled(outcome.dates.length);
  const points = idx.map((i) => {
    const d = outcome.dates[i]!;
    const row: Record<string, unknown> = { date: new Date(d.millisecondsSinceEpoch), i };
    for (const s of series) row[s.key] = s.values[i] ?? 0;
    return row;
  });
  const legend: LegendItem[] = series.map((s) => {
    const curve = view.curves.find((c) => c.key === s.key);
    const rate = curve?.annual ?? null;
    return {
      key: s.key,
      label: rate === null || s.key === 'carteira' ? s.label : `${s.label} (${Fmt.percent(rate, { decimals: 1 })} a.a.)`,
      color: s.color,
      dashed: s.dashed,
    };
  });
  const labels = idx.map((i) => Fmt.shortDate(outcome.dates[i]!));
  const ends = monthEnds(outcome.dates);

  return (
    <ChartFrame
      title="Carteira realizada contra a meta"
      subtitle={`Os mesmos aportes, nas mesmas datas, em cada destino · ${Fmt.date(outcome.dates[0]!)} a ${Fmt.date(outcome.lastDate)}`}
      legend={legend}
      height={300}
      chart={
        <LineChart
          data={points}
          aspectRatio=""
          className="bklit-chart h-full"
          // A Bklit prende o toque para o arrasto; aqui não há arrasto, e a
          // página tem de rolar com o dedo por cima da curva.
          style={{ touchAction: 'pan-y' }}
          // À direita, folga para o rótulo do último mês, centrado na borda.
          margin={{ top: 12, right: 24, bottom: 28, left: 76 }}
        >
          <Grid horizontal />
          {series.map((s) => (
            // Segmento reto e sem esmaecer as pontas, como na evolução do
            // backtest: o último pregão é o resultado, e não pode sumir.
            <Line
              key={s.key}
              dataKey={s.key}
              stroke={s.color}
              strokeWidth={s.width ?? 2}
              curve={curveLinear}
              fadeEdges={false}
              {...(s.dashed ? { dashFromIndex: 0, dashArray: '4,3' } : {})}
            />
          ))}
          <YAxis formatValue={(v) => Fmt.compactMoney(v)} />
          <XAxis labels={labels} numTicks={5} />
          <ChartTooltip
            showDatePill={false}
            content={({ point }) => {
              const i = point['i'] as number;
              return (
                <TooltipContent
                  title={Fmt.date(outcome.dates[i]!)}
                  rows={series.map((s) => ({ label: s.label, color: s.color, value: Fmt.compactMoney(s.values[i] ?? 0) }))}
                />
              );
            }}
          />
        </LineChart>
      }
      table={
        <DataTable
          caption="Patrimônio ao fim de cada mês, por destino"
          columns={['Fim do mês', ...series.map((s) => s.label)]}
          rows={ends.map((i) => [Fmt.date(outcome.dates[i]!), ...series.map((s) => Fmt.money(s.values[i] ?? 0))])}
        />
      }
      footer="Carteira: ações a mercado mais o caixa, com proventos creditados na data ex (JCP líquido da retenção na fonte: 15% até 2025 e 17,5% desde 2026) e a tarifa da B3. Exigido e esperado: os aportes compostos à taxa anual, base de 365 dias. CDI: a série diária do Banco Central. Ibovespa: índice de retorno total da B3. Sem imposto sobre ganho de capital e sem spread de compra."
    />
  );
}
