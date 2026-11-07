import { CalendarClock, History, LineChart as LineIcon, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';

import { fetchValuation, services } from '../../app/hooks';
import { useQuery } from '../../app/query';
import { usePreferences } from '../../app/state/preferences-store';
import { TrackingActions, useTrackings } from '../../app/state/tracking-store';
import { civilToday, cohortMeaning, computeTracking, startDateProblem, type TrackingView, validateStart } from '../../app/tracking';
import {
  type FinancialGoal,
  isoDay,
  parseIsoDay,
  type Portfolio,
  type Ticker,
  TopUpsidePolicy,
  type TrackingOrder,
  type ValuationResult,
} from '../../core';
import { FailureCopy, Fmt, trendOf } from '../../copy';
import type { StoredTracking } from '../../data/persistence/tracking-store';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card, Panel } from '../../ui/card';
import { DataTable } from '../../ui/charts/chart-frame';
import { ConfirmDialog } from '../../ui/dialog';
import { Disclosure } from '../../ui/disclosure';
import { Skeleton } from '../../ui/feedback';
import { TextField } from '../../ui/field';
import { Metric, MetricRow } from '../../ui/metric';
import { Slider } from '../../ui/slider';
import { TrackingChart } from './tracking-chart';

/**
 * **O acompanhamento da carteira**: a Meta deixa de ser só uma
 * projeção e passa a confrontar o plano com o que a carteira de fato fez,
 * comprando a cada aporte o ativo de maior potencial do dia.
 */
export function TrackingSection(props: { goal: FinancialGoal | null; principal: Portfolio }) {
  const { status, items, error } = useTrackings();
  useEffect(() => {
    if (useTrackings.getState().status === 'idle') void TrackingActions.load();
  }, []);

  if (status === 'idle' || status === 'loading') {
    return (
      <Card className="space-y-3 p-5" role="status" aria-label="Carregando o acompanhamento">
        <Skeleton className="h-5 w-56" />
        <Skeleton className="h-24 w-full" />
      </Card>
    );
  }
  if (status === 'error') {
    return (
      <Banner tone="negative" action={<Button size="sm" onClick={() => void TrackingActions.load()}>Tentar de novo</Button>}>
        Não foi possível ler o acompanhamento salvo: {error}
      </Banner>
    );
  }
  const current = items[0];
  if (current === undefined) return <StartTracking goal={props.goal} principal={props.principal} />;
  return <TrackingDetail stored={current} />;
}

