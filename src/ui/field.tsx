import { forwardRef, type InputHTMLAttributes, type ReactNode, useEffect, useId, useState } from 'react';

import { cn } from './cn';

const inputClass =
  'block min-h-11 w-full rounded-lg border border-line bg-sunken px-3 text-body text-fg placeholder:text-fg-3 transition-colors hover:border-line-strong focus:border-brand focus:outline-none focus-visible:outline-none aria-[invalid=true]:border-negative';

export interface TextFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> {
  label: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  /** Elemento à direita, dentro do campo (ex.: mostrar senha). */
  trailing?: ReactNode;
  leading?: ReactNode;
}

/** Campo de texto com rótulo visível, dica e erro ligados por ARIA. */
export const TextField = forwardRef<HTMLInputElement, TextFieldProps>(function TextField(
  { label, hint, error, trailing, leading, className, id: idProp, ...rest },
  ref,
) {
  const auto = useId();
  const id = idProp ?? auto;
  const describedBy = [hint !== undefined ? `${id}-h` : null, error ? `${id}-e` : null].filter(Boolean).join(' ');
  return (
    <div className={cn('space-y-1.5', className)}>
      <label htmlFor={id} className="block text-body-sm font-medium text-fg-2">
        {label}
      </label>
      <div className="relative">
        {leading !== undefined && (
          <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center text-fg-3">{leading}</span>
        )}
        <input
          ref={ref}
          id={id}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy || undefined}
          className={cn(inputClass, leading !== undefined && 'pl-9', trailing !== undefined && 'pr-12')}
          {...rest}
        />
        {trailing !== undefined && <span className="absolute inset-y-0 right-0 flex items-center">{trailing}</span>}
      </div>
      {hint !== undefined && !error && (
        <p id={`${id}-h`} className="text-caption text-fg-3">
          {hint}
        </p>
      )}
      {error && (
        <p id={`${id}-e`} role="alert" className="text-caption font-medium text-negative">
          {error}
        </p>
      )}
    </div>
  );
});

/**
 * Lê número escrito em pt-BR: "1.234,56", "1234,56", "12%" e "-3,5".
 * `null` quando não é número. O ponto é separador de milhar **só** quando há
 * vírgula ou quando ele separa grupos de três — "1.5" continua 1,5.
 */
export function parsePtNumber(raw: string): number | null {
  let s = raw.trim().replace(/[R$\s%]/g, '').replace('−', '-');
  if (s === '' || s === '-' || s === ',') return null;
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
  else if (/^-?\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/** Formata para edição: vírgula decimal, sem separador de milhar, sem zeros sobrando. */
export function editableNumber(value: number, decimals: number): string {
  if (!Number.isFinite(value)) return '';
  const fixed = value.toFixed(decimals);
  const trimmed = decimals > 0 ? fixed.replace(/\.?0+$/, '') : fixed;
  return trimmed.replace('.', ',');
}

/**
 * Campo numérico: aceita o que a pessoa digita em pt-BR e só publica o valor
 * quando ele é número. O texto digitado é preservado enquanto o foco está no
 * campo — reformatar a cada tecla roubaria a vírgula que acabou de entrar.
 */
export function NumberField(props: {
  label: ReactNode;
  value: number | null;
  onChange: (value: number | null) => void;
  /** Casas na exibição em edição. */
  decimals?: number;
  /** Sufixo visível: "%", "R$", "anos". */
  suffix?: string;
  prefix?: string;
  hint?: ReactNode;
  error?: string | null;
  placeholder?: string;
  className?: string;
  min?: number;
  max?: number;
  inputMode?: 'decimal' | 'numeric';
  disabled?: boolean;
  id?: string;
}) {
  const decimals = props.decimals ?? 2;
  const [text, setText] = useState(props.value === null ? '' : editableNumber(props.value, decimals));
  const [focused, setFocused] = useState(false);

  useEffect(() => {
    if (!focused) setText(props.value === null ? '' : editableNumber(props.value, decimals));
  }, [props.value, decimals, focused]);

  return (
    <TextField
      id={props.id}
      label={props.label}
      hint={props.hint}
      error={props.error}
      placeholder={props.placeholder}
      className={props.className}
      inputMode={props.inputMode ?? 'decimal'}
      autoComplete="off"
      disabled={props.disabled}
      value={text}
      leading={props.prefix !== undefined ? <span className="text-body-sm">{props.prefix}</span> : undefined}
      trailing={props.suffix !== undefined ? <span className="pr-3 text-body-sm text-fg-3">{props.suffix}</span> : undefined}
      onFocus={() => setFocused(true)}
      onBlur={() => {
        setFocused(false);
        setText(props.value === null ? '' : editableNumber(props.value, decimals));
      }}
      onChange={(e) => {
        setText(e.target.value);
        props.onChange(parsePtNumber(e.target.value));
      }}
    />
  );
}
