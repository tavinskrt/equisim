import { ArrowLeftRight, CalendarX2, CloudOff, OctagonAlert, Ruler, TrendingUp } from 'lucide-react';
import { Link } from 'react-router';

import { BacktestLimits, type BacktestSettings, type PortfolioComparison, requestedWindow } from '../../app/backtest';
import { CsvExport } from '../../app/csv-export';
import { services } from '../../app/hooks';
import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { useStudy } from '../../app/state/study-store';
import { downloadText } from '../../audit/audit-export';
import type { FinancialGoal } from '../../core';
import { Fmt } from '../../copy';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card, Panel } from '../../ui/card';
import { EmptyState, Skeleton } from '../../ui/feedback';
import { KeyValue } from '../../ui/metric';
import { Slider } from '../../ui/slider';
import { toast } from '../../ui/toast';
import { CorrelationHeatmap } from './correlation-heatmap';
import { EvolutionChart } from './evolution-chart';
import { GoalConfrontation } from './goal-confrontation';
import { PerAssetCard } from './per-asset-card';
import { SideBySidePortfolios, SinglePortfolioMetrics } from './portfolio-metrics';
import { RiskReturnChart } from './risk-return-chart';
import { useComparison, useCorrelation } from './use-comparison';
import { WealthBridge } from './wealth-bridge';

/**
 * Diz, quando é o caso, que a janela não cobre o prazo da meta. `null` quando
 * não há o que dizer: aviso que aparece sempre deixa de ser aviso. O prazo é
 * arredondado **para cima** — 66 meses não cabem em cinco anos.
 */
export function horizonNotice(settings: BacktestSettings, goal: FinancialGoal | null): string | null {
  if (goal === null) return null;
  const window = settings.windowYears;
  const term = Math.ceil(goal.months / 12);
  if (window >= term) return null;
  const warning = `A janela cobre ${window} dos ${term} anos da meta. Compare a RENTABILIDADE, não o patrimônio: o valor final abaixo acumula só parte do plano de aportes, não o prazo inteiro.`;
  if (term <= BacktestLimits.maxWindowYears) return warning;
  return `${warning} A fonte de cotações entrega no máximo ${BacktestLimits.maxWindowYears} anos, então nenhuma posição do controle alcança o prazo da meta.`;
}

/** Explica, em uma frase, por que a janela pedida não pôde ser usada inteira. */
export function shortenedWindowMessage(result: PortfolioComparison): string {
  const start = Fmt.date(result.window.start);
  const requested = Fmt.date(result.requestedWindow.start);
  const culprit = result.limitingTicker === null ? 'nem todos os ativos tinham cotação' : `${result.limitingTicker.value} só tem cotação a partir dessa data`;
  return `Janela encurtada: a simulação começa em ${start}, e não em ${requested}, porque ${culprit}. As duas carteiras usam a mesma janela — é o que mantém o cronograma de aportes idêntico e torna o TWR comparável. Reduza a janela para descartar o ativo como restrição.`;
}

/**
 * **O Laboratório de backtest**: Principal contra Reserva sob o mesmo plano de
 * aportes, na mesma janela. Sem rebalanceamento, compra de ação inteira, caixa
 * por ativo, tarifa da B3 — e só preço: a simulação não distribui provento.
 */
export function BacktestPage() {
  const settings = usePreferences((s) => s.backtest);
  const goal = useStudy((s) => s.study.goal);
  const nothing = useStudy((s) => s.study.principal.isEmpty && s.study.reserve.isEmpty);
  const notice = horizonNotice(settings, goal);

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-title font-semibold text-fg">Backtest</h1>
        <p className="mt-1 text-body-sm text-fg-2">O que as duas carteiras teriam feito no passado, recebendo os aportes do seu plano nas mesmas datas.</p>
      </div>
      <SettingsCard settings={settings} goal={goal} />
      {/* Ressalva do PARÂMETRO, não do resultado: aparece enquanto a simulação roda, porque decide como o número abaixo deve ser lido. */}
      {notice !== null && <Banner icon={<Ruler aria-hidden className="mt-0.5 size-4 shrink-0" />}>{notice}</Banner>}
      {goal === null || nothing ? <NothingYet hasGoal={goal !== null} /> : <ComparisonArea />}
    </div>
  );
}

