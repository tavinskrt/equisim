import { Minus, PencilLine, Plus, Undo2 } from 'lucide-react';
import { Slider as S, ToggleGroup } from 'radix-ui';
import { type ReactNode, useEffect, useId, useRef, useState } from 'react';

import type { ManualField } from '../../core';
import { Badge } from '../../ui/badge';
import { Card } from '../../ui/card';
import { cn } from '../../ui/cn';
import { type Unit, Units } from './units';

/** Ação em texto, na cor de marca: "Usar o do motor", "Usar este valor". */
export function TextAction(props: { children: ReactNode; icon?: ReactNode; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={props.onClick}
      className="inline-flex min-h-11 items-center gap-1.5 rounded-md px-1 text-body-sm font-medium text-positive hover:underline"
    >
      {props.icon}
      {props.children}
    </button>
  );
}

/**
 * Escolha entre modos de um campo ("cai até a perpetuidade" × "constante").
 * Fichas que quebram linha — os rótulos são frases, e um controle segmentado
 * de uma linha só estouraria a 320 px.
 */
export function Modes<T extends string>(props: { label: string; value: T; options: readonly { value: T; label: string }[]; onChange: (v: T) => void }) {
  return (
    <ToggleGroup.Root
      type="single"
      aria-label={props.label}
      value={props.value}
      onValueChange={(v) => v !== '' && props.onChange(v as T)}
      className="flex flex-wrap gap-2"
    >
      {props.options.map((o) => (
        <ToggleGroup.Item
          key={o.value}
          value={o.value}
          className="min-h-11 rounded-full border border-line bg-sunken px-3.5 text-body-sm text-fg-2 transition-colors hover:border-line-strong hover:text-fg data-[state=on]:border-brand data-[state=on]:bg-brand data-[state=on]:font-medium data-[state=on]:text-on-brand"
        >
          {o.label}
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}

/**
 * O cartão de um campo: nome, explicação, o selo "Seu número" quando ele
 * difere do motor, e o retorno ao número do motor. A borda diz o estado — de
 * marca quando o número é seu, negativa quando a conta o recusa —, e o selo e
 * a mensagem dizem o mesmo em texto.
 */
export function FieldCard(props: {
  label: string;
  explanation: string;
  changed: boolean;
  error: string | null;
  onBackToEngine: (() => void) | null;
  children: ReactNode;
  labelId?: string;
}) {
  return (
    <Card className={cn('p-4 sm:p-5', props.error !== null ? 'border-negative' : props.changed ? 'border-brand' : undefined)}>
      <div className="flex items-start gap-2">
        <h3 id={props.labelId} className="flex-1 text-title-sm font-semibold text-fg">
          {props.label}
        </h3>
        {props.changed && <Badge tone="brand">Seu número</Badge>}
      </div>
      <p className="mt-1 text-caption leading-relaxed text-fg-2">{props.explanation}</p>
      <div className="mt-4 space-y-3">{props.children}</div>
      {props.changed && props.onBackToEngine !== null && (
        <div className="mt-1">
          <TextAction icon={<Undo2 aria-hidden className="size-4" />} onClick={props.onBackToEngine}>
            Usar o do motor
          </TextAction>
        </div>
      )}
      {props.error !== null && (
        <p role="alert" className="mt-2 text-body-sm text-negative">
          {props.error}
        </p>
      )}
    </Card>
  );
}

/**
 * Um campo numérico do editor: menos, texto, mais, e o controle deslizante.
 *
 * **O texto digitado manda enquanto o campo tem foco**: reformatar a cada
 * tecla engoliria a vírgula de "12," antes de o "5" chegar. Ao sair do campo,
 * ele volta a mostrar o valor em vigor. Quando o valor muda por fora — o
 * deslizante, o "usar o do motor", a resposta do solver —, o texto acompanha.
 */
export function NumericField(props: {
  field: ManualField;
  label: string;
  explanation: string;
  reference: string;
  note?: string | null;
  value: number;
  /** `NaN` quando o motor não tem esse número (o retorno do capital novo neutro). */
  engineValue: number;
  unit: Unit;
  step: number;
  grid: number;
  minimum: number;
  maximum: number;
  error: string | null;
  onChange: (v: number) => void;
  onBackToEngine?: () => void;
  modes?: ReactNode;
  extras?: ReactNode;
  detail?: ReactNode;
  forcedChanged?: boolean;
}) {
  const u = props.unit;
  const labelId = useId();
  const inputId = useId();
  const [text, setText] = useState(() => Units.display(u, props.value));
  const [focused, setFocused] = useState(false);
  const [unreadable, setUnreadable] = useState(false);
  const last = useRef(props.value);

  useEffect(() => {
    if (focused) return;
    const parsed = Units.read(u, text);
    if (parsed === null || Math.abs(parsed - props.value) > Units.tolerance(u) / 10) setText(Units.display(u, props.value));
    last.current = props.value;
    // `text` fica de fora das dependências de propósito: a sincronização vai
    // do valor para o texto, nunca o contrário.
  }, [props.value, focused, u]);

  const onGrid = (v: number) => (props.grid > 0 ? Math.round(v / props.grid) * props.grid : v);
  const set = (v: number) => {
    setText(Units.display(u, v));
    setUnreadable(false);
    props.onChange(v);
  };
  const stepBy = (direction: number) => set(onGrid(props.value + direction * props.step));

  const engineFinite = Number.isFinite(props.engineValue);
  const changed = props.forcedChanged === true || !engineFinite || Math.abs(props.value - props.engineValue) > Units.tolerance(u);
  // O trilho cobre o valor atual e o do motor, mesmo fora da faixa sugerida:
  // um número digitado fora dela não pode fazer o controle mentir.
  const lo = Math.min(props.minimum, props.value, ...(engineFinite ? [props.engineValue] : []));
  let hi = Math.max(props.maximum, props.value, ...(engineFinite ? [props.engineValue] : []));
  if (hi <= lo) hi = lo + (props.step > 0 ? props.step * 10 : 1);
  const lowerName = props.label.toLowerCase();
  const backToEngine = props.onBackToEngine ?? (engineFinite ? () => set(props.engineValue) : undefined);

  return (
    <FieldCard
      label={props.label}
      labelId={labelId}
      explanation={props.explanation}
      changed={changed}
      error={props.error ?? (unreadable ? 'Escreva um número, como 12,5.' : null)}
      onBackToEngine={backToEngine ?? null}
    >
      {props.modes}
      <div className="flex items-center gap-2">
        <StepButton label={`Diminuir ${lowerName}`} onClick={() => stepBy(-1)}>
          <Minus aria-hidden className="size-5" />
        </StepButton>
        <div
          className={cn(
            'flex min-h-12 flex-1 items-center gap-1.5 rounded-xl border bg-sunken px-3 transition-colors focus-within:border-2',
            props.error !== null || unreadable ? 'border-negative' : 'border-line focus-within:border-brand',
          )}
        >
          <PencilLine aria-hidden className="size-4 shrink-0 text-fg-3" />
          {u === 'reais' && <span className="text-body-sm text-fg-2">R$</span>}
          <input
            id={inputId}
            aria-labelledby={labelId}
            aria-invalid={props.error !== null || unreadable ? true : undefined}
            inputMode="decimal"
            autoComplete="off"
            value={text}
            onFocus={() => setFocused(true)}
            onBlur={() => {
              setFocused(false);
              setUnreadable(false);
              setText(Units.display(u, last.current));
            }}
            onChange={(e) => {
              const raw = e.target.value.replace(/[^0-9,.\-−]/g, '');
              setText(raw);
              const v = Units.read(u, raw);
              setUnreadable(v === null);
              if (v !== null) {
                last.current = v;
                props.onChange(v);
              }
            }}
            className="num w-full min-w-0 bg-transparent text-center text-num-lg font-semibold text-fg outline-none"
          />
          <span className="shrink-0 text-body-sm text-fg-2">{Units.suffix(u)}</span>
        </div>
        <StepButton label={`Aumentar ${lowerName}`} onClick={() => stepBy(1)}>
          <Plus aria-hidden className="size-5" />
        </StepButton>
      </div>
      <S.Root
        aria-labelledby={labelId}
        value={[Math.min(hi, Math.max(lo, props.value))]}
        min={lo}
        max={hi}
        step={props.grid > 0 ? props.grid : (hi - lo) / 200}
        onValueChange={(v) => v[0] !== undefined && set(onGrid(v[0]))}
        className="relative flex h-11 w-full touch-none select-none items-center"
      >
        <S.Track className="relative h-1.5 grow overflow-hidden rounded-full bg-line">
          <S.Range className="absolute h-full rounded-full bg-brand" />
        </S.Track>
        {engineFinite && (
          <span
            aria-hidden
            title={`Motor: ${Units.reference(u, props.engineValue)}`}
            className="pointer-events-none absolute top-1/2 h-3.5 w-0.5 -translate-y-1/2 rounded bg-fg-3"
            style={{ left: `${((props.engineValue - lo) / (hi - lo)) * 100}%` }}
          />
        )}
        <S.Thumb
          aria-valuetext={Units.reference(u, props.value)}
          className="block size-5 rounded-full border-2 border-brand bg-raised shadow-card transition-transform hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
        />
      </S.Root>
      <p className="text-caption text-fg-2">{props.reference}</p>
      {props.note != null && <p className="text-caption text-fg-3">{props.note}</p>}
      {props.extras}
      {props.detail}
    </FieldCard>
  );
}

function StepButton(props: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={props.label}
      title={props.label}
      onClick={props.onClick}
      className="inline-flex size-12 shrink-0 items-center justify-center rounded-xl border border-line bg-sunken text-fg transition-colors hover:border-line-strong active:bg-raised"
    >
      {props.children}
    </button>
  );
}
