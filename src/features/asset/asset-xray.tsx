import { CircleHelp, OctagonAlert, SlidersHorizontal } from 'lucide-react';
import type { CSSProperties } from 'react';
import { Link } from 'react-router';

import type { Failure, Ticker, ValuationResult } from '../../core';
import { BandCopy, FailureCopy, Fmt, VerdictCopy } from '../../copy';
import { useCalibratedBands, useProfile, useValuation } from '../../app/hooks';
import { usePreferences } from '../../app/state/preferences-store';
import { userValuationOf, useSavedValuations } from '../../app/state/saved-valuations-store';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card, Panel } from '../../ui/card';
import { Disclosure } from '../../ui/disclosure';
import { EmptyState, Skeleton } from '../../ui/feedback';
import { HintPopover } from '../../ui/hint';
import { Metric, MetricRow } from '../../ui/metric';
import { EngineLoading } from '../../ui/engine-loading';
import { CountUp, Stagger, StaggerItem } from '../../ui/motion';
import { Tilt } from '../../ui/tilt';
import { type Tone, toneBorder } from '../../ui/tone';
import { cn } from '../../ui/cn';
import { PortaZeroExplainer } from '../study/porta-zero';
import { CalibratedBandCard } from './calibrated-band-card';
import { CaveatsCard } from './caveats-card';
import { ModelCard } from './model-card';
import { NormalizationPanel } from './normalization-panel';
import { PeerCard } from './peer-card';
import { PriceRuler, type RulerBand, type RulerMark } from './price-ruler';
import { ProjectionTable } from './projection-table';
import { SavedForAsset } from './saved-for-asset';
import { type IndexedSection, SectionIndex } from './section-index';
import { SensitivityCard } from './sensitivity-card';

/**
 * **O corpo do Raio-X**: a avaliação inteira de um ativo, com as premissas à
 * vista. Mora na página própria do ativo (`/ativo/:ticker`, decisão 155), que
 * põe o cabeçalho e o Voltar em volta dele.
 */
export function XRayBody({ ticker }: { ticker: Ticker }) {
  const valuation = useValuation(ticker);
  if (valuation.status === 'pending') return <XRaySkeleton />;
  if (valuation.status === 'error') {
    return (
      <EmptyState
        icon={<OctagonAlert className="size-5" />}
        title="Falha na avaliação"
        message={valuation.error instanceof Error ? valuation.error.message : String(valuation.error)}
        action={<Button onClick={valuation.refetch}>Tentar de novo</Button>}
      />
    );
  }
  if (valuation.data.isErr) {
    return <Refusal ticker={ticker} failure={valuation.data.failureOrNull!} />;
  }
  return <XRayResult result={valuation.data.unwrap()} />;
}

/**
 * Sem preço justo: **o motivo**, e o que a Porta 0 exige. Um traço mudo
 * deixaria a pessoa sem saber se o defeito é do ativo ou do aplicativo.
 */
function Refusal({ ticker, failure }: { ticker: Ticker; failure: Failure }) {
  const gate = failure.message.includes('fora do universo analisável');
  return (
    <div className="space-y-4">
      <EmptyState
        icon={<CircleHelp className="size-5" />}
        title={gate ? `${ticker.value} está fora do universo analisável` : 'Não foi possível avaliar'}
        message={FailureCopy.of(failure)}
      />
      <PortaZeroExplainer />
    </div>
  );
}

/** As etapas da cascata, na ordem em que o motor as percorre. */
const engineSteps = [
  'Buscando os balanços…',
  'Normalizando o lucro…',
  'Calculando a taxa de desconto…',
  'Descontando o fluxo de caixa…',
  'Conferindo os pares…',
];

function XRaySkeleton() {
  return (
    <div className="space-y-4">
      <EngineLoading texts={engineSteps} label="Avaliando o ativo" className="min-h-6" />
      <Skeleton className="h-6 w-2/3" />
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-5/6" />
      <Skeleton className="mt-4 h-32 w-full rounded-xl" />
      <Skeleton className="h-24 w-full rounded-xl" />
    </div>
  );
}