function StartTracking(props: { goal: FinancialGoal | null; principal: Portfolio }) {
  const today = useMemo(() => civilToday(services().clock), []);
  const cohorts = useQuery('upside-cohorts', () => services().upsideCohorts());
  const busy = useTrackings((s) => s.busy);
  const [startText, setStartText] = useState(isoDay(today));
  const [day, setDay] = useState(5);
  const [failure, setFailure] = useState<string | null>(null);

  const start = parseIsoDay(startText);
  const cohortData = cohorts.status === 'success' ? cohorts.data : null;
  const problem =
    start === null ? 'Informe a data de início.' : cohorts.status === 'pending' ? null : startDateProblem({ start, today, cohorts: cohortData });
  const tickers = props.principal.tickers;
  const isPast = start !== null && isoDay(start) < isoDay(today);
  const cap = TopUpsidePolicy.defaultCap(tickers.length);
  const goal = props.goal;

  const begin = async () => {
    if (goal === null || start === null) return;
    const valid = validateStart({ tickers, problem });
    if (valid.isErr) {
      setFailure(FailureCopy.of(valid.failureOrNull!));
      return;
    }
    const created = await TrackingActions.start({
      goal,
      tickers,
      start,
      today,
      createdAt: services().clock(),
      contributionDay: day,
      // Sem retorno esperado da carteira desde a decisão 160: o campo do
      // registro fica, para os acompanhamentos gravados antes, e vai vazio.
      expectedReturn: null,
      cohortsGeneratedAt: cohortData?.generatedAt ?? null,
    });
    setFailure(created.isErr ? FailureCopy.of(created.failureOrNull!) : null);
  };

  return (
    <Panel title="Acompanhamento da carteira" subtitle="Compre, a cada aporte, o ativo de maior potencial, e confronte o resultado com a meta">
      <div className="space-y-4">
        <p className="text-body-sm leading-relaxed text-fg-2">
          Cada aporte compra ações inteiras (lote de uma ação, como no mercado fracionário) do ativo de maior potencial da carteira
          Principal entre os que pesam menos de {Fmt.percent(cap, { decimals: 0 })} dela. A sobra fica em caixa para o mês seguinte, e os
          proventos entram no caixa. Cada compra é gravada com o preço e o preço justo do dia, e não muda mais.
        </p>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField
            label="Início da carteira"
            type="date"
            value={startText}
            min={cohortData?.firstDate === null || cohortData === null ? undefined : isoDay(cohortData.firstDate)}
            max={isoDay(today)}
            onChange={(e) => setStartText(e.target.value)}
            error={problem}
            hint="Hoje, ou uma data passada desde a primeira coorte"
          />
          <Slider label="Dia do aporte" value={day} min={1} max={28} step={1} format={(v) => `dia ${v}`} onChange={setDay} />
        </div>
        <p className="text-caption text-fg-3">
          {tickers.length === 0
            ? 'A carteira Principal está vazia.'
            : `${tickers.length} ativo(s): ${tickers.map((t) => t.value).join(', ')}. `}
          {goal !== null &&
            `Aporte inicial de ${Fmt.money(goal.initialContribution.reais)} e mensal de ${Fmt.money(goal.monthlyContribution.reais)}, os da meta.`}
        </p>
        {isPast && (
          <Banner tone="caution" icon={<History aria-hidden className="mt-0.5 size-4 shrink-0" />}>
            Com data passada, cada compra usa o preço justo da coorte trimestral vigente naquele dia — só o que era público ali.{' '}
            {cohortMeaning} Os ativos, porém, são os da carteira de hoje, escolhida por quem já sabe quais empresas sobreviveram: o
            resultado passado tende a sair melhor que o de uma carteira montada naquela data.
          </Banner>
        )}
        {failure !== null && <Banner tone="negative">{failure}</Banner>}
        <Button
          variant="primary"
          icon={<LineIcon aria-hidden className="size-4" />}
          disabled={busy || goal === null || tickers.length === 0 || problem !== null}
          onClick={() => void begin()}
        >
          {busy ? 'Iniciando…' : 'Iniciar acompanhamento'}
        </Button>
      </div>
    </Panel>
  );
}

/** As avaliações de hoje, para os aportes ao vivo, pelo mesmo cache da tela. */
async function liveValuations(tickers: readonly Ticker[]): Promise<ReadonlyMap<Ticker, ValuationResult>> {
  const monteCarlo = usePreferences.getState().valuation.monteCarlo;
  const out = new Map<Ticker, ValuationResult>();
  for (const t of tickers) {
    const v = await fetchValuation(t, monteCarlo);
    if (v !== null) out.set(t, v);
  }
  return out;
}

