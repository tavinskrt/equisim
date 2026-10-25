import {
  CapmInputs,
  compareNum,
  DateTime,
  Duration,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  type ValuationModel,
} from '../../src/core';
import { DomainCopy } from '../../src/copy/domain-copy';
import { outln } from '../lib/files';
import { num2, pct, type ValidationContext } from './context';

/** Avaliação de um ativo sob uma configuração de premissas. */
export interface SensitivityPoint {
  /** Ativo avaliado. */
  readonly ticker: Ticker;
  /** Configuração de premissas, em texto — o eixo e o valor variados. */
  readonly scenario: string;
  /**
   * Modelo que a cascata escolheu. `null` quando a avaliação falhou.
   *
   * Vale observar quando **muda** entre cenários: uma premissa que derruba o
   * ativo de FCFF para múltiplos altera a qualidade da estimativa, não apenas
   * o número.
   */
  readonly model: ValuationModel | null;
  /** Preço justo por papel. `null` quando a avaliação falhou. */
  readonly fairValue: number | null;
  /** Taxa de desconto efetivamente aplicada. */
  readonly discountRate: number | null;
  /** Motivo da falha, quando houve. Mutuamente exclusivo com [fairValue]. */
  readonly failure: string | null;
}

const failed = (ticker: Ticker, scenario: string, failure: string): SensitivityPoint => ({
  ticker,
  scenario,
  model: null,
  fairValue: null,
  discountRate: null,
  failure,
});

