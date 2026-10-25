import { Calculator, Check, CircleCheck, Save } from 'lucide-react';

import {
  type DateTime,
  type Failure,
  ManualField,
  type ManualOutcome,
  type ManualPremises,
  ManualReinvestment,
  type ManualSolution,
  type ManualStep,
  type ManualValuation,
  ValuationLane,
} from '../../core';
import { DomainCopy, Fmt, ManualCopy, trendOf } from '../../copy';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card, Divider, Panel } from '../../ui/card';
import { cn } from '../../ui/cn';
import { Spinner } from '../../ui/feedback';
import { KeyValue, Metric } from '../../ui/metric';
import { toneText } from '../../ui/tone';
import { ProjectionTable } from '../asset/projection-table';
import { Modes, TextAction } from './field-card';
import { Units } from './units';

/** O estado do botão de confirmar, partilhado pelo resumo e pela barra do celular. */
export interface Confirmation {
  readonly enabled: boolean;
  readonly saving: boolean;
  /** Quando as premissas em tela já foram salvas: o botão vira "Salvo". */
  readonly savedAt: DateTime | null;
  readonly onConfirm: () => void;
}

export function ConfirmButton({ confirmation: k, compact = false }: { confirmation: Confirmation; compact?: boolean }) {
  const label = k.saving ? 'Salvando…' : k.savedAt === null ? (compact ? 'Confirmar' : 'Confirmar valuation') : compact ? 'Salvo' : 'Valuation salvo';
  const icon = k.saving ? <Spinner className="size-4 text-on-brand" label="Salvando" /> : k.savedAt === null ? <Save aria-hidden className="size-[18px]" /> : <Check aria-hidden className="size-[18px]" />;
  const button = (
    <Button variant="primary" onClick={k.onConfirm} disabled={!k.enabled || k.savedAt !== null} icon={icon}>
      {label}
    </Button>
  );
  if (compact) return button;
  return (
    <div className="space-y-2">
      {button}
      <p className="text-caption text-fg-2" aria-live="polite">
        {k.savedAt === null
          ? 'Confirmar guarda os seus números e o resultado da conta em "Meus valuations" e registra o cálculo no painel de logs.'
          : `Salvo às ${Fmt.time(k.savedAt)}, com as premissas e o resultado, e registrado no painel de logs. Troque um campo para confirmar outro valuation.`}
      </p>
    </div>
  );
}

/**
 * **Seu preço justo**: a conta do motor com os seus números, contra o preço do
 * motor e o de mercado. A diferença contra o motor só aparece quando há
 * diferença — "+R$ 0,00 contra o motor" seria ruído.
 */
export function SummaryCard(props: { m: ManualValuation; output: ManualOutcome | null; failure: Failure | null; changed: boolean; confirmation: Confirmation }) {
  const { m, output } = props;
  const yours = output?.fairValuePerShare ?? null;
  const delta = yours === null ? null : yours - m.engineFairValue;
  const upside = yours === null ? null : yours / m.marketPrice - 1;
  return (
    <Card className={cn('p-4 sm:p-5', props.changed && 'border-brand')}>
      <h2 className="text-title-sm font-semibold text-fg">Seu preço justo</h2>
      <p className="mt-0.5 text-body-sm text-fg-2">{props.changed ? 'A conta do motor com os seus números' : 'Igual ao do motor: nenhum campo foi trocado'}</p>
      <p className="num mt-4 text-display font-semibold tracking-tight text-fg" aria-live="polite">
        {yours === null ? '—' : Fmt.money(yours)}
      </p>
      {delta !== null && props.changed && (
        <p className={cn('num mt-1 text-body-sm font-medium', toneText[trendOf(delta)])}>
          {delta >= 0 ? '+' : '−'}
          {Fmt.money(Math.abs(delta))} ({Fmt.percent(delta / m.engineFairValue, { decimals: 1, signed: true })}) contra o motor
        </p>
      )}
      <div className="mt-5 grid grid-cols-1 gap-4 min-[420px]:grid-cols-3">
        <Metric size="sm" label="Preço justo do motor" value={Fmt.money(m.engineFairValue)} />
        <Metric size="sm" label="Preço de mercado" value={Fmt.money(m.marketPrice)} />
        <Metric
          size="sm"
          label="Seu potencial"
          value={upside === null ? '—' : Fmt.percent(upside, { decimals: 1, signed: true })}
          hint="total, sem prazo"
          tone={trendOf(upside)}
        />
      </div>
      {props.failure !== null && (
        <Banner tone="negative" className="mt-4">
          {ManualCopy.refusal(props.failure)}
        </Banner>
      )}
      <div className="mt-5">
        <ConfirmButton confirmation={props.confirmation} />
      </div>
    </Card>
  );
}

