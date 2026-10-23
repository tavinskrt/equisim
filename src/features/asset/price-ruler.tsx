import { Fmt } from '../../copy';
import { cn } from '../../ui/cn';

export interface RulerMark {
  readonly key: string;
  /** Rótulo curto, desenhado sobre a régua. */
  readonly short: string;
  /** Rótulo da legenda. */
  readonly label: string;
  readonly value: number;
  /** Cor da marca: um token de série, nunca cor de estado. */
  readonly color: string;
  readonly note?: string;
}

export interface RulerBand {
  readonly key: string;
  /** Rótulo curto, escrito ao lado da faixa: é ele que distingue uma faixa da outra. */
  readonly short: string;
  readonly label: string;
  readonly low: number;
  readonly high: number;
  readonly note?: string;
}

/**
 * **A régua de preço**: mercado, preço justo, margem de segurança, mediana dos
 * pares, o valuation do usuário e as faixas calibradas na mesma escala. É o
 * gráfico que responde "onde o preço de hoje está" sem exigir que se leia
 * número por número — e a legenda abaixo dela é também a tabela dos valores.
 */
export function PriceRuler({ marks, bands, className }: { marks: readonly RulerMark[]; bands: readonly RulerBand[]; className?: string }) {
  const values = [...marks.map((m) => m.value), ...bands.flatMap((b) => [b.low, b.high])].filter(
    (v) => Number.isFinite(v) && v > 0,
  );
  if (values.length === 0) return null;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const pad = Math.max((max - min) * 0.08, max * 0.02);
  const lo = Math.max(0, min - pad);
  const hi = max + pad;
  const pos = (v: number) => ((v - lo) / (hi - lo)) * 100;

  // Duas linhas de rótulo: a marca vai para a de baixo quando encostaria na
  // anterior. Em 320 px, sete rótulos numa linha só se atropelariam.
  const sorted = [...marks].filter((m) => Number.isFinite(m.value) && m.value > 0).sort((a, b) => a.value - b.value);
  const rows = new Map<string, number>();
  const lastAt = [-Infinity, -Infinity];
  for (const m of sorted) {
    const p = pos(m.value);
    const row = p - lastAt[0]! >= 16 ? 0 : p - lastAt[1]! >= 16 ? 1 : 0;
    rows.set(m.key, row);
    lastAt[row] = p;
  }

  return (
    <figure className={cn('w-full', className)}>
      <div className="relative" aria-hidden>
        {/* Rótulos acima da régua. */}
        <div className="relative h-11">
          {sorted.map((m) => (
            <span
              key={m.key}
              className="absolute whitespace-nowrap text-caption font-semibold text-fg-2"
              style={{
                left: `${pos(m.value)}%`,
                top: rows.get(m.key) === 1 ? 22 : 2,
                transform: `translateX(${pos(m.value) > 85 ? '-100%' : pos(m.value) < 15 ? '0' : '-50%'})`,
              }}
            >
              {m.short}
            </span>
          ))}
        </div>
        {/* Faixas calibradas, cada uma com o horizonte escrito ao lado: duas
            faixas da mesma cor só se distinguiriam pelo comprimento. */}
        <div className="space-y-1.5">
          {bands.map((b, i) => {
            const end = pos(b.high);
            const labelLeft = end <= 88;
            return (
              <div key={b.key} className="relative h-3.5">
                <div className="absolute inset-x-0 top-1/2 h-2.5 -translate-y-1/2 rounded-full bg-sunken" />
                <div
                  className="absolute top-1/2 h-2.5 -translate-y-1/2 rounded-full"
                  style={{ left: `${pos(b.low)}%`, width: `${Math.max(end - pos(b.low), 1)}%`, background: bandFill(i) }}
                />
                <span
                  className="num absolute top-1/2 -translate-y-1/2 whitespace-nowrap text-[11px] font-semibold leading-none text-fg-2"
                  style={labelLeft ? { left: `calc(${end}% + 6px)` } : { right: `calc(${100 - pos(b.low)}% + 6px)` }}
                >
                  {b.short}
                </span>
              </div>
            );
          })}
        </div>
        {/* A régua e as marcas. */}
        <div className="relative mt-2 h-6">
          <div className="absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-line-strong" />
          {sorted.map((m) => (
            <span
              key={m.key}
              className="absolute top-1/2 size-3 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2 ring-surface"
              style={{ left: `${pos(m.value)}%`, background: m.color }}
            />
          ))}
        </div>
        <div className="mt-1 flex justify-between text-caption text-fg-3">
          <span className="num">{Fmt.money(lo)}</span>
          <span className="num">{Fmt.money(hi)}</span>
        </div>
      </div>
      <figcaption className="mt-3">
        <span className="sr-only">Régua de preço: </span>
        <dl className="grid gap-x-6 gap-y-1.5 sm:grid-cols-2">
          {sorted.map((m) => (
            <div key={m.key} className="flex items-baseline gap-2">
              <span aria-hidden className="mt-1 size-2.5 shrink-0 self-start rounded-full" style={{ background: m.color }} />
              <dt className="min-w-0 flex-1 text-body-sm text-fg-2">
                {m.label}
                {m.note !== undefined && <span className="block text-caption text-fg-3">{m.note}</span>}
              </dt>
              <dd className="num text-body-sm font-semibold text-fg">{Fmt.money(m.value)}</dd>
            </div>
          ))}
          {bands.map((b, i) => (
            <div key={b.key} className="flex items-baseline gap-2">
              <span aria-hidden className="mt-1 h-2.5 w-4 shrink-0 self-start rounded-full" style={{ background: bandFill(i) }} />
              <dt className="min-w-0 flex-1 text-body-sm text-fg-2">
                {b.label}
                {b.note !== undefined && <span className="block text-caption text-fg-3">{b.note}</span>}
              </dt>
              <dd className="num text-body-sm font-semibold text-fg">
                {Fmt.money(b.low)} a {Fmt.money(b.high)}
              </dd>
            </div>
          ))}
        </dl>
      </figcaption>
    </figure>
  );
}

/** A faixa mais curta mais forte; a mais longa, que a contém, mais clara. */
const bandFill = (i: number) => `color-mix(in oklab, var(--chart-2) ${i === 0 ? 60 : 32}%, transparent)`;
