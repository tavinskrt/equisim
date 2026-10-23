import { Ban, CheckCircle2, Donut, PiggyBank, Ruler, TriangleAlert } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router';

import { FeasibilityLevel, type FeasibilityVerdict, FinancialGoal, type GoalAlignment, Money } from '../../core';
import { FeasibilityCopy, Fmt, Lexicon, SkillCopy, trendOf } from '../../copy';
import { useFeasibility, useGoalAlignment, useSkill } from '../../app/hooks';
import { StudyActions, useStudy } from '../../app/state/study-store';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card, Panel } from '../../ui/card';
import { EmptyState, Skeleton } from '../../ui/feedback';
import { Metric, MetricRow } from '../../ui/metric';
import { Slider } from '../../ui/slider';
import { toneBorder, toneText } from '../../ui/tone';
import { cn } from '../../ui/cn';
import { AccumulationChart, type AccumulationRate, monthlyOf } from './accumulation-chart';
import { feasibilityTitle, feasibilityTone } from './feasibility-tone';
import { MoneySlider } from './money-slider';

const defaults = { initial: 10000, monthly: 1000, target: 500000, months: 120 };

/**
 * **O Planejador da meta**: o plano patrimonial, a rentabilidade que ele exige
 * e onde ela fica contra o CDI e o Ibovespa da década. A viabilidade não
 * depende de avaliação nenhuma: o aviso de meta irreal aparece enquanto se
 * arrasta o controle, antes de escolher qualquer ativo.
 */
export function PlannerPage() {
  const goal = useStudy((s) => s.study.goal);
  const principal = useStudy((s) => s.study.principal);
  const [plan, setPlan] = useState(() =>
    goal === null
      ? defaults
      : {
          initial: goal.initialContribution.reais,
          monthly: goal.monthlyContribution.reais,
          target: goal.targetWealth.reais,
          months: goal.months,
        },
  );

  // O plano vale no estudo assim que a tela abre — como no Flutter, onde o
  // primeiro quadro já gravava os padrões —, e a cada mudança.
  useEffect(() => {
    StudyActions.setGoal(
      FinancialGoal.unvalidated({
        initialContribution: Money.fromReais(plan.initial),
        monthlyContribution: Money.fromReais(plan.monthly),
        months: plan.months,
        targetWealth: Money.fromReais(plan.target),
      }),
    );
  }, [plan]);

  const verdict = useFeasibility(goal);
  const alignment = useGoalAlignment(principal, goal);
  const skill = useSkill();

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-title font-semibold text-fg">Meta</h1>
        <p className="mt-1 text-body-sm text-fg-2">A rentabilidade necessária é derivada destes valores — e confrontada com a renda fixa, a bolsa e a sua carteira.</p>
      </div>
      <div className="grid gap-4 lg:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]">
        <Panel title="Plano patrimonial" subtitle="Aportes, prazo e o valor desejado ao final" className="lg:sticky lg:top-32 lg:self-start">
          <div className="space-y-5">
            <MoneySlider label="Aporte inicial" value={plan.initial} max={2_000_000} step={500} onChange={(initial) => setPlan((p) => ({ ...p, initial }))} />
            <MoneySlider label="Aporte mensal" value={plan.monthly} max={50_000} step={50} onChange={(monthly) => setPlan((p) => ({ ...p, monthly }))} />
            <MoneySlider
              label="Valor desejado ao final"
              value={plan.target}
              min={1000}
              max={20_000_000}
              step={1000}
              onChange={(target) => setPlan((p) => ({ ...p, target }))}
            />
            <Slider
              label="Prazo"
              value={plan.months}
              min={12}
              max={360}
              step={12}
              format={(m) => Fmt.months(m)}
              onChange={(months) => setPlan((p) => ({ ...p, months }))}
            />
            <p className="text-caption text-fg-3">
              Total aportado:{' '}
              <span className="num font-semibold text-fg-2">{Fmt.money(plan.initial + plan.monthly * plan.months)}</span>
            </p>
          </div>
        </Panel>
        <div className="min-w-0 space-y-4">
          {verdict === null ? <VerdictSkeleton /> : <FeasibilityCard verdict={verdict} />}
          {goal !== null && verdict !== null && <Chart verdict={verdict} alignment={alignment.status === 'success' ? alignment.data : null} />}
          {principal.isEmpty ? (
            <Card>
              <EmptyState
                icon={<Donut className="size-5" />}
                title="Sem carteira para comparar"
                message="Monte a carteira Principal para confrontar o retorno esperado com a rentabilidade exigida."
                action={
                  <Button asChild variant="secondary">
                    <Link to="/estudo">Montar a carteira</Link>
                  </Button>
                }
              />
            </Card>
          ) : alignment.status === 'pending' ? (
            <Card className="space-y-3 p-5" aria-label="Avaliando a carteira">
              <Skeleton className="h-5 w-48" />
              <Skeleton className="h-10 w-full" />
            </Card>
          ) : alignment.status === 'success' && alignment.data !== null ? (
            <AlignmentCard
              alignment={alignment.data}
              skillCaveat={skill.status === 'success' ? SkillCopy.caveat(skill.data) : null}
              withPremium={skill.status === 'success' && skill.data?.premiumOrdering != null}
            />
          ) : null}
        </div>
      </div>
    </div>
  );
}

