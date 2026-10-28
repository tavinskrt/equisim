import { ArrowLeft, RotateCcw, SearchX } from 'lucide-react';
import { useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router';

import { services, useValuation } from '../../app/hooks';
import { SavedValuationsActions, useSavedValuations } from '../../app/state/saved-valuations-store';
import {
  AuditIds,
  type DateTime,
  ManualField,
  type ManualPremises,
  ManualValuationRecord,
  type ManualSolution,
  Ticker,
  type ValuationResult,
} from '../../core';
import { FailureCopy, Fmt, ManualCopy } from '../../copy';
import { Banner } from '../../ui/banner';
import { Button, IconButton } from '../../ui/button';
import { Card } from '../../ui/card';
import { EmptyState, Skeleton } from '../../ui/feedback';
import { TickerLogo } from '../../ui/ticker-logo';
import { toast } from '../../ui/toast';
import { PortaZeroExplainer } from '../study/porta-zero';
import { PremiseFields } from './premise-fields';
import { CalculationCard, type Confirmation, DisagreementCard, ResultBar, ReverseCard, SummaryCard, YearsCard } from './result-cards';

/**
 * **Simular minhas premissas** (decisão 147): o editor do valuation, com os
 * números do motor como ponto de partida, o DCF reverso e a confirmação que
 * guarda o resultado em "Meus valuations" e no painel de logs.
 *
 * `?registro=<id>` reabre um valuation salvo com as premissas dele — se ele foi
 * feito pela mesma via de avaliação que o motor usa hoje.
 */
export function ManualPage() {
  const params = useParams();
  const ticker = params['ticker'] === undefined ? null : Ticker.tryParse(params['ticker']);
  if (ticker === null) {
    return (
      <Card>
        <EmptyState icon={<SearchX aria-hidden className="size-6" />} title="Ativo não reconhecido" message={`"${params['ticker'] ?? ''}" não é um código de negociação da B3.`} />
      </Card>
    );
  }
  return <ManualLoader key={ticker.value} ticker={ticker} />;
}

function ManualLoader({ ticker }: { ticker: Ticker }) {
  const valuation = useValuation(ticker);
  const [search] = useSearchParams();
  const recordId = search.get('registro');
  const saved = useSavedValuations();

  if (valuation.status === 'pending' || (recordId !== null && (saved.status === 'idle' || saved.status === 'loading'))) {
    return <EditorSkeleton ticker={ticker} />;
  }
  if (valuation.status === 'error') {
    return (
      <Card>
        <EmptyState
          title="Falha ao avaliar"
          message={valuation.error instanceof Error ? valuation.error.message : String(valuation.error)}
          action={<Button onClick={valuation.refetch}>Tentar de novo</Button>}
        />
      </Card>
    );
  }
  const outcome = valuation.data;
  if (outcome.isErr) {
    return (
      <div className="space-y-4">
        <Header ticker={ticker} changed={false} onReset={null} />
        <Card className="p-5">
          <EmptyState title="Sem preço justo para editar" message={FailureCopy.of(outcome.failureOrNull!)} />
          <PortaZeroExplainer />
        </Card>
      </div>
    );
  }
  const result = outcome.unwrap();
  if (result.manual === null) {
    return (
      <div className="space-y-4">
        <Header ticker={ticker} changed={false} onReset={null} />
        <Card>
          <EmptyState
            title="Este valuation não abre para edição"
            message="A edição usa a conta do fluxo de caixa descontado; o preço justo deste ativo saiu por outro caminho do motor, e trocar os números dele não teria a mesma leitura."
          />
        </Card>
      </div>
    );
  }

  const record = recordId === null ? null : (saved.records.find((r) => r.id === recordId) ?? null);
  const sameLane = record !== null && record.lane === result.manual.lane;
  const notice =
    recordId === null
      ? null
      : record === null
        ? 'O valuation salvo não foi encontrado — talvez tenha sido apagado. Os campos abrem com os números do motor.'
        : !sameLane
          ? 'A avaliação de hoje mudou de via: os números deste valuation não cabem nos campos dela. Os campos abrem com os números do motor.'
          : `Reaberto o valuation de ${Fmt.dateTime(record.savedAt)}: os campos trazem as premissas dele, e a conta usa os dados de hoje.`;

  return <Editor key={`${ticker.value}:${recordId ?? ''}`} result={result} initial={sameLane ? record.premises : null} notice={notice} />;
}

function EditorSkeleton({ ticker }: { ticker: Ticker }) {
  return (
    <div className="space-y-4" aria-busy>
      <Header ticker={ticker} changed={false} onReset={null} />
      <span className="sr-only" role="status">
        Avaliando {ticker.value}
      </span>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[11fr_9fr]">
        <div className="space-y-4">
          {[0, 1, 2].map((i) => (
            <Card key={i} className="p-5">
              <Skeleton className="h-4 w-48" />
              <Skeleton className="mt-3 h-3 w-full" />
              <Skeleton className="mt-4 h-12 w-full" />
            </Card>
          ))}
        </div>
        <Card className="p-5">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="mt-4 h-9 w-40" />
          <Skeleton className="mt-6 h-14 w-full" />
        </Card>
      </div>
    </div>
  );
}

function Header(props: { ticker: Ticker; changed: boolean; onReset: (() => void) | null }) {
  const navigate = useNavigate();
  const back = () => {
    // Quem veio do Raio-X volta a ele; quem abriu o link direto vai ao Raio-X sobre o estudo.
    const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0;
    if (idx > 0) navigate(-1);
    else navigate(`/estudo?ativo=${props.ticker.value}`);
  };
  return (
    <div className="flex items-center gap-2">
      <IconButton label="Voltar à avaliação" onClick={back}>
        <ArrowLeft aria-hidden className="size-5" />
      </IconButton>
      <div className="min-w-0 flex-1">
        <h1 className="text-balance text-title font-semibold text-fg">Simular minhas premissas</h1>
        <p className="flex items-center gap-1.5 text-body-sm text-fg-2">
          <TickerLogo ticker={props.ticker} size="sm" />
          <span>{props.ticker.value} · seu cálculo</span>
        </p>
      </div>
      {props.onReset !== null && (
        <IconButton label="Voltar aos números do motor" tone={props.changed ? 'brand' : 'default'} disabled={!props.changed} onClick={props.onReset}>
          <RotateCcw aria-hidden className="size-5" />
        </IconButton>
      )}
    </div>
  );
}

function Editor({ result, initial, notice }: { result: ValuationResult; initial: ManualPremises | null; notice: string | null }) {
  const m = result.manual!;
  const [p, setP] = useState<ManualPremises>(() => initial ?? m.enginePremises);
  const [saving, setSaving] = useState(false);
  const [confirmed, setConfirmed] = useState<{ premises: ManualPremises; at: DateTime } | null>(null);
  const [target, setTarget] = useState<ManualField>(ManualField.discountRate);
  const [answer, setAnswer] = useState<ManualSolution | null>(null);

  const swap = (next: ManualPremises) => {
    setP(next);
    setAnswer(null);
  };

  const evaluated = m.evaluate(p);
  const output = evaluated.isOk ? evaluated.unwrap() : null;
  const failure = evaluated.failureOrNull;
  const steps = m.attribution(p);
  const changed = steps.length > 0;

  const confirm = async () => {
    if (saving) return;
    const premises = p;
    const captured = ManualValuationRecord.capture({
      id: AuditIds.uuidV4(),
      ticker: result.ticker,
      engineAsOf: result.asOf,
      valuation: m,
      premises,
      savedAt: services().clock(),
    });
    if (captured.isErr) {
      toast(ManualCopy.refusal(captured.failureOrNull!), 'error');
      return;
    }
    const record = captured.unwrap();
    setSaving(true);
    const saved = await SavedValuationsActions.confirm(record);
    setSaving(false);
    const f = saved.failureOrNull;
    if (f === null) {
      setConfirmed({ premises, at: record.savedAt });
      toast(`Valuation salvo: ${Fmt.money(record.fairValuePerShare)} por ação. Ele aparece em "Meus valuations" e no painel de logs.`, 'success');
    } else {
      toast(f.message, 'error');
    }
  };

  const confirmation: Confirmation = {
    enabled: output !== null && !saving,
    saving,
    // Só vale "Salvo" enquanto as premissas em tela são exatamente as salvas.
    savedAt: confirmed !== null && confirmed.premises === p ? confirmed.at : null,
    onConfirm: () => void confirm(),
  };

  return (
    <div className="space-y-4 pb-24 lg:pb-0">
      <Header ticker={result.ticker} changed={changed} onReset={() => swap(m.enginePremises)} />
      {notice !== null && <Banner>{notice}</Banner>}
      <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-[minmax(0,11fr)_minmax(0,9fr)]">
        <PremiseFields
          m={m}
          p={p}
          failure={failure}
          output={output}
          changed={changed}
          normalization={result.diagnostics?.baseNormalization ?? null}
          onChange={swap}
        />
        {/* No computador a coluna do resultado rola sozinha e fica à vista enquanto se edita à esquerda. */}
        <div className="space-y-4 lg:sticky lg:top-[72px] lg:max-h-[calc(100dvh-88px)] lg:overflow-y-auto lg:pr-1 lg:scrollbar-thin">
          <SummaryCard m={m} output={output} failure={failure} changed={changed} confirmation={confirmation} />
          {output !== null && <CalculationCard m={m} output={output} />}
          <DisagreementCard m={m} steps={steps} />
          <ReverseCard
            m={m}
            p={p}
            target={target}
            answer={answer}
            onTarget={(f) => {
              setTarget(f);
              setAnswer(null);
            }}
            onSolve={(field) => setAnswer(m.solve(field, p))}
            onUse={(f, v) => swap(p.withValue(f, v))}
          />
          {output !== null && <YearsCard m={m} p={p} output={output} />}
          {output?.notices.map((n, i) => (
            <Banner key={i} tone="caution">
              {ManualCopy.warning(n)}
            </Banner>
          ))}
          <p className="text-caption text-fg-3">
            A faixa calibrada e a habilidade medida do Equisim são do preço justo do motor, porque foi ele que as avaliações passadas testaram. O preço desta tela é a
            conta do motor com os seus números: o resultado da sua opinião, sem validação própria.
          </p>
          <p className="text-caption text-fg-3">
            Os confirmados ficam em <Link to="/valuations" className="text-positive underline-offset-2 hover:underline">Meus valuations</Link>.
          </p>
        </div>
      </div>
      <ResultBar m={m} output={output} changed={changed} confirmation={confirmation} />
    </div>
  );
}
