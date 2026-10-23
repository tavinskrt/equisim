import { Download } from 'lucide-react';
import { useState } from 'react';
import { CartesianGrid, Line, LineChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

import type { PortfolioComparison } from '../../app/backtest';
import { type BacktestOutcome, DateTime } from '../../core';
import { Fmt } from '../../copy';
import { axisProps, ChartFrame, DataTable, type LegendItem, TooltipBox } from '../../ui/charts/chart-frame';
import { IconButton } from '../../ui/button';
import { Segmented } from '../../ui/segmented';

type Measure = 'base100' | 'wealth';

interface Row {
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

/**
 * **Evolução comparada**: o índice TWR em base 100 das duas carteiras — a
 * curva que neutraliza os aportes e por isso compara composições —, ou o
 * patrimônio em reais, que salta no dia de cada aporte. Duas vistas, nunca dois
 * eixos: as grandezas têm escalas diferentes.
 */
export function EvolutionChart(props: { result: PortfolioComparison; onExport: () => void }) {
  const { principal, reserve } = props.result;
  const [measure, setMeasure] = useState<Measure>('base100');
  const rows = mergeSeries(principal, reserve, measure);
  const reference = (principal ?? reserve)!;
  const fmt = measure === 'base100' ? (v: number) => Fmt.ratio(v, 1) : (v: number) => Fmt.compactMoney(v);
  const fmtExact = measure === 'base100' ? (v: number) => Fmt.ratio(v, 2) : (v: number) => Fmt.money(v);

  const series = [
    ...(principal !== null ? [{ key: 'principal' as const, label: 'Principal', color: 'var(--brand)' }] : []),
    ...(reserve !== null ? [{ key: 'reserve' as const, label: 'Reserva', color: 'var(--reserve)' }] : []),
  ];
  const legend: LegendItem[] = series.map((s) => ({ key: s.key, label: s.label, color: s.color }));
  const first = rows[0]?.t ?? 0;
  const last = rows[rows.length - 1]?.t ?? 0;

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
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={rows} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <CartesianGrid vertical={false} stroke="var(--grid)" />
            <XAxis
              dataKey="t"
              type="number"
              scale="time"
              domain={[first, last]}
              tickFormatter={(t: number) => Fmt.shortDate(DateTime.fromMillisecondsSinceEpoch(t))}
              minTickGap={32}
              {...axisProps}
            />
            <YAxis width={measure === 'base100' ? 44 : 64} domain={['auto', 'auto']} tickFormatter={fmt} {...axisProps} />
            {measure === 'base100' && <ReferenceLine y={100} stroke="var(--border-strong)" strokeDasharray="3 3" />}
            <Tooltip
              cursor={{ stroke: 'var(--border-strong)' }}
              content={({ active, payload }) => {
                if (!active || payload === undefined || payload.length === 0) return null;
                const row = payload[0]!.payload as Row;
                return (
                  <TooltipBox
                    title={Fmt.date(row.date)}
                    rows={series.map((s) => ({ key: s.key, label: s.label, color: s.color, value: row[s.key] === undefined ? '—' : fmtExact(row[s.key]!) }))}
                  />
                );
              }}
            />
            {series.map((s) => (
              <Line
                key={s.key}
                dataKey={s.key}
                type="linear"
                stroke={s.color}
                strokeWidth={2}
                dot={false}
                connectNulls
                activeDot={{ r: 4, stroke: 'var(--surface)', strokeWidth: 2 }}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      }
      table={
        <DataTable
          caption="Evolução das carteiras ao fim de cada mês"
          columns={['Fim do mês', ...series.map((s) => `${s.label} (${measure === 'base100' ? 'base 100' : 'R$'})`)]}
          rows={monthEnds(rows).map((r) => [Fmt.date(r.date), ...series.map((s) => (r[s.key] === undefined ? '—' : fmtExact(r[s.key]!)))])}
        />
      }
      footer={
        measure === 'base100'
          ? 'Índice ponderado pelo tempo (TWR): o retorno da composição, neutro ao cronograma de aportes. A série diária completa vai no CSV.'
          : 'Posições a mercado mais o caixa, incluindo os aportes — por isso a curva salta no dia de cada um. Para comparar composições, use a base 100.'
      }
    />
  );
}