/**
 * A barra fixa do celular: o preço, o potencial e o confirmar sempre à vista
 * enquanto se edita lá em cima. Fica acima da barra de abas, que no celular
 * também é fixa.
 */
export function ResultBar(props: { m: ManualValuation; output: ManualOutcome | null; changed: boolean; confirmation: Confirmation }) {
  const { m } = props;
  const yours = props.output?.fairValuePerShare ?? null;
  const upside = yours === null ? null : yours / m.marketPrice - 1;
  return (
    <div
      className={cn(
        'fixed inset-x-0 z-20 border-t bg-raised/95 backdrop-blur-md lg:hidden',
        'bottom-[calc(56px+env(safe-area-inset-bottom))] md:bottom-0 md:pb-[env(safe-area-inset-bottom)]',
        props.changed ? 'border-brand' : 'border-line',
      )}
    >
      <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-2">
        <div>
          <p className="text-caption text-fg-2">Seu preço justo</p>
          <p className="num text-title font-semibold text-fg">{yours === null ? '—' : Fmt.money(yours)}</p>
        </div>
        <div className="min-w-0">
          <p className="truncate text-caption text-fg-2">
            Motor {Fmt.money(m.engineFairValue)} · mercado {Fmt.money(m.marketPrice)}
          </p>
          <p className={cn('num text-body-sm font-semibold', toneText[trendOf(upside)])}>
            {upside === null ? '—' : `${Fmt.percent(upside, { decimals: 1, signed: true })} de potencial`}
          </p>
        </div>
        <ConfirmButton confirmation={props.confirmation} compact />
      </div>
    </div>
  );
}

/** **A conta**: do valor presente dos dez anos e da perpetuidade até o preço por ação, e de onde vem o valor. */
export function CalculationCard({ m, output: s }: { m: ManualValuation; output: ManualOutcome }) {
  const explicit = s.explicitPresentValue;
  const perpetual = s.terminalPresentValue;
  const total = Math.abs(explicit) + Math.abs(perpetual);
  const explicitWeight = total > 0 ? Math.abs(explicit) / total : 0.5;
  return (
    <Panel
      title="A conta"
      subtitle={
        m.lane === ValuationLane.firm
          ? 'O valor presente do que sobra ao acionista depois da dívida, dividido pelas ações'
          : 'O valor presente do que sobra ao acionista depois de reinvestir, dividido pelas ações'
      }
    >
      <KeyValue label="Valor presente dos 10 anos" value={Fmt.millions(explicit)} />
      <KeyValue label="Valor presente da perpetuidade" value={Fmt.millions(perpetual)} />
      {s.minorityInterest > 0 && <KeyValue label="− Parte dos acionistas minoritários das controladas" value={Fmt.millions(-s.minorityInterest)} />}
      {s.postStatementCapital > 0 && <KeyValue label="+ Ações emitidas depois do balanço" value={Fmt.millions(s.postStatementCapital)} />}
      <Divider className="my-2" />
      <KeyValue label="Valor do patrimônio (VPL)" value={Fmt.millions(s.equityValue)} />
      <KeyValue label="÷ Ações" value={`${Fmt.ratio(m.shares / 1e6, 1)} mi`} />
      <KeyValue label="= Seu preço justo por ação" value={Fmt.money(s.fairValuePerShare)} tone="positive" />
      <p className="mt-4 text-caption text-fg-2">De onde vem o valor</p>
      <div className="mt-1.5 flex h-3 gap-0.5 overflow-hidden rounded-md" aria-hidden>
        <div className="bg-brand" style={{ flexGrow: Math.max(1, Math.round(explicitWeight * 1000)) }} />
        <div className="bg-line-strong" style={{ flexGrow: Math.max(1, Math.round((1 - explicitWeight) * 1000)) }} />
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-caption text-fg-2">
        <li className="inline-flex items-center gap-1.5">
          <span aria-hidden className="size-2.5 rounded-sm bg-brand" />
          10 anos: {Fmt.percent(explicitWeight, { decimals: 0 })}
        </li>
        <li className="inline-flex items-center gap-1.5">
          <span aria-hidden className="size-2.5 rounded-sm bg-line-strong" />
          Perpetuidade: {Fmt.percent(1 - explicitWeight, { decimals: 0 })} — {DomainCopy.terminal(s.terminalKind)}
        </li>
      </ul>
    </Panel>
  );
}

