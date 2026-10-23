import type { BacktestOutcome } from '../../core';
import { Fmt, trendOf } from '../../copy';
import { Card, SectionHeader } from '../../ui/card';
import { cn } from '../../ui/cn';
import { HintPopover } from '../../ui/hint';
import { Metric, MetricRow } from '../../ui/metric';
import { type Tone, toneText } from '../../ui/tone';
import { hypotheticalReserve, metricsGlossary } from './glossary';
import { PortfolioBadge, PortfolioColors } from './portfolio-badge';

interface Cell {
  readonly text: string;
  readonly tone: Tone;
}

interface Row {
  readonly label: string;
  readonly note: string | null;
  /** A grandeza principal do cartão: sem destaque, o patrimônio final se leria com a voz do Calmar. */
  readonly highlight?: boolean;
  readonly cells: readonly Cell[];
}

const pct = (v: number, signed = false, tone?: Tone): Cell => ({ text: Fmt.percent(v, { signed }), tone: tone ?? (signed ? trendOf(v) : 'neutral') });
const ratio = (v: number): Cell => ({ text: Fmt.ratio(v), tone: 'neutral' });
const money = (v: number): Cell => ({ text: Fmt.money(v), tone: 'neutral' });
const xirr = (v: number | null): Cell => (v === null ? { text: '—', tone: 'blocked' } : pct(v, true));

/** O modo Essencial fica com o que responde "qual rendeu mais, e quanto custou de susto": os números são os mesmos do Completo. */
const essentialRows = new Set(['Patrimônio final', 'Aportado', 'TWR', 'XIRR', 'Máx. drawdown']);

function rowsOf(portfolios: readonly BacktestOutcome[]): Row[] {
  const each = (f: (o: BacktestOutcome) => Cell) => portfolios.map(f);
  return [
    { label: 'Patrimônio final', note: 'posições mais caixa', highlight: true, cells: each((o) => money(o.finalValue.reais)) },
    { label: 'Aportado', note: 'capital do investidor', cells: each((o) => money(o.totalContributed.reais)) },
    { label: 'Alocado', note: 'do aportado, o que virou ação', cells: each((o) => money(o.totalAllocated.reais)) },
    { label: 'Custos', note: 'tarifa da B3 nas compras', cells: each((o) => money(o.transactionCosts.reais)) },
    { label: 'Em caixa', note: 'sobra à espera do próximo aporte', cells: each((o) => money(o.residualCash.reais)) },
    { label: 'TWR', note: 'da composição', cells: each((o) => pct(o.metrics.timeWeightedReturn, true)) },
    { label: 'XIRR', note: 'retorno do investidor', cells: each((o) => xirr(o.metrics.moneyWeightedReturn)) },
    { label: 'CAGR', note: null, cells: each((o) => pct(o.metrics.cagr, true)) },
    { label: 'Volatilidade', note: 'anualizada', cells: each((o) => pct(o.metrics.volatility)) },
    { label: 'Máx. drawdown', note: null, cells: each((o) => pct(o.metrics.maxDrawdown, false, 'negative')) },
    { label: 'Sharpe', note: 'vs CDI observado', cells: each((o) => ratio(o.metrics.sharpe)) },
    { label: 'Sortino', note: null, cells: each((o) => ratio(o.metrics.sortino)) },
    { label: 'Calmar', note: null, cells: each((o) => ratio(o.metrics.calmar)) },
  ];
}

/**
 * **As carteiras lado a lado**: uma coluna por carteira, e comparar vira um
 * movimento de olho. O cabeçalho de coluna repete o nome sob o ponto colorido
 * — patrimônio é exatamente o número que se atribui à carteira errada.
 *
 * É uma tabela de verdade (`<table>`): o leitor de tela anuncia o cabeçalho de
 * cada célula. Abaixo de 400 px ela continua tabela, com a coluna do rótulo
 * quebrando a ressalva em linha própria.
 */
