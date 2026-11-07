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
 * que o prazo da meta, e a cesta de uma ação de cada ativo não é o patrimônio
 * do plano; taxas anualizadas se comparam entre durações e tamanhos
 * diferentes, patrimônios não.
 *
 * **O realizado é o CAGR**: com uma compra só, no primeiro
 * pregão, não há fluxo intermediário, e o retorno ponderado pelo dinheiro
 * coincide com o ponderado pelo tempo — o XIRR repetiria o CAGR.
 */
export function GoalConfrontation({ principal, reserve }: { principal: BacktestOutcome; reserve: BacktestOutcome | null }) {
  const goal = useStudy((s) => s.study.goal);
  const verdict = useFeasibility(goal);
  const required = verdict?.requiredAnnualRate ?? null;
  // Meta que o solver não resolveu: a aba Meta já explica; um travessão sem
  // contexto aqui só ocuparia espaço.
  if (required === null || !Number.isFinite(required)) return null;

  const realized = principal.metrics.cagr;
  const margin = (realized - required) * 100;
  const alternative = reserve?.metrics.cagr ?? null;

  return (
    // "Realizado", e não "frente à meta" sozinho (lente `tela`, 22/09/2026):
    // a Meta tem um cartão de layout parecido que mostra o ESPERADO.
    <Panel title="O realizado frente à meta" subtitle={`No período simulado · ${principal.effectivePeriod.toString()}`}>
      <MetricRow>
        <Metric label={Lexicon.required} value={Fmt.percent(required)} hint={Lexicon.requiredPerYear} />
        <Metric label={Lexicon.realized} value={Fmt.percent(realized, { signed: true })} hint={Lexicon.realizedCagr} tone={trendOf(realized)} />
        <Metric label={Lexicon.margin} value={Fmt.points(margin)} tone={trendOf(margin)} />
      </MetricRow>
      <p className="mt-3 text-caption text-fg-3">
        O exigido vem do plano da aba Meta. O realizado é o CAGR da cesta comprada no início da janela, só de preço — a simulação não distribui provento —: o que esta
        composição entregou no passado, e não o que ela promete para o prazo da meta.
      </p>
      {alternative !== null && (
        // Sem ponto final: `Fmt.points` termina em "p.p.", e a abreviação já fecha a frase.
        <p className="mt-2 text-caption text-fg-2">
          A Reserva, comprada no mesmo pregão, teria rendido {Fmt.percent(alternative, { signed: true })} ao ano — folga de {Fmt.points((alternative - required) * 100)}
        </p>
      )}
    </Panel>
  );
}
