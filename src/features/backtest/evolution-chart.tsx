import { curveLinear } from '@visx/curve';
import { Download } from 'lucide-react';
import { useState } from 'react';

import type { PortfolioComparison } from '../../app/backtest';
import type { BacktestOutcome, DateTime } from '../../core';
import { Fmt } from '../../copy';
import { ChartTooltip, Grid, Line, LineChart, TooltipContent, XAxis, YAxis } from '../../ui/charts/bklit';
import { ChartFrame, DataTable, type LegendItem } from '../../ui/charts/chart-frame';
import { IconButton } from '../../ui/button';
import { Segmented } from '../../ui/segmented';

type Measure = 'base100' | 'wealth';
type SeriesKey = 'principal' | 'reserve';

export interface Row {
  readonly t: number;
  readonly date: DateTime;
  principal?: number;
  reserve?: number;
}

/** As duas séries no mesmo eixo de datas: cada curva leva as próprias datas, e nenhuma é desenhada fora de lugar se um pregão faltar a uma delas. */
function mergeSeries(principal: BacktestOutcome | null, reserve: BacktestOutcome | null, measure: Measure): Row[] {
  const byKey = new Map<string, Row>();
  const put = (o: BacktestOutcome | null, field: 'principal' | 'reserve') => {
    if (o === null) return;
    const values = measure === 'base100' ? o.base100 : o.wealth;
    o.dates.forEach((d, i) => {
      let row = byKey.get(d.key);
      if (row === undefined) {
        row = { t: d.millisecondsSinceEpoch, date: d };
        byKey.set(d.key, row);
      }
      row[field] = values[i];
    });
  };
  put(principal, 'principal');
  put(reserve, 'reserve');
  return [...byKey.values()].sort((a, b) => a.t - b.t);
}

/** O último pregão de cada mês: a tabela mostra a trajetória sem as 2.500 linhas diárias, que estão no CSV. */
function monthEnds(rows: readonly Row[]): Row[] {
  const out: Row[] = [];
  rows.forEach((r, i) => {
    const next = rows[i + 1];
    if (next === undefined || next.date.month !== r.date.month || next.date.year !== r.date.year) out.push(r);
  });
  return out;
}

/** Um ponto do gráfico: a data como `Date`, que é o eixo da Bklit, e a linha de origem, que o tooltip lê. */
export interface PlotPoint extends Record<string, unknown> {
  readonly date: Date;
  readonly source: Row;
}

/**
 * Os pontos que o gráfico desenha. O gráfico da Bklit lê todas as curvas de
 * uma tabela só, e um valor ausente vira o topo do gráfico, então:
 *
 * - **no meio** de uma curva, o pregão que falta a ela é interpolado no tempo,
 *   o mesmo segmento reto que o `connectNulls` do Recharts desenhava;
 * - **nas pontas**, o gráfico fica no período em que todas as curvas têm
 *   valor (`trimmed` avisa quando isso corta alguma), porque esticar uma
 *   curva para antes do começo dela inventaria trajetória.
 *
 * O valor interpolado só posiciona a linha: o tooltip lê `source`, que guarda
 * o ausente como ausente, e a tabela e o CSV não passam por aqui.
 */
export function plotPoints(rows: readonly Row[], keys: readonly SeriesKey[]): { points: PlotPoint[]; trimmed: boolean } {
  if (keys.length === 0 || rows.length === 0) return { points: [], trimmed: false };
  let from = 0;
  let to = rows.length - 1;
  for (const k of keys) {
    const first = rows.findIndex((r) => r[k] !== undefined);
    const last = rows.findLastIndex((r) => r[k] !== undefined);
    if (first < 0) return { points: [], trimmed: false };
    from = Math.max(from, first);
    to = Math.min(to, last);
  }
  if (from > to) return { points: [], trimmed: true };
  const span = rows.slice(from, to + 1);
  const points: PlotPoint[] = span.map((r) => ({ date: new Date(r.t), source: r }));
  for (const k of keys) {
    let prev = 0;
    for (let i = 0; i < span.length; i++) {
      if (span[i]![k] === undefined) continue;
      if (i - prev > 1) {
        const a = span[prev]!;
        const b = span[i]!;
        for (let j = prev + 1; j < i; j++) points[j]![k] = a[k]! + ((b[k]! - a[k]!) * (span[j]!.t - a.t)) / (b.t - a.t);
      }
      points[i]![k] = span[i]![k];
      prev = i;
    }
  }
  return { points, trimmed: from > 0 || to < rows.length - 1 };
}

/**
 * **Evolução comparada**: o índice TWR em base 100 das duas carteiras — a
 * curva que neutraliza os aportes e por isso compara composições —, ou o
 * patrimônio em reais, que salta no dia de cada aporte. Duas vistas, nunca dois
 * eixos: as grandezas têm escalas diferentes.
 *
 * O desenho é o gráfico de linha da Bklit UI (decisão 158). A base 100 ajusta
 * o eixo à faixa dos dados, com a linha de 100 tracejada, porque a diferença
 * entre as carteiras é o que se lê ali; o patrimônio em reais parte do zero.
 */