export function SideBySidePortfolios(props: { principal: BacktestOutcome; reserve: BacktestOutcome; essential?: boolean }) {
  const { principal, reserve } = props;
  const columns = [
    { name: 'Principal', color: PortfolioColors.principal },
    { name: 'Reserva', color: PortfolioColors.reserve },
  ];
  const all = rowsOf([principal, reserve]);
  const rows = props.essential === true ? all.filter((r) => essentialRows.has(r.label)) : all;
  return (
    <Card className="p-4 sm:p-5">
      <SectionHeader
        title="Carteiras lado a lado"
        subtitle="Mesma janela e mesmos aportes — só a composição difere"
        actions={
          <HintPopover
            title="Indicadores das duas carteiras"
            intro="Todos se referem à janela simulada. As duas carteiras recebem aportes idênticos nas mesmas datas — só a composição difere, então o que sobra de diferença entre as colunas é a escolha dos ativos."
            entries={metricsGlossary}
            size="md"
          />
        }
      />
      <table className="mt-4 w-full max-w-2xl text-body-sm">
        <caption className="sr-only">Indicadores da Principal e da Reserva na janela simulada</caption>
        <thead>
          <tr>
            <th scope="col" className="w-full pb-2 text-left">
              <span className="sr-only">Indicador</span>
            </th>
            {columns.map((c) => (
              <th key={c.name} scope="col" className="pb-2 pl-4 text-right whitespace-nowrap">
                <PortfolioBadge name={c.name} color={c.color} />
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.label} className="border-t border-divider">
              <th scope="row" className="py-2 pr-2 text-left font-normal">
                <span className={cn('block', r.highlight ? 'font-semibold text-fg' : 'text-fg-2')}>{r.label}</span>
                {r.note !== null && <span className="block text-caption text-fg-3">{r.note}</span>}
              </th>
              {r.cells.map((c, i) => (
                <td
                  key={i}
                  className={cn('num py-2 pl-4 text-right whitespace-nowrap', r.highlight ? 'text-title-sm font-semibold' : 'font-medium', toneText[c.tone])}
                >
                  {c.text}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="mt-3 text-caption text-fg-3">{hypotheticalReserve}</p>
    </Card>
  );
}

/**
 * A legenda de capital sob o patrimônio: aportado, alocado e custos. **O caixa só é
 * nomeado acima de um real**: "R$ 0,40 em caixa" ao lado de seis dígitos
 * transformaria troco em fato econômico.
 */
export function capitalCaption(o: BacktestOutcome): string {
  const base = `aportado ${Fmt.money(o.totalContributed.reais)} · alocado ${Fmt.money(o.totalAllocated.reais)} · custos ${Fmt.money(o.transactionCosts.reais)}`;
  return o.residualCash.cents < 100 ? base : `${base} — ${Fmt.money(o.residualCash.reais)} em caixa`;
}

/** Os indicadores de **uma** carteira, quando só ela foi simulada: a comparação lado a lado não tem sentido com uma coluna. */
export function SinglePortfolioMetrics({ title, outcome, isReserve }: { title: string; outcome: BacktestOutcome; isReserve: boolean }) {
  const m = outcome.metrics;
  return (
    <Card className="p-4 sm:p-5">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <PortfolioBadge name={title} color={isReserve ? PortfolioColors.reserve : PortfolioColors.principal} />
          <p className="num mt-2 text-display font-semibold tracking-tight text-fg">{Fmt.money(outcome.finalValue.reais)}</p>
          <p className="mt-1 text-caption text-fg-3">{capitalCaption(outcome)}</p>
        </div>
        <div className="text-right">
          <p className="eyebrow">TWR</p>
          <p className={cn('num text-title-sm font-semibold', toneText[trendOf(m.timeWeightedReturn)])}>{Fmt.percent(m.timeWeightedReturn, { signed: true })}</p>
        </div>
        <HintPopover
          title={`Indicadores da ${title}`}
          intro="Todos se referem à janela simulada. As duas carteiras recebem aportes idênticos nas mesmas datas — só a composição difere."
          entries={metricsGlossary}
          size="md"
        />
      </div>
      <MetricRow className="mt-5">
        <Metric size="sm" label="XIRR" value={m.moneyWeightedReturn === null ? '—' : Fmt.percent(m.moneyWeightedReturn, { signed: true })} hint="retorno do investidor" tone={trendOf(m.moneyWeightedReturn)} />
        <Metric size="sm" label="CAGR" value={Fmt.percent(m.cagr, { signed: true })} tone={trendOf(m.cagr)} />
        <Metric size="sm" label="Volatilidade" value={Fmt.percent(m.volatility)} hint="anualizada" />
        <Metric size="sm" label="Máx. drawdown" value={Fmt.percent(m.maxDrawdown)} tone="negative" />
        <Metric size="sm" label="Sharpe" value={Fmt.ratio(m.sharpe)} hint="vs CDI observado" />
        <Metric size="sm" label="Sortino" value={Fmt.ratio(m.sortino)} />
        <Metric size="sm" label="Calmar" value={Fmt.ratio(m.calmar)} />
      </MetricRow>
      {isReserve && <p className="mt-4 text-caption text-fg-3">{hypotheticalReserve}</p>}
    </Card>
  );
}