/**
 * **Onde você discorda do motor**: quanto cada troca move o preço, na ordem em
 * que a conta as usa. Barras flutuantes numa escala só, do preço do motor ao
 * seu; o sinal e o valor em texto acompanham a cor.
 */
export function DisagreementCard({ m, steps }: { m: ManualValuation; steps: readonly ManualStep[] }) {
  const values = [m.engineFairValue, ...steps.flatMap((d) => (d.to === null ? [d.from] : [d.from, d.to]))].filter(Number.isFinite);
  const lo = Math.min(0, ...values);
  const hi = Math.max(lo + 1e-9, ...values) * 1.05;
  const pos = (v: number) => Math.min(1, Math.max(0, (v - lo) / (hi - lo))) * 100;
  const last = steps.length === 0 ? null : steps[steps.length - 1]!.to;
  return (
    <Panel title="Onde você discorda do motor" subtitle="Quanto cada troca move o preço, na ordem em que a conta as usa">
      <dl className="space-y-3">
        <StepRow label="Preço justo do motor" value={Fmt.money(m.engineFairValue)} from={pos(lo)} to={pos(m.engineFairValue)} fill="var(--border-strong)" />
        {steps.length === 0 && <p className="text-body-sm text-fg-2">Troque um campo para ver quanto cada discordância move o preço.</p>}
        {steps.map((d, i) => {
          const label = d.groups.map((g) => DomainCopy.group(g)).join(' e ');
          if (d.to === null || d.delta === null) {
            return <StepRow key={i} label={label} value="sem valor finito" valueClass="text-blocked" from={pos(d.from)} to={pos(d.from)} fill="var(--negative)" />;
          }
          return (
            <StepRow
              key={i}
              label={label}
              value={`${d.delta >= 0 ? '+' : '−'}${Fmt.money(Math.abs(d.delta))}`}
              valueClass={toneText[trendOf(d.delta)]}
              from={pos(d.from)}
              to={pos(d.to)}
              fill={d.delta >= 0 ? 'var(--positive)' : 'var(--negative)'}
            />
          );
        })}
        {last !== null && (
          <>
            <Divider />
            <StepRow label="Seu preço justo" value={Fmt.money(last)} from={pos(lo)} to={pos(last)} fill="var(--brand)" strong />
          </>
        )}
      </dl>
    </Panel>
  );
}