function TrackingDetail({ stored }: { stored: StoredTracking }) {
  const today = useMemo(() => civilToday(services().clock), []);
  const syncError = useTrackings((s) => s.syncError);
  const key = `tracking:${stored.record.id}:${stored.orders.length}:${isoDay(today)}`;
  const view = useQuery(key, async () => {
    const r = await computeTracking({ services: services(), stored, today, live: liveValuations });
    if (r.isErr) throw new Error(FailureCopy.of(r.failureOrNull!));
    return r.unwrap();
  });

  // As compras decididas agora vão ao armazenamento uma vez por montagem do
  // resultado. Gravadas, a lista muda, a chave muda, e a nova montagem não
  // decide nada de novo.
  const synced = useRef<string | null>(null);
  useEffect(() => {
    if (view.status !== 'success' || 'waiting' in view.data) return;
    const fresh = view.data.outcome.newOrders;
    if (fresh.length === 0 || synced.current === key) return;
    synced.current = key;
    void TrackingActions.appendOrders(stored.record.id, fresh);
  }, [view.status, view.data, key, stored.record.id]);

  return (
    <div className="space-y-4">
      <Panel
        title="Acompanhamento da carteira"
        subtitle={`${stored.record.plan.tickers.length} ativo(s) desde ${Fmt.date(stored.record.plan.start)}, aporte todo dia ${stored.record.plan.contributionDay}`}
        actions={<RemoveTracking id={stored.record.id} />}
      >
        {view.status === 'pending' ? (
          <div className="space-y-3" role="status" aria-label="Montando o acompanhamento">
            <Skeleton className="h-10 w-full" />
            <p className="text-caption text-fg-3">Cotações, proventos e coortes; se houver aporte vencido, também a avaliação de hoje.</p>
          </div>
        ) : view.status === 'error' ? (
          <Banner tone="negative" action={<Button size="sm" onClick={view.refetch}>Tentar de novo</Button>}>
            {view.error instanceof Error ? view.error.message : 'Falha ao montar o acompanhamento.'}
          </Banner>
        ) : 'waiting' in view.data ? (
          <Banner icon={<CalendarClock aria-hidden className="mt-0.5 size-4 shrink-0" />}>
            O primeiro aporte sai no primeiro pregão a partir de {Fmt.date(stored.record.plan.start)}. Volte depois dele.
          </Banner>
        ) : (
          <Summary view={view.data} />
        )}
        {syncError !== null && (
          <Banner tone="negative" className="mt-3">
            As compras novas não foram gravadas: {syncError}. O resultado na tela vale, mas não ficou guardado. Se o erro for de permissão,
            as regras do Firestore desta versão ainda não foram publicadas.
          </Banner>
        )}
      </Panel>
      {view.status === 'success' && !('waiting' in view.data) && (
        <>
          <TrackingChart view={view.data} />
          <Holdings view={view.data} />
          <Orders orders={view.data.outcome.orders} />
        </>
      )}
    </div>
  );
}

function Summary({ view }: { view: TrackingView }) {
  const { outcome } = view;
  const wealth = outcome.finalValueCents / 100;
  const contributed = outcome.totalContributedCents / 100;
  const xirr = outcome.moneyWeightedReturn;
  const gapToRequired = view.requiredNow === null ? null : wealth - view.requiredNow;
  const required = view.required;
  const meets = xirr !== null && required !== null ? xirr >= required : null;
  return (
    <div className="space-y-4">
      <MetricRow className="sm:grid-cols-3">
        <Metric label="Patrimônio" value={Fmt.money(wealth)} hint={`aportado ${Fmt.money(contributed)}`} />
        <Metric
          label="Retorno da carteira"
          value={xirr === null ? '—' : Fmt.percent(xirr, { decimals: 1 })}
          hint="a.a., ponderado pelo dinheiro (XIRR)"
          tone={meets === null ? 'neutral' : meets ? 'positive' : 'negative'}
        />
        <Metric label="Exigido pela meta" value={required === null ? '—' : Fmt.percent(required, { decimals: 1 })} hint="a.a." />
      </MetricRow>
      <div className="space-y-2">
        {gapToRequired !== null && (
          <p className={gapToRequired >= 0 ? 'text-body-sm text-positive' : 'text-body-sm text-negative'}>
            A carteira está{' '}
            <span className="num font-semibold">{Fmt.money(Math.abs(gapToRequired))}</span>
            {gapToRequired >= 0 ? ' acima do caminho que a meta exige até hoje.' : ' abaixo do caminho que a meta exige até hoje.'}
          </p>
        )}
        {view.projectedAtPace !== null && (
          <p className="text-body-sm text-fg-2">
            No ritmo atual, com os {view.remainingMonths} meses de aporte que faltam, a carteira chega a{' '}
            <span className={`num font-semibold ${view.projectedAtPace >= view.record.targetWealth.reais ? 'text-positive' : 'text-negative'}`}>
              {Fmt.money(view.projectedAtPace)}
            </span>{' '}
            em {Fmt.date(view.record.endDate)}, contra a meta de {Fmt.money(view.record.targetWealth.reais)}.
          </p>
        )}
        <p className="text-caption text-fg-3">
          {outcome.orders.length} aporte(s) · proventos {Fmt.money(outcome.totalDividendsCents / 100)} · tarifas{' '}
          {Fmt.money(outcome.totalCostCents / 100)} · caixa {Fmt.money(outcome.cashCents / 100)} · TWR{' '}
          <span className={trendOf(outcome.timeWeightedReturn) === 'negative' ? 'text-negative' : undefined}>
            {Fmt.percent(outcome.timeWeightedReturn, { decimals: 1 })}
          </span>{' '}
          no período
        </p>
        <Banner>
          O potencial do motor ainda não teve a habilidade de ordenar retornos comprovada na validação: este acompanhamento mostra o que a
          regra fez, e não prova que ela funciona.
        </Banner>
        {view.notes.map((n) => (
          <Banner key={n} tone="caution">
            {n}
          </Banner>
        ))}
      </div>
    </div>
  );
}

