import { type FinancialGoal, RequiredReturnSolver } from '../../core';
import { Fmt } from '../../copy';
import { ChartTooltip, Grid, Line, LineChart, TooltipContent, XAxis, YAxis } from '../../ui/charts/bklit';
import { ChartFrame, DataTable, type LegendItem } from '../../ui/charts/chart-frame';

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

/** Um mês no eixo do gráfico: passo fixo de 30 dias, para os meses ficarem equidistantes. */
const MONTH_MS = 30 * 24 * 60 * 60 * 1000;

/** O prazo em anos, para o eixo: "5a" no ano cheio, "2,5a" entre eles. */
const yearLabel = (m: number) => (m % 12 === 0 ? `${m / 12}a` : `${Fmt.ratio(m / 12, 1)}a`);

/**
 * **A curva de acumulação**: o patrimônio mês a mês sob cada taxa — a exigida
 * pela meta, o CDI e o Ibovespa da década, o esperado da carteira e o dos
 * aportes sem rendimento. É o valor futuro de uma série uniforme, a mesma
 * conta que o solver da taxa exigida inverte.
 *
 * **O piloto da Bklit UI** (decisão 156): o desenho é o gráfico de linha da
 * Bklit, com a moldura, a legenda e a tabela de sempre. O eixo dela é de
 * datas, e o desta curva é de prazo: cada ponto ganha uma data sintética, a
 * um passo fixo por mês, que só posiciona o ponto — o rótulo do eixo e o do
 * tooltip dizem o prazo, e nenhuma data aparece.
 */
export function AccumulationChart({ goal, rates }: { goal: FinancialGoal; rates: readonly AccumulationRate[] }) {
  const initial = goal.initialContribution.reais;
  const monthly = goal.monthlyContribution.reais;
  const months = goal.months;
  const target = goal.targetWealth.reais;
  // Um ponto por trimestre basta para a forma, e mantém o SVG leve.
  const step = months > 120 ? 6 : 3;
  const points: Record<string, unknown>[] = [];
  for (let m = 0; m <= months; m += step) points.push(point(m));
  if (points[points.length - 1]!['m'] !== months) points.push(point(months));

  function point(m: number): Record<string, unknown> {
    const row: Record<string, unknown> = { m, date: new Date(m * MONTH_MS), meta: target };
    for (const r of rates) row[r.key] = RequiredReturnSolver.futureValue({ rate: monthlyOf(r.annual), initial, monthly, months: m });
    return row;
  }

  const legend: LegendItem[] = [
    ...rates.map((r) => ({ key: r.key, label: `${r.label} (${Fmt.percent(r.annual, { decimals: 1 })} a.a.)`, color: r.color, dashed: r.dashed })),
    { key: 'meta', label: 'Meta', color: 'var(--fg-2)', dashed: true },
  ];
  const labels = points.map((p) => yearLabel(p['m'] as number));
  const tableRows = points
    .filter((p) => (p['m'] as number) % 12 === 0 || p['m'] === months)
    .map((p) => [Fmt.months(p['m'] as number), ...rates.map((r) => Fmt.compactMoney(p[r.key] as number))]);

  return (
    <ChartFrame
      title="Curva de acumulação"
      subtitle={`O patrimônio mês a mês sob cada taxa, com os mesmos aportes. Meta: ${Fmt.money(target)}.`}
      legend={legend}
      height={300}
      chart={
        <LineChart
          data={points}
          aspectRatio=""
          className="bklit-chart h-full"
          // O gráfico da Bklit prende o toque para o arrasto; aqui ele não tem
          // arrasto, e a página tem de rolar com o dedo por cima da curva.
          style={{ touchAction: 'pan-y' }}
          margin={{ top: 12, right: 12, bottom: 28, left: 76 }}
        >
          <Grid horizontal />
          {rates.map((r) => (
            <Line key={r.key} dataKey={r.key} stroke={r.color} strokeWidth={2} {...(r.dashed ? { dashFromIndex: 0, dashArray: '4,3' } : {})} />
          ))}
          <Line dataKey="meta" stroke="var(--fg-2)" strokeWidth={1.5} dashFromIndex={0} dashArray="4,3" showHighlight={false} />
          <YAxis formatValue={(v) => Fmt.compactMoney(v)} />
          <XAxis labels={labels} numTicks={6} />
          <ChartTooltip
            showDatePill={false}
            content={({ point }) => (
              <TooltipContent
                title={Fmt.months(point['m'] as number)}
                rows={[
                  ...rates.map((r) => ({ label: r.label, color: r.color, value: Fmt.compactMoney(point[r.key] as number) })),
                  { label: 'Meta', color: 'var(--fg-2)', value: Fmt.compactMoney(target) },
                ]}
              />
            )}
          />
        </LineChart>
      }
      table={<DataTable caption="Patrimônio acumulado por taxa" columns={['Prazo', ...rates.map((r) => r.label)]} rows={tableRows} />}
      footer="Valor futuro de uma série uniforme: V₀(1+i)ⁿ + PMT·[((1+i)ⁿ − 1)/i], com a taxa mensal equivalente (1+a)^(1/12) − 1. Sem impostos e sem custos."
    />
  );
}