function StepRow(props: { label: string; value: string; valueClass?: string; from: number; to: number; fill: string; strong?: boolean }) {
  const left = Math.min(props.from, props.to);
  const width = Math.abs(props.to - props.from);
  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <dt className={cn('text-body-sm', props.strong ? 'font-semibold text-fg' : 'text-fg-2')}>{props.label}</dt>
        <dd className={cn('num shrink-0 text-body-sm font-semibold', props.valueClass ?? 'text-fg')}>{props.value}</dd>
      </div>
      <div className="relative mt-1.5 h-2.5 rounded bg-sunken" aria-hidden>
        <div className="absolute inset-y-0 rounded-sm" style={{ left: `${left}%`, width: `max(2px, ${width}%)`, background: props.fill }} />
      </div>
    </div>
  );
}

/**
 * **O que o preço de hoje supõe?** O DCF reverso: o valor de um campo que faz
 * o preço justo bater com o de mercado, com os outros campos como estão. Quando
 * nenhum valor fecha a conta, diz o mais perto que se chega — e não inventa.
 */
export function ReverseCard(props: {
  m: ManualValuation;
  p: ManualPremises;
  target: ManualField;
  answer: ManualSolution | null;
  onTarget: (f: ManualField) => void;
  onSolve: (field: ManualField) => void;
  onUse: (f: ManualField, v: number) => void;
}) {
  const { m, p, answer: r } = props;
  const options: ManualField[] = [
    ManualField.discountRate,
    ManualField.growth,
    ManualField.baseProfit,
    p.reinvestment === ManualReinvestment.byReturn ? ManualField.returnOnCapital : ManualField.retention,
    ...(p.terminalReturn !== null ? [ManualField.terminalReturn] : []),
  ];
  const chosen = options.includes(props.target) ? props.target : options[0]!;
  const name = ManualCopy.label(chosen, m.lane).toLowerCase();
  const u = Units.of(chosen);
  let sentence: string | null = null;
  if (r !== null && r.field === chosen) {
    if (r.value !== null) {
      sentence = `Para valer ${Fmt.money(r.target)}, com os outros campos como estão, ${name} teria de ser ${Units.reference(u, r.value)}. Hoje está em ${Units.reference(u, p.valueOf(chosen) ?? Number.NaN)}.`;
    } else if (r.closestValue !== null && r.closestPrice !== null) {
      sentence = `Com os outros campos como estão, nenhum valor de ${name} leva o preço justo a ${Fmt.money(r.target)}: o mais perto é ${Fmt.money(r.closestPrice)}, com ${Units.reference(u, r.closestValue)}.`;
    } else {
      sentence = `Com os outros campos como estão, a conta não fecha para nenhum valor de ${name}.`;
    }
  }
  return (
    <Panel title="O que o preço de hoje supõe?" subtitle={`O valor de um campo que faz o preço justo bater com o de mercado (${Fmt.money(m.marketPrice)})`}>
      <Modes
        label="Campo a resolver"
        value={chosen.name}
        options={options.map((f) => ({ value: f.name, label: ManualCopy.label(f, m.lane) }))}
        onChange={(v) => props.onTarget(ManualField.values.find((f) => f.name === v)!)}
      />
      <Button variant="primary" className="mt-4" onClick={() => props.onSolve(chosen)} icon={<Calculator aria-hidden className="size-[18px]" />}>
        Calcular
      </Button>
      {sentence !== null && (
        <div className="mt-4" aria-live="polite">
          <p className="text-body-sm text-fg">{sentence}</p>
          {r?.value != null && (
            <TextAction icon={<CircleCheck aria-hidden className="size-4" />} onClick={() => props.onUse(chosen, r.value!)}>
              Usar este valor
            </TextAction>
          )}
        </div>
      )}
    </Panel>
  );
}

/** **Ano a ano**: a mesma tabela do Raio-X, agora com os seus números. */
export function YearsCard({ m, p, output }: { m: ManualValuation; p: ManualPremises; output: ManualOutcome }) {
  return (
    <Panel title="Ano a ano" subtitle="Em milhões de reais. O fluxo de cada ano chega no meio dele, como no motor: valor presente = fluxo ÷ fator">
      <ProjectionTable m={m} p={p} output={output} />
    </Panel>
  );
}
