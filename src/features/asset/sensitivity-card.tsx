import { Dices } from 'lucide-react';

import { DiscreteScenarios, ScenarioBand, type ValuationResult } from '../../core';
import { DomainCopy, Fmt, trendOf } from '../../copy';
import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { Banner } from '../../ui/banner';
import { Panel } from '../../ui/card';
import { Metric, MetricRow } from '../../ui/metric';
import { Switch } from '../../ui/switch';

interface TornadoBar {
  readonly label: string;
  readonly low: number;
  readonly high: number;
}

/**
 * **Sensibilidade: quanto o preço justo se move com as premissas** (decisão
 * 148). É sensibilidade, e não cenário (decisão 92): a faixa cobriu 8% do que
 * aconteceu nas coortes, e a incerteza medida é a faixa calibrada.
 */
export function SensitivityCard({ result }: { result: ValuationResult }) {
  const settings = usePreferences((s) => s.valuation);
  const base = result.fairValue.reais;
  const scenarios = result.discreteScenarios;
  const distribution = result.distribution;
  const harsh = scenarios?.get(ScenarioBand.bear)?.reais;
  const mild = scenarios?.get(ScenarioBand.bull)?.reais;

  const bars: TornadoBar[] = [];
  if (harsh !== undefined && mild !== undefined) {
    bars.push({ label: 'Crescimento e taxa', low: Math.min(harsh, mild), high: Math.max(harsh, mild) });
  }
  if (distribution !== null) bars.push({ label: 'Faixa sorteada', low: distribution.p5, high: distribution.p95 });

  return (
    <Panel
      title="Sensibilidade"
      subtitle={
        settings.monteCarlo
          ? `Quanto o preço justo se move em ${Fmt.ratio(settings.samples, 0)} sorteios de crescimento, taxa e perpetuidade`
          : 'Quanto o preço justo se move se o crescimento e a taxa mudarem juntos'
      }
    >
      <Switch
        checked={settings.monteCarlo}
        onChange={PreferencesActions.setMonteCarlo}
        label="Monte Carlo"
        description="Sorteia as premissas em vez de usar os três conjuntos fixos. A avaliação é refeita."
        className="mb-4"
      />
      {distribution !== null ? (
        <DistributionView result={result} />
      ) : scenarios !== null ? (
        <DiscreteView result={result} />
      ) : (
        <p className="text-caption text-fg-2">Só o preço justo do motor pôde ser calculado.</p>
      )}
      {harsh !== undefined && mild !== undefined && mild < harsh && (
        <Banner className="mt-4">
          Aqui as premissas mais brandas dão preço menor que as mais duras. A empresa rende abaixo do custo de capital, e
          crescer mais pede reinvestir num negócio que não paga o que custa: o crescimento destrói valor em vez de criar.
          Não é erro da conta.
        </Banner>
      )}
      {bars.length > 0 && <Tornado bars={bars} base={base} />}
      <p className="mt-3 text-caption text-fg-3">
        A linha central é o preço justo do motor ({Fmt.money(base)}). Isto é sensibilidade, e não probabilidade: a incerteza
        medida é a faixa calibrada.
      </p>
    </Panel>
  );
}

function DiscreteView({ result }: { result: ValuationResult }) {
  const scenarios = result.discreteScenarios!;
  const base = result.fairValue.reais;
  const g = Fmt.ratio(DiscreteScenarios.defaultGrowthDelta * 100, 0);
  const d = Fmt.ratio(DiscreteScenarios.defaultDiscountDelta * 100, 0);
  // Espaço fixo entre o número e a unidade: em coluna estreita a quebra
  // separava "−3" de "p.p.".
  const note = (band: ScenarioBand) =>
    band === ScenarioBand.bear
      ? `crescimento −${g} p.p., taxa +${d} p.p.`
      : band === ScenarioBand.base
        ? 'o preço justo'
        : `crescimento +${g} p.p., taxa −${d} p.p.`;
  return (
    <MetricRow className="sm:grid-cols-3">
      {ScenarioBand.values.map((band) => {
        const value = scenarios.get(band);
        if (value === undefined) return null;
        // A cor sai da posição contra o preço justo, e não do nome: com o
        // crescimento destruindo valor, as brandas dão preço menor.
        return (
          <Metric
            key={band.name}
            label={DomainCopy.band(band)}
            value={Fmt.money(value.reais)}
            hint={note(band)}
            tone={band === ScenarioBand.base ? 'neutral' : trendOf(value.reais - base)}
            size="sm"
          />
        );
      })}
    </MetricRow>
  );
}

function DistributionView({ result }: { result: ValuationResult }) {
  const distribution = result.distribution!;
  const market = result.marketPrice.reais;
  const probability = distribution.probabilityAbove(market);
  return (
    <div className="space-y-4">
      <MetricRow className="sm:grid-cols-3">
        <Metric label="P5" value={Fmt.money(distribution.p5)} hint="5% dos sorteios abaixo" size="sm" />
        <Metric label="Mediana" value={Fmt.money(distribution.median)} hint="metade abaixo, metade acima" size="sm" />
        <Metric label="P95" value={Fmt.money(distribution.p95)} hint="5% dos sorteios acima" size="sm" />
      </MetricRow>
      <Banner tone={probability > 0.5 ? 'positive' : 'negative'} icon={<Dices aria-hidden className="mt-0.5 size-4 shrink-0" />}>
        Em {Fmt.percent(probability, { decimals: 0 })} dos sorteios de premissas o preço justo supera o preço de mercado atual (
        {Fmt.money(market)}). Sorteio de premissa não é probabilidade de preço.
      </Banner>
    </div>
  );
}

/** O tornado: cada barra é a faixa que a premissa move, contra a linha do preço justo. */
function Tornado({ bars, base }: { bars: readonly TornadoBar[]; base: number }) {
  const lo = Math.min(base, ...bars.map((b) => b.low));
  const hi = Math.max(base, ...bars.map((b) => b.high));
  const span = hi - lo || 1;
  const pos = (v: number) => ((v - lo) / span) * 100;
  return (
    <figure className="mt-4">
      <div className="space-y-3">
        {bars.map((b) => (
          <div key={b.label} className="grid grid-cols-[minmax(96px,30%)_1fr] items-center gap-3">
            <p className="truncate text-body-sm text-fg-2">{b.label}</p>
            <div>
              <div className="relative h-5">
                <div
                  className="absolute inset-y-0.5 rounded-[4px]"
                  style={{
                    left: `${pos(b.low)}%`,
                    width: `${Math.max(pos(b.high) - pos(b.low), 0.8)}%`,
                    background: 'color-mix(in oklab, var(--chart-2) 60%, transparent)',
                  }}
                />
                <div className="absolute inset-y-0 w-0.5 -translate-x-1/2 bg-fg" style={{ left: `${pos(base)}%` }} aria-hidden />
              </div>
              <p className="num mt-0.5 flex justify-between text-caption text-fg-3">
                <span>{Fmt.money(b.low)}</span>
                <span>{Fmt.money(b.high)}</span>
              </p>
            </div>
          </div>
        ))}
      </div>
      <figcaption className="sr-only">
        {bars.map((b) => `${b.label}: de ${Fmt.money(b.low)} a ${Fmt.money(b.high)}`).join('; ')}; preço justo {Fmt.money(base)}.
      </figcaption>
    </figure>
  );
}
