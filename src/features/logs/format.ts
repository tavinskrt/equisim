import type { DateTime } from '../../core';

const pad = (n: number, w = 2) => String(n).padStart(w, '0');

/**
 * Número do painel: inteiro com milhar em ponto, fração com vírgula — seis
 * casas abaixo de 1, para taxa e fator não virarem zero, e duas acima.
 *
 * O Flutter usava ponto para os dois separadores ("1.234.50"), o que tornava
 * ambíguo o número que a auditoria existe para conferir.
 */
export function formatAuditNumber(value: number): string {
  if (!Number.isFinite(value)) return String(value);
  if (Math.abs(value - Math.round(value)) < 1e-9 && Math.abs(value) < 1e15) {
    return Math.round(value).toLocaleString('pt-BR', { maximumFractionDigits: 0 });
  }
  const decimals = Math.abs(value) < 1 ? 6 : 2;
  return value.toLocaleString('pt-BR', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}

/** Valor compacto para os rótulos do gráfico da amostra: `1,23 mi`. */
export function compactAuditNumber(value: number): string {
  if (!Number.isFinite(value)) return '—';
  const abs = Math.abs(value);
  const f = (v: number, d: number) => v.toLocaleString('pt-BR', { minimumFractionDigits: d, maximumFractionDigits: d });
  if (abs >= 1e9) return `${f(value / 1e9, 2)} bi`;
  if (abs >= 1e6) return `${f(value / 1e6, 2)} mi`;
  if (abs >= 1e3) return `${f(value / 1e3, 1)} mil`;
  return f(value, 2);
}

export const formatAuditDate = (t: DateTime) => `${pad(t.day)}/${pad(t.month)}/${t.year}`;

export const formatAuditTime = (t: DateTime) => `${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}.${pad(t.millisecond, 3)}`;
