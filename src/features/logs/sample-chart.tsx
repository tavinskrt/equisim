import { type RefObject, useLayoutEffect, useRef, useState } from 'react';

import type { TraceSample, TraceSamplePoint } from '../../core';
import { compactAuditNumber, formatAuditNumber } from './format';

/** Largura do elemento, acompanhando o redimensionamento. */
function useWidth<T extends HTMLElement>(): [RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const el = ref.current;
    if (el === null) return;
    setWidth(el.clientWidth);
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver((entries) => setWidth(entries[0]?.contentRect.width ?? 0));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, width];
}

const PLOT = 168;
const LABEL_STRIP = 18;
const CLIP_INSET = 16;

/**
 * A escala do gráfico. Com banda de aceitação, o eixo para um pouco além dela:
 * um exercício extremo (o lucro de 2020 de uma aérea) achataria todos os outros
 * — e ele aparece cortado, com o valor escrito, em vez de esmagar o resto.
 */
function scaleOf(sample: TraceSample): [number, number] {
  const values = sample.points.map((p) => p.value);
  const low = sample.lowerBound;
  const high = sample.upperBound;
  let bottom = Math.min(0, ...values);
  let top = Math.max(...values);
  if (low !== null && high !== null) {
    const margin = (high - low) * 0.55;
    const upperLimit = high + margin;
    const lowerLimit = Math.min(0, low - margin);
    const within = values.filter((v) => v <= upperLimit);
    top = Math.min(top, Math.max(upperLimit, within.length === 0 ? upperLimit : Math.max(...within)));
    const above = values.filter((v) => v >= lowerLimit);
    bottom = Math.max(bottom, Math.min(lowerLimit, above.length === 0 ? lowerLimit : Math.min(...above)));
  }
  if (sample.selected !== null) {
    top = Math.max(top, sample.selected);
    bottom = Math.min(bottom, Math.min(0, sample.selected));
  }
  if (top - bottom < 1e-12) {
    const unit = Math.abs(top) < 1e-12 ? 1 : Math.abs(top) * 0.1;
    top += unit;
    bottom -= unit;
  }
  const span = top - bottom;
  return [bottom - span * 0.06, top + span * 0.14];
}

/**
 * A amostra de um cálculo — os exercícios da janela de normalização, por
 * exemplo — em barras, com a banda de aceitação, o resumo (a mediana) e o
 * exercício observado. Quando o observado foi trazido para a banda, uma seta
 * mostra de onde para onde.
 */
