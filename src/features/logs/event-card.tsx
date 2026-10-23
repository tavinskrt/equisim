import katex from 'katex';
import { ArrowRight, ChevronDown } from 'lucide-react';
import { Collapsible } from 'radix-ui';
import { memo, type ReactNode, useMemo, useState } from 'react';

import { AuditBus } from '../../audit/audit-bus';
import type { AuditEvent, CalculationTrace } from '../../core';
import { cn } from '../../ui/cn';
import { formatAuditDate, formatAuditNumber, formatAuditTime } from './format';
import { JsonPanel } from './json-tree';
import { SampleChart } from './sample-chart';

/**
 * Um evento da auditoria, recolhido no cabeçalho: endereço, transação, hora e
 * duração. Aberto, as três seções — **A** o que entrou e saiu, **B** as
 * fórmulas em LaTeX na ordem em que o motor as aplicou, **C** cada símbolo com
 * o seu valor e cada etapa intermediária. A numeração de C acompanha a de B.
 *
 * O conteúdo só monta aberto: uma sessão longa tem centenas de eventos, e
 * renderizar o LaTeX de todos travaria o painel.
 */
export const EventCard = memo(function EventCard({ event, ordinal }: { event: AuditEvent; ordinal: number }) {
  const [open, setOpen] = useState(false);
  const network = !AuditBus.isCalculation(event);
  const confirmed = AuditBus.isConfirmedValuation(event);
  const failed = event.outputPayload['status'] === 'falha';
  const accent = failed ? 'negative' : network ? 'reserve' : 'brand';

  return (
    <Collapsible.Root open={open} onOpenChange={setOpen} className="overflow-hidden rounded-xl border border-line bg-surface">
      <Collapsible.Trigger className="flex w-full items-start gap-2.5 px-3.5 py-3 text-left hover:bg-raised">
        <span
          className={cn(
            'mt-0.5 inline-flex size-6.5 shrink-0 items-center justify-center rounded-md text-caption font-bold',
            accent === 'negative' && 'bg-negative-surface text-negative',
            accent === 'reserve' && 'bg-reserve-surface text-reserve dark:text-reserve-muted',
            accent === 'brand' && 'bg-brand-surface text-positive',
          )}
        >
          {ordinal}
        </span>
        <span className="min-w-0 flex-1">
          <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span className="min-w-0 truncate font-mono text-body-sm font-bold text-fg">{event.endpoint}</span>
            <Tag event={event} network={network} confirmed={confirmed} failed={failed} />
          </span>
          <span className="mt-1 block truncate font-mono text-caption text-fg-3">
            tx {event.transactionId} · {confirmed ? `${formatAuditDate(event.timestamp)} ` : ''}
            {formatAuditTime(event.timestamp)} · {event.executionTimeMs} ms
          </span>
        </span>
        <ChevronDown aria-hidden className={cn('mt-1 size-4 shrink-0 text-fg-3 transition-transform', open && 'rotate-180')} />
      </Collapsible.Trigger>
      <Collapsible.Content className="space-y-4 px-3.5 pb-4">
        <Section
          letter="A"
          title="Requisição & Resposta"
          subtitle={
            network
              ? 'Payload bruto trocado com a fonte de dados.'
              : confirmed
                ? 'As premissas que o usuário confirmou, as do motor de que elas partiram, e o resultado gravado com elas.'
                : 'Insumos resolvidos que entraram no motor e o resultado que saiu dele.'
          }
        >
          <div className="space-y-2">
            <JsonPanel label="inputPayload" value={event.inputPayload} />
            <JsonPanel label="outputPayload" value={event.outputPayload} />
          </div>
        </Section>
        {!network && (
          <>
            <Section letter="B" title="Fórmulas e Equações" subtitle="Cada expressão como aparece na metodologia, na ordem em que o motor a aplicou.">
              <div className="space-y-2">
                {event.calculations.map((c, i) => (
                  <FormulaBlock key={i} ordinal={i + 1} trace={c} />
                ))}
              </div>
            </Section>
            <Section
              letter="C"
              title="Substituição de Variáveis e Decomposição"
              subtitle="O valor atribuído a cada símbolo e o resultado de cada etapa intermediária. A numeração acompanha a seção B."
            >
              <div className="space-y-2">
                {event.calculations.map((c, i) => (
                  <SubstitutionBlock key={i} ordinal={i + 1} trace={c} />
                ))}
              </div>
            </Section>
          </>
        )}
      </Collapsible.Content>
    </Collapsible.Root>
  );
});

function Tag({ event, network, confirmed, failed }: { event: AuditEvent; network: boolean; confirmed: boolean; failed: boolean }) {
  const [text, tone] =
    failed && confirmed
      ? ['valuation não salvo', 'negative']
      : failed
        ? ['sem modelo aplicável', 'negative']
        : confirmed
          ? ['valuation confirmado', 'brand']
          : network
            ? [`HTTP ${String(event.outputPayload['statusCode'] ?? '—')}`, 'reserve']
            : [`${event.calculations.length} fórmula(s)`, 'brand'];
  return (
    <span
      className={cn(
        'shrink-0 rounded px-2 py-0.5 font-mono text-caption font-bold',
        tone === 'negative' && 'bg-negative-surface text-negative',
        tone === 'reserve' && 'bg-reserve-surface text-reserve dark:text-reserve-muted',
        tone === 'brand' && 'bg-brand-surface text-positive',
      )}
    >
      {text}
    </span>
  );
}

