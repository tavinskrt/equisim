import { CartesianGrid, Line, LineChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

import { type FinancialGoal, RequiredReturnSolver } from '../../core';
import { Fmt } from '../../copy';
import { axisProps, ChartFrame, DataTable, type LegendItem, TooltipBox } from '../../ui/charts/chart-frame';

export interface AccumulationRate {
  readonly key: string;
  readonly label: string;
  /** Taxa **anual efetiva**. */
  readonly annual: number;
  readonly color: string;
  readonly dashed?: boolean;
}

/** Anual efetiva para mensal, **por composição**: `(1+a)^(1/12) − 1`, nunca `a/12`. */
export const monthlyOf = (annual: number) => Math.pow(1 + annual, 1 / 12) - 1;

/**
 * **A curva de acumulação**: o patrimônio mês a mês sob cada taxa — a exigida
 * pela meta, o CDI e o Ibovespa da década, o esperado da carteira e o dos
 * aportes sem rendimento. É o valor futuro de uma série uniforme, a mesma
 * conta que o solver da taxa exigida inverte.
 */
export function AccumulationChart({ goal, rates }: { goal: FinancialGoal; rates: readonly AccumulationRate[] }) {
  const initial = goal.initialContribution.reais;
  const monthly = goal.monthlyContribution.reais;
  const months = goal.months;
  // Um ponto por trimestre basta para a forma, e mantém o SVG leve.
  const step = months > 120 ? 6 : 3;
  const points: Record<string, number>[] = [];
  for (let m = 0; m <= months; m += step) points.push(point(m));
  if (points[points.length - 1]!['m'] !== months) points.push(point(months));

  function point(m: number): Record<string, number> {
    const row: Record<string, number> = { m };
    for (const r of rates) row[r.key] = RequiredReturnSolver.futureValue({ rate: monthlyOf(r.annual), initial, monthly, months: m });
    return row;
  }

  const legend: LegendItem[] = [
    ...rates.map((r) => ({ key: r.key, label: `${r.label} (${Fmt.percent(r.annual, { decimals: 1 })} a.a.)`, color: r.color, dashed: r.dashed })),
    { key: 'meta', label: 'Meta', color: 'var(--fg-2)', dashed: true },
  ];
  const yearTick = (m: number) => `${Math.round(m / 12)}a`;
  // Marcas só em anos inteiros, no máximo seis: com o passo de 3 meses dos
  // pontos, o Recharts escolhia 0a, 3a, 5a, 8a — intervalos desiguais.
  const yearStep = Math.max(1, Math.ceil(months / 12 / 6));
  const yearTicks = Array.from({ length: Math.floor(months / 12 / yearStep) + 1 }, (_, i) => i * yearStep * 12);
  const tableRows = points
    .filter((p) => p['m']! % 12 === 0 || p['m'] === months)
    .map((p) => [Fmt.months(p['m']!), ...rates.map((r) => Fmt.compactMoney(p[r.key]!))]);

  return (
    <ChartFrame
      title="Curva de acumulação"
      subtitle={`O patrimônio mês a mês sob cada taxa, com os mesmos aportes. Meta: ${Fmt.money(goal.targetWealth.reais)}.`}
      legend={legend}
      height={300}
      chart={
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <CartesianGrid vertical={false} stroke="var(--grid)" />
            <XAxis dataKey="m" type="number" domain={[0, months]} ticks={yearTicks} tickFormatter={yearTick} {...axisProps} />
            <YAxis width={80} tickFormatter={(v: number) => Fmt.compactMoney(v)} {...axisProps} />
            <ReferenceLine
              y={goal.targetWealth.reais}
              stroke="var(--fg-2)"
              strokeDasharray="4 3"
              label={{ value: 'Meta', position: 'insideTopLeft', fill: 'var(--fg-2)', fontSize: 11 }}
            />
            <Tooltip
              cursor={{ stroke: 'var(--border-strong)' }}
              content={({ active, payload, label }) =>
                !active || payload === undefined || payload.length === 0 ? null : (
                  <TooltipBox
                    title={Fmt.months(Number(label))}
                    rows={rates.map((r) => ({
                      key: r.key,
                      label: r.label,
                      color: r.color,
                      value: Fmt.compactMoney(Number(payload.find((p) => p.dataKey === r.key)?.value ?? Number.NaN)),
                    }))}
                  />
                )
              }
            />
            {rates.map((r) => (
              <Line
                key={r.key}
                dataKey={r.key}
                type="monotone"
                stroke={r.color}
                strokeWidth={2}
                strokeDasharray={r.dashed ? '4 3' : undefined}
                dot={false}
                activeDot={{ r: 4, stroke: 'var(--surface)', strokeWidth: 2 }}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      }
      table={<DataTable caption="Patrimônio acumulado por taxa" columns={['Prazo', ...rates.map((r) => r.label)]} rows={tableRows} />}
      footer="Valor futuro de uma série uniforme: V₀(1+i)ⁿ + PMT·[((1+i)ⁿ − 1)/i], com a taxa mensal equivalente (1+a)^(1/12) − 1. Sem impostos e sem custos."
    />
  );
}