export function EvolutionChart(props: { result: PortfolioComparison; onExport: () => void }) {
  const { principal, reserve } = props.result;
  const [measure, setMeasure] = useState<Measure>('base100');
  const rows = mergeSeries(principal, reserve, measure);
  const reference = (principal ?? reserve)!;
  const fmt = measure === 'base100' ? (v: number) => Fmt.ratio(v, 0) : (v: number) => Fmt.compactMoney(v);
  const fmtExact = measure === 'base100' ? (v: number) => Fmt.ratio(v, 2) : (v: number) => Fmt.money(v);

  const series = [
    ...(principal !== null ? [{ key: 'principal' as const, label: 'Principal', color: 'var(--brand)' }] : []),
    ...(reserve !== null ? [{ key: 'reserve' as const, label: 'Reserva', color: 'var(--reserve)' }] : []),
  ];
  const legend: LegendItem[] = series.map((s) => ({ key: s.key, label: s.label, color: s.color }));
  const { points, trimmed } = plotPoints(
    rows,
    series.map((s) => s.key),
  );
  if (measure === 'base100') for (const p of points) p['base'] = 100;
  const labels = points.map((p) => Fmt.shortDate(p.source.date));
  const footer =
    measure === 'base100'
      ? 'Índice ponderado pelo tempo (TWR): o retorno da composição, neutro ao cronograma de aportes. A série diária completa vai no CSV.'
      : 'Posições a mercado mais o caixa, incluindo os aportes — por isso a curva salta no dia de cada um. Para comparar composições, use a base 100.';

  return (
    <ChartFrame
      title="Evolução comparada"
      subtitle={`${measure === 'base100' ? 'Base 100' : 'Patrimônio em reais'} · ${reference.effectivePeriod.toString()}`}
      legend={legend}
      height={280}
      actions={
        <>
          <Segmented
            size="sm"
            label="Grandeza"
            value={measure}
            onChange={setMeasure}
            options={[
              { value: 'base100', label: 'Base 100' },
              { value: 'wealth', label: 'R$' , ariaLabel: 'Patrimônio em reais' },
            ]}
          />
          <IconButton label="Exportar CSV" tone="brand" onClick={props.onExport}>
            <Download aria-hidden className="size-[18px]" />
          </IconButton>
        </>
      }
      chart={
        <LineChart
          // Trocar a grandeza remonta o gráfico: a curva entra de novo, em vez
          // de se transformar de índice em reais, que não são a mesma conta.
          key={measure}
          data={points}
          aspectRatio=""
          className="bklit-chart h-full"
          // A Bklit prende o toque para o arrasto; aqui não há arrasto, e a
          // página tem de rolar com o dedo por cima da curva.
          style={{ touchAction: 'pan-y' }}
          margin={{ top: 8, right: 12, bottom: 28, left: measure === 'base100' ? 44 : 76 }}
          yDomainFit={measure === 'base100'}
        >
          <Grid horizontal />
          {measure === 'base100' && <Line dataKey="base" stroke="var(--border-strong)" strokeWidth={1} curve={curveLinear} dashFromIndex={0} dashArray="3,3" showHighlight={false} />}
          {series.map((s) => (
            // Segmento reto entre pregões: a curva natural, padrão da Bklit,
            // passa por valores que a carteira nunca teve entre um dia e outro.
            // Sem o esmaecer das pontas, também padrão: o último pregão é o
            // resultado da simulação, e não pode sumir no fundo.
            <Line key={s.key} dataKey={s.key} stroke={s.color} strokeWidth={2} curve={curveLinear} fadeEdges={false} />
          ))}
          <YAxis formatValue={fmt} />
          <XAxis labels={labels} numTicks={5} />
          <ChartTooltip
            showDatePill={false}
            content={({ point }) => {
              const source = (point as PlotPoint).source;
              return (
                <TooltipContent
                  title={Fmt.date(source.date)}
                  rows={series.map((s) => ({ label: s.label, color: s.color, value: source[s.key] === undefined ? '—' : fmtExact(source[s.key]!) }))}
                />
              );
            }}
          />
        </LineChart>
      }
      table={
        <DataTable
          caption="Evolução das carteiras ao fim de cada mês"
          columns={['Fim do mês', ...series.map((s) => `${s.label} (${measure === 'base100' ? 'base 100' : 'R$'})`)]}
          rows={monthEnds(rows).map((r) => [Fmt.date(r.date), ...series.map((s) => (r[s.key] === undefined ? '—' : fmtExact(r[s.key]!)))])}
        />
      }
      footer={trimmed ? `${footer} O gráfico mostra o período em que as duas carteiras têm cotação; a tabela e o CSV trazem cada uma inteira.` : footer}
    />
  );
}