/** Análise de sensibilidade do preço justo às premissas declaradas. */
export const SensitivityReports = {
  /**
   * Varre a amostra medindo a sensibilidade do preço justo às premissas.
   *
   * Três eixos, escolhidos porque são exatamente os que uma banca questiona
   * num DCF: a defasagem de publicação assumida, o prêmio de risco de mercado
   * (que é parâmetro declarado, não observado) e o horizonte de projeção.
   */
  async run(ctx: ValidationContext, symbols: readonly string[]): Promise<SensitivityPoint[]> {
    const points: SensitivityPoint[] = [];
    const today = DateTime.now();

    for (const symbol of symbols) {
      const ticker = Ticker.tryParse(symbol);
      if (ticker === null) continue;
      process.stdout.write('.');

      const anchors = await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark });
      const riskFree = anchors.getOrElse(MarketAnchors.fallback2026).riskFreeCagr;

      const base = await PrepareValuationInputs.call({
        ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: riskFree,
        asOf: today,
      });

      if (base.isErr) {
        points.push(failed(ticker, 'base', base.failureOrNull!.message));
        continue;
      }

      const inputs = base.unwrap();

      // Eixo 1 — defasagem de publicação assumida.
      for (const lagDays of [0, 90, 180, 365]) {
        const view = new PointInTimeView(today, { publicationLag: new Duration({ days: lagDays }) });
        const visible = view.published(inputs.fundamentals);
        points.push(
          evaluate(
            new ValuationInputs({ ticker, asOf: today, fundamentals: visible, marketPrice: inputs.marketPrice, capm: inputs.capm }),
            `defasagem ${lagDays}d`,
          ),
        );
      }

      // Eixo 2 — prêmio de risco de mercado.
      for (const premium of [0.045, 0.055, 0.065]) {
        points.push(
          evaluate(
            new ValuationInputs({
              ticker,
              asOf: today,
              fundamentals: inputs.fundamentals,
              marketPrice: inputs.marketPrice,
              capm: new CapmInputs({
                riskFreeRate: inputs.capm.riskFreeRate,
                beta: inputs.capm.beta,
                marketPremium: premium,
                betaSource: inputs.capm.betaSource,
              }),
            }),
            `prêmio ${pct(premium, 1)}`,
          ),
        );
      }

      // Eixo 3 — horizonte de projeção explícita.
      for (const years of [3, 5, 10]) {
        points.push(
          evaluate(
            new ValuationInputs({
              ticker,
              asOf: today,
              fundamentals: inputs.fundamentals,
              marketPrice: inputs.marketPrice,
              capm: inputs.capm,
              projectionYears: years,
            }),
            `projeção ${years}a`,
          ),
        );
      }
    }
    outln();
    return points;
  },

  /**
   * Formata a varredura como relatório Markdown, apontando qual eixo moveu
   * mais o preço justo de cada ativo.
   */
  report(points: readonly SensitivityPoint[]): string {
    const byTicker = new Map<Ticker, SensitivityPoint[]>();
    for (const point of points) {
      const list = byTicker.get(point.ticker) ?? [];
      list.push(point);
      byTicker.set(point.ticker, list);
    }

    const lines = [
      '# Sensibilidade da avaliação às premissas',
      '',
      `Gerado em ${DateTime.now().toIso8601String().slice(0, 19)}.`,
      '',
      'Mede quanto o preço justo se move ao variar três premissas declaradas: a defasagem de publicação dos demonstrativos, o prêmio ' +
        'de risco de mercado e o horizonte de projeção explícita. Nenhuma das três é observável — todas são escolhas metodológicas, e o ' +
        'trabalho precisa mostrar o peso de cada uma.',
      '',
    ];

    // --- Distribuição dos modelos aplicados ---
    const modelCounts = new Map<ValuationModel, number>();
    let failures = 0;
    for (const point of points) {
      if (point.model !== null) modelCounts.set(point.model, (modelCounts.get(point.model) ?? 0) + 1);
      else failures++;
    }

    lines.push(
      '## Modelos efetivamente aplicados',
      '',
      'A cascata escolhe o modelo mais exigente que os dados sustentam. A distribuição abaixo indica a qualidade média dos dados ' +
        'disponíveis na fonte.',
      '',
      '| Modelo | Ocorrências |',
      '|---|---|',
    );
    for (const [model, count] of modelCounts) lines.push(`| ${DomainCopy.model(model)} | ${count} |`);
    if (failures > 0) lines.push(`| *(não avaliável)* | ${failures} |`);

    // --- Amplitude por ativo ---
    lines.push(
      '',
      '## Amplitude do preço justo por ativo',
      '',
      '| Ativo | Mínimo | Base | Máximo | Amplitude | Premissa mais influente |',
      '|---|---|---|---|---|---|',
    );

    for (const [ticker, list] of byTicker) {
      const valued = list.filter((p) => p.fairValue !== null);
      if (valued.length === 0) {
        lines.push(`| ${ticker.value} | — | — | — | — | ${list[0]!.failure ?? 'sem dados'} |`);
        continue;
      }

      const values = valued.map((p) => p.fairValue!).sort(compareNum);
      const baseline = valued.find((p) => p.scenario === 'defasagem 90d') ?? valued[0]!;
      const spread = baseline.fairValue! > 0 ? (values[values.length - 1]! - values[0]!) / baseline.fairValue! : 0.0;

      lines.push(
        `| ${ticker.value} | ${num2(values[0]!, 2)} | ${num2(baseline.fairValue!, 2)} | ${num2(values[values.length - 1]!, 2)} ` +
          `| ${pct(spread, 0)} | ${mostInfluential(valued, baseline.fairValue!)} |`,
      );
    }

    // --- Detalhamento ---
    lines.push('', '## Detalhamento', '', '| Ativo | Cenário | Modelo | Preço justo | Taxa de desconto |', '|---|---|---|---|---|');
    for (const point of points) {
      lines.push(
        `| ${point.ticker.value} | ${point.scenario} | ${point.model === null ? '—' : DomainCopy.model(point.model)} ` +
          `| ${point.fairValue === null ? '—' : num2(point.fairValue, 2)} | ${point.discountRate === null ? '—' : pct(point.discountRate)} |`,
      );
    }

    return `${lines.join('\n')}\n`;
  },
};

function evaluate(inputs: ValuationInputs, scenario: string): SensitivityPoint {
  return ValuationCascade.evaluate(inputs).fold<SensitivityPoint>(
    (valuation) => ({
      ticker: inputs.ticker,
      scenario,
      model: valuation.model,
      fairValue: valuation.fairValue.reais,
      discountRate: valuation.discountRate,
      failure: null,
    }),
    (failure) => failed(inputs.ticker, scenario, failure.message),
  );
}

/** Qual eixo produz o maior desvio em relação ao cenário central. */
function mostInfluential(points: readonly SensitivityPoint[], baseline: number): string {
  if (baseline <= 0) return '—';
  const byAxis = new Map<string, number>();
  for (const point of points) {
    if (point.fairValue === null) continue;
    const axis = point.scenario.split(' ')[0]!;
    const deviation = Math.abs(point.fairValue - baseline) / baseline;
    if (deviation > (byAxis.get(axis) ?? 0)) byAxis.set(axis, deviation);
  }
  if (byAxis.size === 0) return '—';
  let worst: [string, number] | null = null;
  for (const entry of byAxis) if (worst === null || !(worst[1] >= entry[1])) worst = entry;
  return `${worst![0]} (${pct(worst![1], 0)})`;
}