function SettingsCard({ settings, goal }: { settings: BacktestSettings; goal: FinancialGoal | null }) {
  const start = requestedWindow(services().clock(), settings.windowYears).start;
  return (
    <Panel title="Parâmetros da simulação" subtitle="Sem rebalanceamento: os pesos derivam com o mercado">
      <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] md:gap-8">
        <div>
          <Slider
            label="Janela"
            value={settings.windowYears}
            min={BacktestLimits.minWindowYears}
            max={BacktestLimits.maxWindowYears}
            step={1}
            onChange={(v) => PreferencesActions.setWindowYears(v)}
            format={(v) => `${v} ${v === 1 ? 'ano' : 'anos'}`}
          />
          {/* O prazo da meta logo abaixo, no MESMO formato da aba Meta: empilhados, os dois horizontes se comparam sem trocar de aba. */}
          {goal !== null && <KeyValue className="mt-2" label="Prazo da meta" value={Fmt.months(goal.months)} />}
        </div>
        <p className="text-caption leading-relaxed text-fg-3">
          Quanto tempo de história a simulação percorre, contado de hoje para trás. Com {settings.windowYears} {settings.windowYears === 1 ? 'ano' : 'anos'}, o plano
          de aportes começa em {Fmt.date(start)} e vai até hoje. Janelas maiores incluem mais ciclos de mercado; em compensação, exigem que todos os ativos das
          duas carteiras já negociassem naquela data — quando algum não negociava, a janela é encurtada até o primeiro pregão dele.
        </p>
      </div>
    </Panel>
  );
}

function NothingYet({ hasGoal }: { hasGoal: boolean }) {
  return (
    <Card>
      <EmptyState
        icon={<TrendingUp aria-hidden className="size-6" />}
        title="Nada a simular ainda"
        message="Monte a carteira Principal e defina o plano de aportes na aba Meta."
        action={
          <div className="flex flex-wrap justify-center gap-2">
            <Button asChild variant="secondary">
              <Link to="/estudo">Montar a carteira</Link>
            </Button>
            {!hasGoal && (
              <Button asChild variant="secondary">
                <Link to="/meta">Definir a meta</Link>
              </Button>
            )}
          </div>
        }
      />
    </Card>
  );
}

/**
 * O lugar do resultado enquanto a simulação roda: a altura aproxima a do
 * primeiro bloco real, para a troca ser preenchimento, e não empurrão.
 */
function ComparisonSkeleton() {
  return (
    <Card className="p-5" aria-busy>
      <span className="sr-only" role="status">
        Simulando as carteiras
      </span>
      <Skeleton className="h-3 w-40" />
      <Skeleton className="mt-4 h-[280px] w-full" />
      <Skeleton className="mt-6 h-3 w-32" />
      <Skeleton className="mt-3 h-16 w-full" />
    </Card>
  );
}

function ComparisonArea() {
  const comparison = useComparison();
  if (comparison.status === 'pending') return <ComparisonSkeleton />;
  if (comparison.status === 'error') {
    return (
      <Card>
        <EmptyState
          icon={<OctagonAlert aria-hidden className="size-6" />}
          title="Falha na simulação"
          message={comparison.error instanceof Error ? comparison.error.message : String(comparison.error)}
          action={
            <Button variant="secondary" onClick={comparison.refetch}>
              Tentar de novo
            </Button>
          }
        />
      </Card>
    );
  }
  if (comparison.data === null) return <NothingYet hasGoal />;
  return <ComparisonBody result={comparison.data} />;
}

