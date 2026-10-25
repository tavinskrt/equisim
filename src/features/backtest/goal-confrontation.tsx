import type { BacktestOutcome } from '../../core';
import { Fmt, Lexicon, trendOf } from '../../copy';
import { useFeasibility } from '../../app/hooks';
import { useStudy } from '../../app/state/study-store';
import { Panel } from '../../ui/card';
import { Metric, MetricRow } from '../../ui/metric';

/**
 * **O realizado frente à meta**: a rentabilidade que a meta exige contra a que
 * a janela simulada entregou. Repete os rótulos do cartão da Meta — Exigido,
 * Realizado, Folga — porque é a mesma grandeza, medida de outro jeito: lá o que
 * a avaliação implica, aqui o que a composição entregou.
 *
 * **Confronta taxas, nunca patrimônios.** A janela quase sempre é mais curta
 * que o prazo da meta; taxas anualizadas se comparam entre durações
 * diferentes, patrimônios não.
 */
export function GoalConfrontation({ principal, reserve }: { principal: BacktestOutcome; reserve: BacktestOutcome | null }) {
  const goal = useStudy((s) => s.study.goal);
  const verdict = useFeasibility(goal);
  const required = verdict?.requiredAnnualRate ?? null;
  // Meta que o solver não resolveu: a aba Meta já explica; um travessão sem
  // contexto aqui só ocuparia espaço.
  if (required === null || !Number.isFinite(required)) return null;

  const realized = principal.metrics.moneyWeightedReturn;
  const margin = realized === null ? null : (realized - required) * 100;
  const alternative = reserve?.metrics.moneyWeightedReturn ?? null;

  return (
    // "Realizado", e não "frente à meta" sozinho (lente `tela`, 22/09/2026):
    // a Meta tem um cartão de layout parecido que mostra o ESPERADO.
    <Panel title="O realizado frente à meta" subtitle={`No período simulado · ${principal.effectivePeriod.toString()}`}>
      <MetricRow>
        <Metric label={Lexicon.required} value={Fmt.percent(required)} hint={Lexicon.requiredPerYear} />
        <Metric
          label={Lexicon.realized}
          value={realized === null ? '—' : Fmt.percent(realized, { signed: true })}
          hint={Lexicon.realizedXirr}
          tone={trendOf(realized)}
        />
        <Metric label={Lexicon.margin} value={margin === null ? '—' : Fmt.points(margin)} tone={trendOf(margin)} />
      </MetricRow>
      <p className="mt-3 text-caption text-fg-3">
        O exigido vem do plano da aba Meta. O realizado é o XIRR da janela simulada, só de preço — a simulação não distribui provento —: o que esta composição entregou no
        passado, e não o que ela promete para o prazo da meta.
      </p>
      {alternative !== null && (
        // Sem ponto final: `Fmt.points` termina em "p.p.", e a abreviação já fecha a frase.
        <p className="mt-2 text-caption text-fg-2">
          A Reserva, sob os mesmos aportes, teria rendido {Fmt.percent(alternative, { signed: true })} ao ano — folga de {Fmt.points((alternative - required) * 100)}
        </p>
      )}
    </Panel>
  );
}