function VerdictSkeleton() {
  return (
    <Card className="space-y-3 p-5" role="status" aria-label="Avaliando a meta">
      <Skeleton className="h-4 w-36" />
      <Skeleton className="h-11 w-full" />
      <Skeleton className="h-4 w-52" />
    </Card>
  );
}

const verdictIcon = (level: FeasibilityLevel) => {
  const cls = 'size-5 shrink-0';
  if (level === FeasibilityLevel.riskFreeSufficient) return <PiggyBank aria-hidden className={cls} />;
  if (level === FeasibilityLevel.plausible) return <CheckCircle2 aria-hidden className={cls} />;
  if (level === FeasibilityLevel.demanding) return <TriangleAlert aria-hidden className={cls} />;
  return <Ban aria-hidden className={cls} />;
};

function FeasibilityCard({ verdict }: { verdict: FeasibilityVerdict }) {
  const tone = feasibilityTone(verdict.level);
  const rate = verdict.requiredAnnualRate;
  const showRates = rate !== null && Number.isFinite(rate);
  return (
    <Card className={cn('border p-4 sm:p-5', toneBorder[tone])}>
      <div className={cn('flex items-center gap-2', toneText[tone])}>
        {verdictIcon(verdict.level)}
        <h2 className="text-title-sm font-bold">{feasibilityTitle(verdict.level)}</h2>
      </div>
      {showRates && (
        <MetricRow className="mt-4 sm:grid-cols-4">
          <Metric label={Lexicon.required} value={Fmt.percent(rate, { decimals: 2 })} hint={Lexicon.requiredPerYear} tone={tone} />
          <Metric label="Equivalente mensal" value={Fmt.percent(Number.isFinite(rate) && rate > -1 ? monthlyOf(rate) : 0, { decimals: 2 })} hint="juros compostos" />
          <Metric label="CDI" value={Fmt.percent(verdict.anchors.riskFreeCagr, { decimals: 1 })} hint={`a.a., ${verdict.anchors.observedYears} anos`} />
          <Metric label="Ibovespa" value={Fmt.percent(verdict.anchors.marketCagr, { decimals: 1 })} hint={`a.a., ${verdict.anchors.observedYears} anos`} />
        </MetricRow>
      )}
      <p className="mt-3 text-body-sm leading-relaxed text-fg-2">{FeasibilityCopy.of(verdict)}</p>
      <p className="mt-2 text-caption text-fg-3">
        Referências dos últimos {verdict.anchors.observedYears} anos: CDI {Fmt.percent(verdict.anchors.riskFreeCagr)} a.a. · Ibovespa{' '}
        {Fmt.percent(verdict.anchors.marketCagr)} a.a.
      </p>
    </Card>
  );
}

function Chart({ verdict, alignment }: { verdict: FeasibilityVerdict; alignment: GoalAlignment | null }) {
  const goal = useStudy((s) => s.study.goal)!;
  const rates: AccumulationRate[] = [];
  if (verdict.requiredAnnualRate !== null && Number.isFinite(verdict.requiredAnnualRate) && verdict.requiredAnnualRate > -1) {
    rates.push({ key: 'exigido', label: Lexicon.required, annual: verdict.requiredAnnualRate, color: 'var(--chart-1)' });
  }
  rates.push({ key: 'cdi', label: 'CDI', annual: verdict.anchors.riskFreeCagr, color: 'var(--chart-2)' });
  rates.push({ key: 'ibov', label: 'Ibovespa', annual: verdict.anchors.marketCagr, color: 'var(--chart-3)' });
  if (alignment !== null) rates.push({ key: 'carteira', label: Lexicon.expected, annual: alignment.expectedReturn, color: 'var(--chart-4)' });
  rates.push({ key: 'aportes', label: 'Só os aportes', annual: 0, color: 'var(--fg-3)', dashed: true });
  return <AccumulationChart goal={goal} rates={rates} />;
}

function AlignmentCard(props: { alignment: GoalAlignment; skillCaveat: string | null; withPremium: boolean }) {
  const { alignment } = props;
  const meets = alignment.meetsGoal;
  return (
    <Panel
      title="Carteira frente à meta"
      subtitle={props.withPremium ? 'Custo do capital próprio mais prêmio pela ordenação medida' : 'Custo do capital próprio, sem prêmio'}
    >
      <MetricRow className="sm:grid-cols-3">
        <Metric
          label={Lexicon.expected}
          value={Fmt.percent(alignment.expectedReturn)}
          hint="retorno total, com proventos reinvestidos"
          tone={meets ? 'positive' : 'negative'}
        />
        <Metric label={Lexicon.required} value={Fmt.percent(alignment.required.annual)} hint={Lexicon.requiredPerYear} />
        <Metric label={Lexicon.margin} value={Fmt.points(alignment.gap)} hint="sobre o exigido" tone={trendOf(alignment.gap)} />
      </MetricRow>
      <div className="mt-4 space-y-2">
        {props.skillCaveat !== null && <Banner icon={<Ruler aria-hidden className="mt-0.5 size-4 shrink-0" />}>{props.skillCaveat}</Banner>}
        {alignment.coverageIsWeak && (
          <Banner tone="caution">
            Apenas {Fmt.percent(alignment.valuationCoverage, { decimals: 0 })} do peso da carteira tem avaliação disponível. O retorno
            esperado é pouco representativo.
          </Banner>
        )}
      </div>
    </Panel>
  );
}