function XRayResult({ result }: { result: ValuationResult }) {
  const mode = usePreferences((s) => s.mode);
  const analyst = mode === 'analyst';
  const verdict = VerdictCopy.of(result);
  const records = useSavedValuations((s) => s.records);
  const mine = userValuationOf(records, result.ticker);
  const tables = useCalibratedBands();
  const bands = tables.status === 'success' ? BandCopy.readings(result, tables.data) : [];
  const caveatCount = (result.diagnostics?.caveats.length ?? 0) + result.warnings.length;
  const manual = result.manual;
  const engineProjection = manual === null ? null : manual.evaluate(manual.enginePremises);

  const marks: RulerMark[] = [
    { key: 'mercado', short: 'Mercado', label: 'Preço de mercado', value: result.marketPrice.reais, color: 'var(--fg)' },
    {
      key: 'justo',
      short: 'Justo',
      label: 'Preço justo do motor',
      value: result.fairValue.reais,
      color: 'var(--chart-1)',
      note: 'pelas premissas do motor',
    },
  ];
  if (result.marginOfSafety > 0) {
    marks.push({
      key: 'margem',
      short: 'Compra',
      label: `Com margem de segurança de ${Fmt.percent(result.marginOfSafety, { decimals: 0 })}`,
      value: result.safetyPrice.reais,
      color: 'var(--chart-6)',
    });
  }
  const peers = result.triangulation?.consolidated ?? null;
  if (peers !== null) {
    marks.push({ key: 'pares', short: 'Pares', label: 'Mediana dos múltiplos de pares', value: peers, color: 'var(--chart-4)', note: 'teste de sanidade, não preço' });
  }
  if (mine !== null) {
    marks.push({
      key: 'seu',
      short: 'Seu',
      label: 'Seu valuation',
      value: mine.fairValuePerShare,
      color: 'var(--chart-5)',
      note: `confirmado em ${Fmt.date(mine.savedAt)}`,
    });
  }
  const rulerBands: RulerBand[] = bands.map((b) => ({
    key: String(b.table.months),
    short: `${b.table.months} m`,
    label: `Faixa calibrada de 80% em ${b.table.months} meses`,
    low: b.low.reais,
    high: b.high.reais,
    note: 'preço mais proventos, medido nas coortes',
  }));

  const sections: IndexedSection[] = [
    { id: 'secao-leitura', label: 'Leitura do motor' },
    { id: 'secao-regua', label: 'Régua de preço' },
    { id: 'secao-simular', label: 'Simular' },
    { id: 'secao-salvos', label: 'Seus valuations' },
    ...(analyst
      ? [
          { id: 'secao-faixa', label: 'Faixa calibrada' },
          { id: 'secao-modelo', label: 'Modelo e taxa' },
          { id: 'secao-lucro', label: 'Lucro de partida' },
          { id: 'secao-sensibilidade', label: 'Sensibilidade' },
          { id: 'secao-pares', label: 'Múltiplos de pares' },
          { id: 'secao-projecao', label: 'Projeção de 10 anos' },
          { id: 'secao-ressalvas', label: 'Ressalvas' },
        ]
      : [{ id: 'secao-ressalvas', label: 'Ressalvas' }]),
  ];
  // O invólucro de um cartão que não tem o que mostrar fica vazio, e some.
  const slot = 'scroll-mt-20 empty:hidden';

  return (
    <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_200px]">
      <Stagger className="min-w-0 space-y-4">
        <StaggerItem id="secao-leitura" className={slot}>
          <Tilt glow={toneGlow[verdict.tone]}>
            <Card className={cn('verdict-glow relative overflow-hidden border p-4 sm:p-6', toneBorder[verdict.tone])} style={{ '--verdict': toneGlow[verdict.tone] } as CSSProperties}>
              <p className="eyebrow">Leitura do motor</p>
              <h2 className="mt-1 text-title font-semibold text-fg">{verdict.title}</h2>
              <p className="mt-2 max-w-prose text-body leading-relaxed text-fg-2">{verdict.sentence}</p>
              {mine !== null && <p className="mt-2 text-body-sm text-fg">{VerdictCopy.mine(mine, result.marketPrice.reais)}</p>}
              <MetricRow className="mt-5 sm:grid-cols-3">
                <Metric label="Preço de mercado" value={<CountUp value={result.marketPrice.reais} format={Fmt.money} />} hint={`em ${Fmt.date(result.asOf)}`} />
                <Metric label="Preço justo" value={<CountUp value={result.fairValue.reais} format={Fmt.money} />} hint="pelas premissas do motor" />
                <Metric
                  label="Potencial"
                  value={<CountUp value={result.upside} format={(v) => Fmt.percent(v, { decimals: 1, signed: true })} />}
                  hint="total, sem prazo"
                  tone={verdict.outlier ? 'caution' : verdict.tone}
                  help={
                    <HintPopover
                      title="Potencial"
                      intro="Distância entre a cotação e o preço justo estimado pelo modelo. É a discordância entre o modelo e o mercado — não um retorno previsto, e sem prazo para se realizar."
                    />
                  }
                />
              </MetricRow>
              {result.marginOfSafety > 0 && (
                <p className="mt-3 text-caption text-fg-2">
                  Com margem de segurança de {Fmt.percent(result.marginOfSafety, { decimals: 0 })}, o preço de compra seria{' '}
                  {Fmt.money(result.safetyPrice.reais)} — {result.isUndervalued ? 'já atingido' : 'ainda não atingido'}.
                </p>
              )}
            </Card>
          </Tilt>
        </StaggerItem>

        <StaggerItem id="secao-regua" className={slot}>
          <Panel
            title="Régua de preço"
            subtitle="Mercado, preço justo e as referências na mesma escala"
            actions={
              <HintPopover
                title="Régua de preço"
                entries={[
                  { term: 'Preço justo', meaning: 'O valor por ação que o fluxo de caixa descontado dá com as premissas do motor.' },
                  { term: 'Mediana dos pares', meaning: 'O preço que os múltiplos (P/L, P/VP, EV/EBITDA) do setor dariam. Serve para conferir o nível, não para substituir o preço justo.' },
                  { term: 'Faixa calibrada', meaning: 'Onde o preço mais os proventos terminaram em 8 de cada 10 avaliações passadas, no horizonte indicado. É a incerteza medida contra o que aconteceu.' },
                  { term: 'Seu valuation', meaning: 'O último que você confirmou discordando do motor. Não tem validação própria: é a conta do motor com os seus números.' },
                ]}
              />
            }
          >
            <PriceRuler marks={marks} bands={rulerBands} />
          </Panel>
        </StaggerItem>

        <StaggerItem id="secao-simular" className={slot}>
          {manual !== null && (
            <Card className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:p-5">
              <div className="min-w-0 flex-1">
                <p className="text-body font-semibold text-fg">Discorda do motor?</p>
                <p className="mt-0.5 text-body-sm text-fg-2">
                  Refaça a conta com os seus números, ou descubra o que o preço de hoje supõe (DCF reverso).
                </p>
              </div>
              <Button asChild variant="primary">
                <Link to={`/ativo/${result.ticker.value}/simular`}>
                  <SlidersHorizontal aria-hidden className="size-4" />
                  Simular minhas premissas
                </Link>
              </Button>
            </Card>
          )}
        </StaggerItem>

        <StaggerItem id="secao-salvos" className={slot}>
          <SavedForAsset result={result} />
        </StaggerItem>

        {analyst ? (
          <>
            <StaggerItem id="secao-faixa" className={slot}>
              <CalibratedBandCard result={result} />
            </StaggerItem>
            <StaggerItem id="secao-modelo" className={slot}>
              <ModelCard result={result} />
            </StaggerItem>
            <StaggerItem id="secao-lucro" className={slot}>
              {result.diagnostics?.baseNormalization != null && (
                <Panel title="Lucro de partida" subtitle="O último exercício ou o ano corrente anualizado, ou corrigido pelo ciclo">
                  <NormalizationPanel normalization={result.diagnostics.baseNormalization} />
                </Panel>
              )}
            </StaggerItem>
            <StaggerItem id="secao-sensibilidade" className={slot}>
              <SensitivityCard result={result} />
            </StaggerItem>
            <StaggerItem id="secao-pares" className={slot}>
              <PeerCard result={result} />
            </StaggerItem>
            <StaggerItem id="secao-projecao" className={slot}>
              {manual !== null && engineProjection !== null && engineProjection.isOk && (
                <Disclosure title="Projeção de 10 anos" summary="A conta do motor, ano a ano, em milhões de reais">
                  <ProjectionTable m={manual} p={manual.enginePremises} output={engineProjection.unwrap()} />
                </Disclosure>
              )}
            </StaggerItem>
            <StaggerItem id="secao-ressalvas" className={slot}>
              <CaveatsCard result={result} />
            </StaggerItem>
          </>
        ) : (
          <>
            <StaggerItem id="secao-ressalvas" className={slot}>
              {caveatCount > 0 && (
                <Disclosure
                  title={`Ressalvas (${caveatCount})`}
                  summary="O que pede cautela ao ler este número"
                  defaultOpen={verdict.outlier}
                >
                  <CaveatsCard result={result} />
                </Disclosure>
              )}
            </StaggerItem>
            <StaggerItem>
              <Banner>
                O modo <strong>Completo</strong> mostra o modelo, a taxa de desconto, a normalização do lucro, a sensibilidade, os
                múltiplos de pares e a projeção de dez anos. Os números são os mesmos nos dois modos.
              </Banner>
            </StaggerItem>
          </>
        )}
      </Stagger>

      {/* O índice fica ao lado no computador; no celular a página é uma coluna só e ele não cabe. */}
      <aside className="sticky top-20 hidden lg:block">
        <SectionIndex sections={sections} />
      </aside>
    </div>
  );
}

/** A cor do brilho do cartão da leitura, pelo tom do veredito. */
const toneGlow: Record<Tone, string> = {
  positive: 'var(--positive)',
  negative: 'var(--negative)',
  caution: 'var(--caution)',
  neutral: 'var(--brand)',
  pending: 'var(--pending)',
  blocked: 'var(--blocked)',
  reserve: 'var(--reserve)',
  brand: 'var(--brand)',
};