function exportCsv(result: PortfolioComparison) {
  const study = useStudy.getState().study;
  const now = services().clock();
  const content = CsvExport.document({ studyName: study.name, result, generatedAt: now });
  const slug = study.name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  const date = `${now.year}-${String(now.month).padStart(2, '0')}-${String(now.day).padStart(2, '0')}`;
  // O BOM faz o Excel ler o arquivo como UTF-8; sem ele, "Período" vira "PerÃ­odo".
  if (downloadText(`equisim-backtest-${slug || 'estudo'}-${date}.csv`, `﻿${content}`, 'text/csv;charset=utf-8')) {
    toast('CSV baixado — separador ponto e vírgula, decimal com vírgula: abre direto no Excel em português.', 'success');
    return;
  }
  navigator.clipboard
    ?.writeText(content)
    .then(() => toast('CSV copiado — cole numa planilha ou num arquivo .csv.', 'success'))
    .catch(() => toast('O navegador não permitiu baixar nem copiar o CSV.', 'error'));
}

function ComparisonBody({ result }: { result: PortfolioComparison }) {
  const analyst = usePreferences((s) => s.mode) === 'analyst';
  const correlation = useCorrelation();
  const { principal, reserve } = result;

  if (principal === null && reserve === null) {
    return (
      <Card>
        <EmptyState
          icon={<CloudOff aria-hidden className="size-6" />}
          title="Sem dados de mercado"
          // Dizer o motivo poupa a caçada: quase sempre é um ativo sem cotação no período, e o nome dele está na mensagem.
          message={result.principalFailure ?? result.reserveFailure ?? 'Não foi possível carregar as cotações do período.'}
        />
      </Card>
    );
  }
  const reference = (principal ?? reserve)!;
  const gap = result.twrGap;

  return (
    <div className="space-y-4">
      <EvolutionChart result={result} onExport={() => exportCsv(result)} />
      {gap !== null && (
        <Banner tone={gap >= 0 ? 'positive' : 'negative'} icon={<ArrowLeftRight aria-hidden className="mt-0.5 size-4 shrink-0" />}>
          {gap >= 0
            ? `A Principal rendeu ${Fmt.ratio(gap, 1)} pontos percentuais a mais que a Reserva no período.`
            : `A Reserva teria rendido ${Fmt.ratio(Math.abs(gap), 1)} pontos percentuais a mais que a Principal no período.`}
        </Banner>
      )}
      {result.windowWasShortened && <Banner icon={<CalendarX2 aria-hidden className="mt-0.5 size-4 shrink-0" />}>{shortenedWindowMessage(result)}</Banner>}
      {principal === null && result.principalFailure !== null && <Banner tone="negative">Principal não simulada — {result.principalFailure}</Banner>}
      {reserve === null && result.reserveFailure !== null && <Banner tone="negative">Reserva não simulada — {result.reserveFailure}</Banner>}
      {reference.warnings.map((w) => (
        <Banner key={w} tone="caution">
          {w}
        </Banner>
      ))}

      <div className="grid gap-4 xl:grid-cols-2">
        {principal !== null && <GoalConfrontation principal={principal} reserve={reserve} />}
        <WealthBridge principal={principal} reserve={reserve} />
      </div>

      {principal !== null && reserve !== null ? (
        <SideBySidePortfolios principal={principal} reserve={reserve} essential={!analyst} />
      ) : (
        <>
          {principal !== null && <SinglePortfolioMetrics title="Carteira Principal" outcome={principal} isReserve={false} />}
          {reserve !== null && <SinglePortfolioMetrics title="Carteira Reserva" outcome={reserve} isReserve />}
        </>
      )}

      <PerAssetCard principal={principal} reserve={reserve} />

      {analyst ? (
        <div className="grid gap-4 xl:grid-cols-2">
          {result.riskReturn.length > 0 && <RiskReturnChart result={result} />}
          {correlation.status === 'success' && correlation.data !== null && <CorrelationHeatmap data={correlation.data} />}
        </div>
      ) : (
        <Banner>
          O modo <strong>Completo</strong> mostra a volatilidade, o Sharpe, o Sortino e o Calmar, a dispersão risco × retorno e a correlação entre os ativos. Os
          números são os mesmos nos dois modos.
        </Banner>
      )}
    </div>
  );
}