function Section(props: { letter: string; title: string; subtitle: string; children: ReactNode }) {
  return (
    <section>
      <div className="flex items-center gap-2">
        <span className="rounded bg-brand-surface px-1.5 py-0.5 text-caption font-bold tracking-[0.06em] text-positive">SEÇÃO {props.letter}</span>
        <h3 className="text-body-sm font-bold text-fg">{props.title}</h3>
      </div>
      <p className="mt-1 text-caption text-fg-3">{props.subtitle}</p>
      <div className="mt-2">{props.children}</div>
    </section>
  );
}

const withUnit = (value: number, unit: string) => `${formatAuditNumber(value)}${unit === '' ? '' : ` ${unit}`}`;

/**
 * A fórmula em LaTeX, desenhada pelo KaTeX. `trust: false` (o padrão) e
 * `throwOnError: false`: o LaTeX vem do núcleo, e um comando que o KaTeX não
 * conhece vira o texto em vermelho, e não uma exceção que derruba o painel.
 */
function FormulaBlock({ ordinal, trace }: { ordinal: number; trace: CalculationTrace }) {
  const html = useMemo(() => {
    try {
      return katex.renderToString(trace.latexRepresentation, { displayMode: true, throwOnError: false, output: 'htmlAndMathml', strict: 'ignore' });
    } catch {
      return null;
    }
  }, [trace.latexRepresentation]);
  return (
    <div className="rounded-lg border border-line bg-sunken px-3 pb-3 pt-2.5">
      <p className="text-label font-semibold text-fg">
        {ordinal}. {trace.formulaName}
      </p>
      {html === null ? (
        <pre className="mt-2 overflow-x-auto font-mono text-label text-caution">{trace.latexRepresentation}</pre>
      ) : (
        // O HTML vem do KaTeX, que escapa o texto da fórmula; nada do usuário entra aqui.
        <div className="mt-1 text-fg" dangerouslySetInnerHTML={{ __html: html }} />
      )}
      {trace.finalValue !== null && (
        <p className="mt-2 flex items-center gap-1.5 font-mono text-label font-bold text-positive select-text">
          <ArrowRight aria-hidden className="size-3.5" />
          {withUnit(trace.finalValue, trace.unit)}
        </p>
      )}
    </div>
  );
}

function SubstitutionBlock({ ordinal, trace }: { ordinal: number; trace: CalculationTrace }) {
  const variables = Object.entries(trace.mappedVariables);
  return (
    <div className="rounded-lg border border-line bg-sunken px-3 pb-3 pt-2.5">
      <p className="text-label font-semibold text-fg">
        {ordinal}. {trace.formulaName}
      </p>
      {trace.explanation.length > 0 && (
        <div className="mt-2 rounded-md border-l-[3px] border-brand bg-brand-surface px-3 py-2">
          <p className="eyebrow text-positive">Por quê</p>
          {trace.explanation.map((line, i) => (
            <p key={i} className={cn('text-body-sm leading-relaxed text-fg select-text', i > 0 && 'mt-2', i === 1 && 'font-semibold')}>
              {line}
            </p>
          ))}
        </div>
      )}
      {trace.sample !== null && trace.sample.points.length > 0 && (
        <div className="mt-3">
          <SampleChart sample={trace.sample} />
        </div>
      )}
      {variables.length > 0 && (
        <>
          <p className="eyebrow mt-3">Variáveis mapeadas</p>
          <table className="mt-1.5 w-full overflow-hidden rounded-md border border-line font-mono text-label">
            <caption className="sr-only">Variáveis mapeadas de {trace.formulaName}</caption>
            <tbody>
              {variables.map(([symbol, value]) => (
                <tr key={symbol} className="border-b border-line last:border-0">
                  <th scope="row" className="w-[45%] px-2.5 py-1.5 text-left font-normal break-all text-json-key">
                    {symbol}
                  </th>
                  <td className={cn('px-2.5 py-1.5 font-bold break-all select-text', value == null ? 'text-caution' : 'text-fg')}>
                    {value == null ? 'indisponível' : typeof value === 'number' ? formatAuditNumber(value) : String(value)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
      {trace.intermediateSteps.length > 0 && (
        <>
          <p className="eyebrow mt-3">Decomposição</p>
          <ul className="mt-1.5 space-y-1">
            {trace.intermediateSteps.map((step, i) => (
              <li key={i} className="flex gap-2.5 font-mono text-label leading-relaxed text-fg select-text">
                <span aria-hidden className="mt-[7px] size-1.5 shrink-0 rounded-full bg-brand" />
                <span className="min-w-0 break-words">{step}</span>
              </li>
            ))}
          </ul>
        </>
      )}
      {trace.finalValue !== null && (
        <p className="mt-2 rounded-md bg-brand-surface px-2.5 py-1.5 font-mono text-label font-bold text-positive select-text">
          Resultado: {withUnit(trace.finalValue, trace.unit)}
        </p>
      )}
    </div>
  );
}
