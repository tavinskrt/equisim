import type { BacktestOutcome } from '../../core';
import { Fmt } from '../../copy';
import { ChartFrame, DataTable } from '../../ui/charts/chart-frame';
import { cn } from '../../ui/cn';
import { PortfolioBadge } from './portfolio-badge';

interface Bridge {
  readonly name: string;
  readonly color: string;
  /** Em centavos, para a identidade fechar sem erro de ponto flutuante. */
  readonly invested: number;
  readonly costs: number;
  readonly marketGain: number;
  readonly final: number;
}

/**
 * A ponte da compra ao patrimônio, **em centavos inteiros**:
 *
 *     investido = preço das ações + custos       (uma ação de cada, decisão 161)
 *     final     = posições a mercado
 *  ⇒ final     = investido − custos + ganho de mercado
 *
 * Com uma compra só, que custa exatamente o que as ações e a tarifa custaram,
 * não sobra caixa, e o ganho de mercado é o que o preço fez com as ações.
 */
export function bridgeOf(name: string, color: string, o: BacktestOutcome): Bridge {
  const invested = o.totalContributed.cents;
  const costs = o.transactionCosts.cents;
  const final = o.finalValue.cents;
  return { name, color, invested, costs, marketGain: final - (invested - costs), final };
}

const money = (cents: number) => Fmt.money(cents / 100);
const signedMoney = (cents: number) => `${cents > 0 ? '+' : cents < 0 ? '−' : ''}${Fmt.money(Math.abs(cents) / 100)}`;

/**
 * **Da compra ao patrimônio**: quanto a cesta custou, quanto a tarifa levou,
 * quanto o mercado somou ou tirou, e onde a carteira terminou. Barras
 * flutuantes, uma escala para as duas carteiras — comprimentos iguais, valores
 * iguais.
 */
export function WealthBridge({ principal, reserve }: { principal: BacktestOutcome | null; reserve: BacktestOutcome | null }) {
  const bridges = [
    ...(principal !== null ? [bridgeOf('Principal', 'var(--brand)', principal)] : []),
    ...(reserve !== null ? [bridgeOf('Reserva', 'var(--reserve)', reserve)] : []),
  ];
  const max = Math.max(1, ...bridges.flatMap((b) => [b.invested, b.final, b.invested - b.costs]));
  const pct = (cents: number) => `${(Math.max(0, cents) / max) * 100}%`;

  return (
    <ChartFrame
      title="Da compra ao patrimônio"
      subtitle="Investido − custos ± ganho de mercado = patrimônio final"
      chart={
        <div className="space-y-5">
          {bridges.map((b) => {
            const afterCosts = b.invested - b.costs;
            const gainLow = Math.min(afterCosts, b.final);
            const gainHigh = Math.max(afterCosts, b.final);
            return (
              <div key={b.name}>
                <PortfolioBadge name={b.name} color={b.color} />
                <dl className="mt-2 space-y-1.5">
                  <BridgeRow label="Investido" value={money(b.invested)} from={0} to={b.invested} pct={pct} fill={b.color} faded />
                  <BridgeRow label="Custos" value={signedMoney(-b.costs)} from={afterCosts} to={b.invested} pct={pct} fill="var(--negative)" />
                  <BridgeRow
                    label={b.marketGain >= 0 ? 'Ganho de mercado' : 'Perda de mercado'}
                    value={signedMoney(b.marketGain)}
                    valueTone={b.marketGain > 0 ? 'text-positive' : b.marketGain < 0 ? 'text-negative' : undefined}
                    from={gainLow}
                    to={gainHigh}
                    pct={pct}
                    fill={b.marketGain >= 0 ? 'var(--positive)' : 'var(--negative)'}
                  />
                  <BridgeRow label="Patrimônio final" value={money(b.final)} from={0} to={b.final} pct={pct} fill={b.color} strong />
                </dl>
              </div>
            );
          })}
        </div>
      }
      table={
        <DataTable
          caption="Da compra ao patrimônio, por carteira"
          columns={['Parcela', ...bridges.map((b) => b.name)]}
          rows={[
            ['Investido', ...bridges.map((b) => money(b.invested))],
            ['Custos (tarifa da B3)', ...bridges.map((b) => signedMoney(-b.costs))],
            ['Ganho de mercado', ...bridges.map((b) => signedMoney(b.marketGain))],
            ['Patrimônio final', ...bridges.map((b) => money(b.final))],
          ]}
        />
      }
      footer="O investido é o que a cesta custou no primeiro pregão: uma ação de cada ativo, mais a tarifa da B3. As duas cestas custam valores diferentes, então compare as carteiras pela base 100, e não pelo patrimônio."
    />
  );
}

function BridgeRow(props: {
  label: string;
  value: string;
  from: number;
  to: number;
  pct: (cents: number) => string;
  fill: string;
  faded?: boolean;
  strong?: boolean;
  valueTone?: string;
}) {
  const left = props.pct(Math.min(props.from, props.to));
  const width = props.pct(Math.abs(props.to - props.from));
  return (
    <div className="grid grid-cols-[minmax(96px,132px)_minmax(0,1fr)_auto] items-center gap-3">
      <dt className={cn('text-body-sm', props.strong ? 'font-semibold text-fg' : 'text-fg-2')}>{props.label}</dt>
      <div className="relative h-3 rounded-sm bg-sunken" aria-hidden>
        <div
          className="absolute inset-y-0 rounded-sm"
          style={{ left, width, minWidth: props.to !== props.from ? 2 : 0, background: props.fill, opacity: props.faded ? 0.45 : 1 }}
        />
      </div>
      <dd className={cn('num min-w-28 text-right text-body-sm', props.strong ? 'font-semibold' : '', props.valueTone ?? 'text-fg')}>{props.value}</dd>
    </div>
  );
}