export function SampleChart({ sample }: { sample: TraceSample }) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const observed = sample.points.find((p) => p.isObserved);
  const normalized = observed !== undefined && sample.selected !== null && Math.abs(observed.value - sample.selected) > 1e-9;

  return (
    <div>
      <p className="eyebrow">{sample.title === '' ? 'Amostra' : sample.title}</p>
      <div className="mt-2 rounded-md border border-line px-2.5 pb-2 pt-3.5">
        <div ref={ref} style={{ height: PLOT }}>
          {width > 0 && <Plot sample={sample} width={width} />}
        </div>
        <ul className="mt-3 flex flex-wrap gap-x-3.5 gap-y-1.5 font-mono text-caption text-fg-3">
          <LegendItem color="var(--brand)" label="exercício central da amostra" />
          <LegendItem color="var(--fg-3)" label="demais exercícios da janela" />
          <LegendItem color={normalized ? 'var(--negative)' : 'var(--reserve)'} label={normalized ? 'observado, destoa do ciclo' : 'observado, em linha com o ciclo'} />
          {sample.lowerBound !== null && <LegendItem color="color-mix(in srgb, var(--brand) 22%, transparent)" label="banda de aceitação" />}
        </ul>
      </div>
      <table className="mt-2 w-full overflow-hidden rounded-md border border-line font-mono text-label">
        <caption className="sr-only">{sample.title === '' ? 'Amostra' : sample.title}, valor a valor</caption>
        <tbody>
          {sample.points.map((p, i) => (
            <tr key={i} className="border-b border-line last:border-0">
              <th scope="row" className="w-16 px-2.5 py-1.5 text-left font-normal text-json-key">
                {p.label}
              </th>
              <td className={p.definesResult ? 'px-2 py-1.5 font-bold text-positive' : 'px-2 py-1.5 text-fg'}>{formatAuditNumber(p.value)}</td>
              <td className="px-2.5 py-1.5 text-right text-caption text-fg-3">{tagOf(p, sample, normalized)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function tagOf(p: TraceSamplePoint, sample: TraceSample, normalized: boolean): string {
  return [p.definesResult ? `define a ${sample.summaryLabel}` : null, p.isObserved ? (normalized ? 'observado · normalizado' : 'observado') : null]
    .filter((x) => x !== null)
    .join(' · ');
}

function LegendItem({ color, label }: { color: string; label: string }) {
  return (
    <li className="inline-flex items-center gap-1.5">
      <span aria-hidden className="size-2.5 rounded-sm" style={{ background: color }} />
      {label}
    </li>
  );
}

function Plot({ sample, width }: { sample: TraceSample; width: number }) {
  const points = sample.points;
  if (points.length === 0) return null;
  const plotHeight = PLOT - LABEL_STRIP;
  const [bottom, top] = scaleOf(sample);
  const y = (v: number) => plotHeight - ((v - bottom) / (top - bottom)) * plotHeight;
  const slot = width / points.length;
  const barWidth = Math.min(34, slot * 0.52);
  const zero = Math.min(plotHeight, Math.max(0, y(0)));
  const low = sample.lowerBound;
  const high = sample.upperBound;
  const label = { fontSize: 10, fontFamily: 'var(--font-mono)' } as const;

  return (
    <svg width={width} height={PLOT} role="img" aria-label={`${sample.title || 'Amostra'}: ${points.length} valores; a tabela abaixo traz cada um.`}>
      {low !== null && high !== null && (
        <g>
          <rect x={0} y={y(high)} width={width} height={Math.max(0, y(low) - y(high))} fill="color-mix(in srgb, var(--brand) 12%, transparent)" />
          {[low, high].map((edge) => (
            <line key={edge} x1={0} x2={width} y1={y(edge)} y2={y(edge)} stroke="color-mix(in srgb, var(--brand) 45%, transparent)" strokeDasharray="4 4" />
          ))}
          <text x={2} y={y(high) - 3} fill="var(--fg-3)" {...label}>
            {compactAuditNumber(high)}
          </text>
          <text x={2} y={y(low) + 11} fill="var(--fg-3)" {...label}>
            {compactAuditNumber(low)}
          </text>
        </g>
      )}
      {bottom < 0 && top > 0 && <line x1={0} x2={width} y1={y(0)} y2={y(0)} stroke="var(--border)" />}
      {points.map((p, i) => {
        const center = slot * (i + 0.5);
        const above = p.value > top;
        const below = p.value < bottom;
        const valueY = above ? CLIP_INSET : below ? plotHeight - CLIP_INSET : y(p.value);
        const yTop = Math.min(valueY, zero);
        const h = Math.max(2, Math.abs(valueY - zero));
        const winsorized = p.isObserved && sample.selected !== null && Math.abs(p.value - sample.selected) > 1e-9;
        const color = winsorized ? 'var(--negative)' : p.isObserved ? 'var(--reserve)' : p.definesResult ? 'var(--brand)' : 'var(--fg-3)';
        const target = winsorized ? y(Math.min(top, Math.max(bottom, sample.selected!))) : null;
        return (
          <g key={i}>
            <rect
              x={center - barWidth / 2}
              y={yTop}
              width={barWidth}
              height={h}
              rx={2}
              fill={color}
              opacity={p.definesResult ? 0.95 : 0.72}
              stroke={p.definesResult ? 'var(--brand)' : undefined}
              strokeWidth={p.definesResult ? 1.4 : undefined}
            />
            {(above || below) && (
              <>
                <BreakMark center={center} barWidth={barWidth} edge={above ? yTop : yTop + h} atTop={above} color={color} />
                <text x={center} y={above ? yTop - 4 : yTop + h + 12} textAnchor="middle" fill="var(--fg)" fontWeight={700} {...label}>
                  {compactAuditNumber(p.value)}
                </text>
              </>
            )}
            {target !== null && (
              <>
                <line x1={center - barWidth / 2 - 4} x2={center + barWidth / 2 + 4} y1={target} y2={target} stroke="var(--brand)" strokeWidth={2} />
                <Arrow x={center} from={valueY} to={target} />
              </>
            )}
            <text x={center} y={plotHeight + 13} textAnchor="middle" fill={p.definesResult ? 'var(--fg)' : 'var(--fg-3)'} {...label}>
              {p.label}
            </text>
          </g>
        );
      })}
      {sample.summary !== null && (
        <g>
          <line x1={0} x2={width} y1={y(sample.summary)} y2={y(sample.summary)} stroke="var(--brand)" strokeDasharray="4 4" />
          <text x={width - 2} y={y(sample.summary) - 4} textAnchor="end" fill="var(--fg)" fontWeight={700} {...label}>
            {sample.summaryLabel} {compactAuditNumber(sample.summary)}
          </text>
        </g>
      )}
    </svg>
  );
}

/** O ziguezague de barra cortada: o valor real está escrito ao lado, fora da escala. */
function BreakMark({ center, barWidth, edge, atTop, color }: { center: number; barWidth: number; edge: number; atTop: boolean; color: string }) {
  const left = center - barWidth / 2;
  const d = atTop ? 1 : -1;
  let path = `M${left} ${edge + 2 * d}`;
  for (let i = 0; i < 4; i++) path += `L${left + (barWidth * (i + 0.5)) / 4} ${edge + (i % 2 === 0 ? 5 : 2) * d}`;
  path += `L${left + barWidth} ${edge + 2 * d}`;
  return <path d={path} fill="none" stroke={color} strokeWidth={1.6} />;
}

function Arrow({ x, from, to }: { x: number; from: number; to: number }) {
  const d = to > from ? 1 : -1;
  return (
    <g stroke="var(--brand)" strokeWidth={1.4}>
      <line x1={x} x2={x} y1={from} y2={to} />
      <line x1={x} x2={x - 3} y1={to} y2={to - 4 * d} />
      <line x1={x} x2={x + 3} y1={to} y2={to - 4 * d} />
    </g>
  );
}
