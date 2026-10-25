import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts';

import type { Portfolio } from '../../core';
import { Fmt } from '../../copy';
import { Panel } from '../../ui/card';
import { EmptyState } from '../../ui/feedback';

const slots = ['var(--chart-1)', 'var(--chart-2)', 'var(--chart-3)', 'var(--chart-4)', 'var(--chart-5)'] as const;
const otherColor = 'var(--border-strong)';

/**
 * A cor segue o setor, e não a posição dele no ranking: o setor recebe o
 * próximo matiz livre **na primeira vez em que aparece na sessão**, e o
 * mantém. Sem isso, incluir um ativo repintaria os setores que já estavam lá.
 * Do sexto em diante, os setores se juntam em "Outros" — um sexto matiz
 * gerado não passaria no validador da paleta.
 */
const registry = new Map<string, number>();
function slotOf(key: string): number | null {
  const hit = registry.get(key);
  if (hit !== undefined) return hit;
  if (registry.size >= slots.length) return null;
  registry.set(key, registry.size);
  return registry.size - 1;
}

interface Slice {
  readonly key: string;
  readonly label: string;
  readonly weight: number;
  readonly count: number;
  readonly color: string;
}

export function sectorSlices(portfolio: Portfolio): Slice[] {
  const by = new Map<string, { label: string; weight: number; count: number }>();
  for (const e of portfolio.entries.values()) {
    const key = e.sector.isUnknown ? '__sem__' : e.sector.key;
    const label = e.sector.isUnknown ? 'Não classificado' : e.sector.label;
    const cur = by.get(key) ?? { label, weight: 0, count: 0 };
    by.set(key, { label, weight: cur.weight + e.weight.value, count: cur.count + 1 });
  }
  const named: Slice[] = [];
  let other = { weight: 0, count: 0 };
  for (const [key, v] of [...by.entries()].sort((a, b) => a[1].label.localeCompare(b[1].label, 'pt-BR'))) {
    const slot = key === '__sem__' ? null : slotOf(key);
    if (slot === null) other = { weight: other.weight + v.weight, count: other.count + v.count };
    else named.push({ key, label: v.label, weight: v.weight, count: v.count, color: slots[slot]! });
  }
  named.sort((a, b) => b.weight - a.weight);
  if (other.count > 0) named.push({ key: '__outros__', label: 'Outros', weight: other.weight, count: other.count, color: otherColor });
  return named;
}

/** A rosca setorial da Principal, com a tabela dos pesos ao lado — que é também a legenda. */
export function SectorDonut({ portfolio }: { portfolio: Portfolio }) {
  const slices = sectorSlices(portfolio);
  return (
    <Panel title="Setores da Principal" subtitle="Peso do aporte por setor da B3">
      {slices.length === 0 ? (
        <EmptyState title="Sem ativos" message="A rosca aparece quando a Principal tiver ativos." className="py-6" />
      ) : (
        <div className="flex flex-col items-center gap-4 sm:flex-row lg:flex-col">
          <div className="size-40 shrink-0" aria-hidden>
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={slices}
                  dataKey="weight"
                  nameKey="label"
                  innerRadius="62%"
                  outerRadius="100%"
                  paddingAngle={slices.length > 1 ? 2 : 0}
                  stroke="var(--surface)"
                  strokeWidth={2}
                  isAnimationActive={false}
                >
                  {slices.map((s) => (
                    <Cell key={s.key} fill={s.color} />
                  ))}
                </Pie>
                <Tooltip
                  cursor={false}
                  content={({ active, payload }) => {
                    const p = payload?.[0]?.payload as Slice | undefined;
                    if (!active || p === undefined) return null;
                    return (
                      <div className="rounded-md border border-line bg-raised px-2.5 py-1.5 text-body-sm text-fg shadow-pop">
                        <p className="font-semibold">{p.label}</p>
                        <p className="num text-fg-2">
                          {Fmt.percent(p.weight, { decimals: 1 })} · {p.count} {p.count === 1 ? 'ativo' : 'ativos'}
                        </p>
                      </div>
                    );
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
          </div>
          <table className="w-full text-body-sm">
            <caption className="sr-only">Peso da Principal por setor</caption>
            <tbody>
              {slices.map((s) => (
                <tr key={s.key} className="border-b border-divider last:border-0">
                  <th scope="row" className="py-1.5 text-left font-normal text-fg-2">
                    <span className="flex items-center gap-2">
                      <span aria-hidden className="size-2.5 shrink-0 rounded-full" style={{ background: s.color }} />
                      <span className="truncate">{s.label}</span>
                    </span>
                  </th>
                  <td className="num whitespace-nowrap py-1.5 pl-3 pr-2 text-right text-caption text-fg-3">
                    {s.count} {s.count === 1 ? 'ativo' : 'ativos'}
                  </td>
                  <td className="num w-16 py-1.5 text-right font-semibold text-fg">{Fmt.percent(s.weight, { decimals: 1 })}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}
