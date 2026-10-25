import { type AuditEvent, DateTime } from '../core';
import { AuditBus } from './audit-bus';

/** Filtro da lista do painel. A chave é dado gravado no arquivo, e não nome de código. */
export type AuditFilter = 'todos' | 'calculos' | 'valuations-confirmados' | 'rede';

export const AUDIT_FILTERS: readonly AuditFilter[] = ['todos', 'calculos', 'valuations-confirmados', 'rede'];

/** O evento passa no filtro? Pela origem, como [AuditBus.isCalculation]. */
export function matchesFilter(event: AuditEvent, filter: AuditFilter): boolean {
  switch (filter) {
    case 'todos':
      return true;
    case 'calculos':
      return AuditBus.isCalculation(event);
    case 'valuations-confirmados':
      return AuditBus.isConfirmedValuation(event);
    case 'rede':
      return !AuditBus.isCalculation(event);
  }
}

/** O evento casa com a busca — endereço, transação ou nome de fórmula. */
export function matchesQuery(event: AuditEvent, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (q.length === 0) return true;
  if (event.endpoint.toLowerCase().includes(q)) return true;
  if (event.transactionId.toLowerCase().includes(q)) return true;
  return event.calculations.some((c) => c.formulaName.toLowerCase().includes(q));
}

/**
 * O documento exportado pelo painel, no **formato 2**.
 *
 * **O arquivo diz o que ele é, e o que ficou de fora** (item D4): a busca
 * digitada, o filtro, quantos eventos o histórico tinha e quantos o anel
 * descartou por falta de espaço. Um arquivo filtrado ou incompleto não pode
 * parecer o histórico inteiro.
 */
export function buildAuditDocument(args: {
  events: readonly AuditEvent[];
  historySize: number;
  filter: AuditFilter;
  query: string;
  discardedCalculations: number;
  discardedNetwork: number;
  exportedAt?: DateTime;
}): Record<string, unknown> {
  const query = args.query.trim();
  const doc: Record<string, unknown> = {
    aplicacao: 'Equisim',
    documento: 'Auditoria de cálculos',
    formato: 2,
    exportadoEm: (args.exportedAt ?? DateTime.now()).toIso8601String(),
    totalDeEventos: args.events.length,
    totalDeAvaliacoes: args.events.filter((e) => AuditBus.isCalculation(e)).length,
    totalDeCalculos: args.events.reduce((sum, e) => sum + e.calculations.length, 0),
    totalNoHistorico: args.historySize,
    filtroAplicado: args.filter,
    buscaAplicada: query.length === 0 ? null : query,
    descartados: { calculos: args.discardedCalculations, rede: args.discardedNetwork },
  };
  if (args.discardedCalculations > 0 || args.discardedNetwork > 0) {
    doc['aviso'] = 'O histórico descartou eventos antigos por falta de espaço: este arquivo não tem a sessão inteira.';
  }
  doc['eventos'] = args.events.map((e) => e.toJson());
  return doc;
}

/** Nome do arquivo: `equisim-auditoria-AAAA-MM-DDTHH-MM-SS.json`, na hora local. */
export function auditFileName(at: DateTime = DateTime.now()): string {
  const stamp = at.toIso8601String().replaceAll(':', '-').split('.')[0];
  return `equisim-auditoria-${stamp}.json`;
}

/**
 * Entrega o conteúdo como download do navegador.
 *
 * O conteúdo é montado em memória e publicado como *object URL*; nada trafega
 * pela rede. O `revokeObjectURL` logo em seguida devolve a memória — sem ele,
 * exportar várias vezes numa sessão longa deixaria cópias do arquivo presas
 * até a aba ser fechada (https://developer.mozilla.org/docs/Web/API/URL/revokeObjectURL_static).
 */
export function downloadText(filename: string, content: string, type = 'application/json;charset=utf-8'): boolean {
  if (typeof document === 'undefined' || typeof URL.createObjectURL !== 'function') return false;
  const url = URL.createObjectURL(new Blob([content], { type }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Revogado no quadro seguinte: alguns navegadores só começam a ler o blob
  // depois que o clique termina de propagar.
  setTimeout(() => URL.revokeObjectURL(url), 0);
  return true;
}
