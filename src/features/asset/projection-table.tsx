import { type ManualOutcome, type ManualPremises, type ManualValuation, ValuationLane } from '../../core';
import { Fmt } from '../../copy';
import { cn } from '../../ui/cn';

const inMillions = (v: number | null | undefined) =>
  v === null || v === undefined || !Number.isFinite(v) ? '—' : `${v < 0 ? '−' : ''}${Fmt.ratio(Math.abs(v) / 1e6, 1)}`;

/**
 * **Ano a ano**: a projeção de dez anos e a perpetuidade, em milhões. O fluxo
 * de cada ano chega no meio dele, como no motor: valor presente = fluxo ÷ fator.
 */
export function ProjectionTable({ m, p, output }: { m: ManualValuation; p: ManualPremises; output: ManualOutcome }) {
  const firm = m.lane === ValuationLane.firm;
  const header = [
    'Ano',
    'Crescimento',
    firm ? 'Lucro operacional' : 'Lucro líquido',
    'Reinvestido',
    ...(firm ? ['Fluxo da firma', 'Dívida'] : []),
    firm ? 'Fluxo do acionista' : 'Fluxo',
    'Taxa',
    'Fator',
    'Valor presente',
  ];
  const rows: string[][] = output.years.map((y) => [
    String(y.year),
    Fmt.percent(y.growth, { decimals: 1 }),
    inMillions(y.profit),
    Fmt.percent(y.retention, { decimals: 0 }),
    ...(firm ? [inMillions(y.firmFlow), inMillions(y.debtService)] : []),
    inMillions(y.flow),
    Fmt.percent(y.rate, { decimals: 2 }),
    Fmt.ratio(y.discountFactor, 3),
    inMillions(y.presentValue),
  ]);
  const lastFactor = output.years[output.years.length - 1]?.discountFactor ?? Number.NaN;
  const terminal = [
    'Perpetuidade',
    Fmt.percent(p.perpetualGrowth, { decimals: 1 }),
    '',
    '',
    ...(firm ? ['', ''] : []),
    `${inMillions(output.terminalValue)} no ano ${output.years.length}`,
    Fmt.percent(output.terminalRate, { decimals: 2 }),
    Fmt.ratio(lastFactor, 3),
    inMillions(output.terminalPresentValue),
  ];
  const total = [
    'VPL',
    ...Array.from({ length: header.length - 2 }, () => ''),
    inMillions(output.explicitPresentValue + output.terminalPresentValue),
  ];
  return (
    <div>
      <div className="-mx-1 overflow-x-auto px-1 scrollbar-thin">
        <table className="w-full min-w-[640px] text-caption">
          <caption className="sr-only">Projeção ano a ano, em milhões de reais</caption>
          <thead>
            <tr className="border-b border-divider">
              {header.map((h, i) => (
                <th key={h} scope="col" className={cn('whitespace-nowrap px-2 py-2 font-medium text-fg-2', i === 0 ? 'text-left' : 'text-right')}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="num text-fg">
            {[...rows, terminal].map((r, ri) => (
              <tr key={ri} className={cn('border-b border-divider', ri === rows.length && 'bg-sunken')}>
                {r.map((v, i) => (
                  <td key={i} className={cn('whitespace-nowrap px-2 py-1.5', i === 0 ? 'text-left' : 'text-right')}>
                    {v}
                  </td>
                ))}
              </tr>
            ))}
            <tr className="font-bold">
              {total.map((v, i) => (
                <td key={i} className={cn('whitespace-nowrap px-2 py-2', i === 0 ? 'text-left' : 'text-right')}>
                  {v}
                </td>
              ))}
            </tr>
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-caption text-fg-3">
        {firm
          ? 'Fluxo do acionista = fluxo da firma − serviço da dívida (juros depois do imposto, menos o rendimento do caixa, menos a dívida nova que acompanha o crescimento).'
          : 'Fluxo = lucro × (1 − parcela reinvestida).'}
      </p>
    </div>
  );
}