function Holdings({ view }: { view: TrackingView }) {
  const rows = [...view.outcome.holdings]
    .sort((a, b) => b.valueCents - a.valueCents)
    .map((h) => [
      h.ticker.value,
      String(h.shares),
      Fmt.money(h.valueCents / 100),
      Fmt.percent(h.weight, { decimals: 1 }),
      String(h.purchases),
      Fmt.money(h.dividendsCents / 100),
    ]);
  return (
    <Card className="overflow-x-auto p-4 sm:p-5">
      <h2 className="mb-2 text-title-sm font-semibold text-fg">Posições</h2>
      <DataTable caption="Posições da carteira acompanhada" columns={['Ativo', 'Ações', 'Valor', 'Peso', 'Compras', 'Proventos']} rows={rows} />
    </Card>
  );
}

function Orders({ orders }: { orders: readonly TrackingOrder[] }) {
  const rows = [...orders].reverse().map((o) => [
    Fmt.date(o.executedOn),
    o.ticker?.value ?? '—',
    o.quantity > 0 ? String(o.quantity) : '—',
    o.quantity > 0 ? Fmt.money(o.priceCents / 100) : '—',
    o.upside === null ? '—' : Fmt.percent(o.upside, { decimals: 1, signed: true }),
    o.origin === null ? '—' : o.origin === 'coorte' ? `coorte ${Fmt.date(o.fairValueAsOf!)}` : 'motor',
    Fmt.money(o.cashAfterCents / 100),
  ]);
  return (
    <Disclosure title="Compras" summary={`${orders.length} aporte(s), do mais recente ao primeiro — gravados e imutáveis`}>
      {orders.some((o) => o.origin === 'coorte') && (
        <p className="mb-2 text-caption leading-relaxed text-fg-3">
          “Preço justo de” diz de onde veio o preço justo da compra: do motor no dia, ou de uma coorte. {cohortMeaning}
        </p>
      )}
      <div className="max-h-96 overflow-auto">
        <DataTable
          caption="Compras do acompanhamento"
          columns={['Data', 'Ativo', 'Ações', 'Preço', 'Potencial', 'Preço justo de', 'Caixa depois']}
          rows={rows}
        />
      </div>
    </Disclosure>
  );
}

function RemoveTracking({ id }: { id: string }) {
  const [open, setOpen] = useState(false);
  const busy = useTrackings((s) => s.busy);
  const [error, setError] = useState<string | null>(null);
  return (
    <>
      <Button size="sm" variant="ghost" icon={<Trash2 aria-hidden className="size-4" />} onClick={() => setOpen(true)}>
        Encerrar
      </Button>
      <ConfirmDialog
        open={open}
        onOpenChange={setOpen}
        title="Encerrar o acompanhamento?"
        description="O acompanhamento e todas as compras gravadas dele são apagados, e não há como desfazer. Um novo acompanhamento começa do zero, com a carteira e a meta de agora."
        confirmLabel={busy ? 'Encerrando…' : 'Encerrar e apagar'}
        busy={busy}
        onConfirm={() =>
          void TrackingActions.remove(id).then((r) => {
            if (r.isErr) setError(FailureCopy.of(r.failureOrNull!));
            else setOpen(false);
          })
        }
      >
        {error !== null && <Banner tone="negative">{error}</Banner>}
      </ConfirmDialog>
    </>
  );
}
