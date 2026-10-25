import { RotateCcw } from 'lucide-react';

import {
  type BaseNormalization,
  type Failure,
  InvalidInput,
  ManualField,
  ManualGrowthPath,
  type ManualOutcome,
  type ManualPremises,
  ManualRatePath,
  ManualReinvestment,
  type ManualValuation,
  ValuationLane,
} from '../../core';
import { Fmt, ManualCopy } from '../../copy';
import { Card } from '../../ui/card';
import { NormalizationPanel } from '../asset/normalization-panel';
import { FieldCard, Modes, NumericField, TextAction } from './field-card';
import { Units } from './units';

const ref = Units.reference;

/** O campo que a recusa nomeia; o crescimento da perpetuidade também acusa a taxa, porque é a distância entre os dois que a conta recusa. */
function errorFor(failure: Failure | null, field: ManualField): string | null {
  if (!(failure instanceof InvalidInput) || failure.field === null) return null;
  const refused = ManualField.values.find((f) => f.name === failure.field);
  if (refused === undefined) return null;
  const names = refused === field || (refused === ManualField.perpetualGrowth && field === ManualField.discountRate);
  return names ? ManualCopy.refusal(failure) : null;
}

/**
 * **Seus números**: os campos abrem com os do motor, e o preço muda enquanto
 * se digita. Cada um diz de onde veio o número do motor — a referência é o
 * que torna a discordância uma decisão, e não um chute.
 */
export function PremiseFields(props: {
  m: ManualValuation;
  p: ManualPremises;
  failure: Failure | null;
  output: ManualOutcome | null;
  changed: boolean;
  normalization: BaseNormalization | null;
  onChange: (p: ManualPremises) => void;
}) {
  const { m, p, failure, output, onChange } = props;
  const engine = m.enginePremises;
  const lane = m.lane;
  const error = (f: ManualField) => errorFor(failure, f);
  const published = m.publishedBase;
  // O ano corrente anualizado, quando ele fecha a série (decisão 153).
  const months = m.publishedMonths;
  const lastPeriod =
    months === null
      ? 'o último exercício'
      : `o ano de ${m.publishedYear} anualizado (${months} ${months === 1 ? 'mês' : 'meses'} × 12/${months})`;

  const refBase = m.rebuiltBase
    ? `Motor: ${ref('reais', engine.baseProfit)} — reconstruído do retorno do ciclo, porque ${lastPeriod} veio no prejuízo.`
    : published !== null && Math.abs(m.baseFactor - 1) > 0.005
      ? `Motor: ${ref('reais', engine.baseProfit)} — ${lastPeriod}, ${ref('reais', published)}, normalizado ${m.baseFactor > 1 ? 'para cima' : 'para baixo'} pelo ciclo (×${Fmt.ratio(m.baseFactor, 2)}).`
      : `Motor: ${ref('reais', engine.baseProfit)} — ${months === null ? 'o último exercício publicado' : lastPeriod}.`;

  const rateRef = `Motor: ${ref('rate', engine.discountRate)} no ano 1 e ${ref('rate', m.engineTerminalRate)} na perpetuidade — a curva de juros do Tesouro mais o beta vezes o prêmio de mercado.`;
  const wacc = output?.capitalCostRates ?? null;
  const firmNote =
    lane === ValuationLane.firm && wacc !== null && wacc.length > 0
      ? `Na via da firma, o custo médio do capital do motor (${ref('rate', wacc[0]!)} no ano 1) continua guiando o retorno e a perpetuidade da operação: a taxa daqui só desconta.`
      : null;
  const newCapitalRef =
    engine.terminalReturn === null
      ? `Motor: igual à taxa (${ref('rate', m.engineTerminalRate)}).`
      : `Motor: ${ref('rate', engine.terminalReturn)} — vantagem competitiva medida no histórico da empresa.`;

  return (
    <div className="space-y-4">
      <Card className="p-4 sm:p-5">
        <h2 className="text-title-sm font-semibold text-fg">Seus números</h2>
        <p className="mt-0.5 text-body-sm text-fg-2">Os campos abrem com os números do motor. Troque o que discordar: o preço muda enquanto você digita.</p>
        <p className="mt-3 text-body-sm text-fg-2">
          {lane === ValuationLane.firm
            ? 'Este ativo é avaliado pela via da firma: a conta parte do lucro da operação, desconta o que sobra ao acionista depois da dívida e divide pelas ações.'
            : 'Este ativo é avaliado pela via do acionista: a conta parte do lucro líquido, desconta o que sobra depois de reinvestir e divide pelas ações.'}
        </p>
        {props.changed && (
          <TextAction icon={<RotateCcw aria-hidden className="size-4" />} onClick={() => onChange(engine)}>
            Voltar aos números do motor
          </TextAction>
        )}
      </Card>

      <NumericField
        field={ManualField.baseProfit}
        label={ManualCopy.label(ManualField.baseProfit, lane)}
        explanation={ManualCopy.explanation(ManualField.baseProfit, lane)}
        reference={refBase}
        value={p.baseProfit}
        engineValue={engine.baseProfit}
        unit="reais"
        step={Math.abs(engine.baseProfit * 0.05)}
        grid={1e5}
        minimum={0}
        maximum={engine.baseProfit * 3}
        error={error(ManualField.baseProfit)}
        onChange={(v) => onChange(p.copyWith({ baseProfit: v }))}
        extras={
          published !== null && published > 0 && Math.abs(published - p.baseProfit) > Units.tolerance('reais') ? (
            <TextAction onClick={() => onChange(p.copyWith({ baseProfit: published }))}>
              {months === null ? 'Usar o último exercício' : `Usar ${lastPeriod}`} ({ref('reais', published)})
            </TextAction>
          ) : undefined
        }
        detail={props.normalization === null ? undefined : <NormalizationPanel normalization={props.normalization} editable />}
      />

      <NumericField
        field={ManualField.growth}
        label={ManualCopy.label(ManualField.growth, lane)}
        explanation={ManualCopy.explanation(ManualField.growth, lane)}
        reference={`Motor: ${ref('rate', engine.growth)} no ano 1, caindo em linha reta até o crescimento da perpetuidade.`}
        value={p.growth}
        engineValue={engine.growth}
        unit="rate"
        step={0.0025}
        grid={0.0025}
        minimum={-0.2}
        maximum={0.4}
        error={error(ManualField.growth)}
        onChange={(v) => onChange(p.copyWith({ growth: v }))}
        forcedChanged={p.growthPath !== engine.growthPath}
        onBackToEngine={() => onChange(p.copyWith({ growth: engine.growth, growthPath: engine.growthPath }))}
        modes={
          <Modes
            label="Caminho do crescimento"
            value={p.growthPath.name}
            options={[
              { value: ManualGrowthPath.decays.name, label: 'Cai até a perpetuidade' },
              { value: ManualGrowthPath.constant.name, label: 'Constante nos 10 anos' },
            ]}
            onChange={(v) => onChange(p.copyWith({ growthPath: ManualGrowthPath.values.find((x) => x.name === v)! }))}
          />
        }
      />

      <NumericField
        field={ManualField.perpetualGrowth}
        label={ManualCopy.label(ManualField.perpetualGrowth, lane)}
        explanation={ManualCopy.explanation(ManualField.perpetualGrowth, lane)}
        reference={`Motor: ${ref('rate', engine.perpetualGrowth)}.`}
        value={p.perpetualGrowth}
        engineValue={engine.perpetualGrowth}
        unit="rate"
        step={0.0025}
        grid={0.0025}
        minimum={-0.02}
        maximum={0.12}
        error={error(ManualField.perpetualGrowth)}
        onChange={(v) => onChange(p.copyWith({ perpetualGrowth: v }))}
      />

      <NumericField
        field={ManualField.discountRate}
        label={ManualCopy.label(ManualField.discountRate, lane)}
        explanation={ManualCopy.explanation(ManualField.discountRate, lane)}
        reference={rateRef}
        note={firmNote}
        value={p.discountRate}
        engineValue={engine.discountRate}
        unit="rate"
        step={0.0025}
        grid={0.0025}
        minimum={0.04}
        maximum={0.3}
        error={error(ManualField.discountRate)}
        onChange={(v) => onChange(p.copyWith({ discountRate: v }))}
        forcedChanged={p.ratePath !== engine.ratePath}
        onBackToEngine={() => onChange(p.copyWith({ discountRate: engine.discountRate, ratePath: engine.ratePath }))}
        modes={
          <Modes
            label="Caminho da taxa"
            value={p.ratePath.name}
            options={[
              { value: ManualRatePath.engine.name, label: 'Segue a curva, como no motor' },
              { value: ManualRatePath.constant.name, label: 'Uma taxa só, em todos os anos' },
            ]}
            onChange={(v) => onChange(p.copyWith({ ratePath: ManualRatePath.values.find((x) => x.name === v)! }))}
          />
        }
      />

      <ReinvestmentField m={m} p={p} engine={engine} error={error} onChange={onChange} />

      {p.reinvestment === ManualReinvestment.byReturn && (
        <NewCapitalField m={m} p={p} engine={engine} reference={newCapitalRef} error={error(ManualField.terminalReturn)} onChange={onChange} />
      )}
    </div>
  );
}

function ReinvestmentField(props: {
  m: ManualValuation;
  p: ManualPremises;
  engine: ManualPremises;
  error: (f: ManualField) => string | null;
  onChange: (p: ManualPremises) => void;
}) {
  const { m, p, engine, onChange } = props;
  const lane = m.lane;
  const modes = (
    <Modes
      label="Como a empresa reinveste"
      value={p.reinvestment.name}
      options={[
        { value: ManualReinvestment.byReturn.name, label: 'Pelo retorno, como no motor' },
        { value: ManualReinvestment.fixedFraction.name, label: 'Uma parcela fixa do lucro' },
      ]}
      onChange={(v) => onChange(p.copyWith({ reinvestment: ManualReinvestment.values.find((x) => x.name === v)! }))}
    />
  );
  if (p.reinvestment === ManualReinvestment.fixedFraction) {
    return (
      <NumericField
        field={ManualField.retention}
        label={ManualCopy.label(ManualField.retention, lane)}
        explanation={ManualCopy.explanation(ManualField.retention, lane)}
        reference={`Ponto de partida: a parcela do ano 1 no motor, ${ref('fraction', engine.retention)}. Com ela fixa, o crescimento deixa de depender do retorno, e a perpetuidade é Gordon com a mesma parcela.`}
        value={p.retention}
        engineValue={engine.retention}
        unit="fraction"
        step={0.01}
        grid={0.01}
        minimum={0}
        maximum={0.95}
        error={props.error(ManualField.retention)}
        onChange={(v) => onChange(p.copyWith({ retention: v }))}
        modes={modes}
        forcedChanged
        onBackToEngine={() =>
          onChange(p.copyWith({ reinvestment: engine.reinvestment, returnOnCapital: engine.returnOnCapital, retention: engine.retention }))
        }
      />
    );
  }
  return (
    <NumericField
      field={ManualField.returnOnCapital}
      label={ManualCopy.label(ManualField.returnOnCapital, lane)}
      explanation={ManualCopy.explanation(ManualField.returnOnCapital, lane)}
      reference={
        engine.returnOnCapital > 0
          ? `Motor: ${ref('rate', engine.returnOnCapital)} no ano 1.`
          : 'Motor: sem retorno medido — o motor não reinveste nada para crescer, e o resultado declara isso.'
      }
      value={p.returnOnCapital}
      engineValue={engine.returnOnCapital}
      unit="rate"
      step={0.0025}
      grid={0.0025}
      minimum={0}
      maximum={0.6}
      error={props.error(ManualField.returnOnCapital)}
      onChange={(v) => onChange(p.copyWith({ returnOnCapital: v }))}
      modes={modes}
    />
  );
}

function NewCapitalField(props: {
  m: ManualValuation;
  p: ManualPremises;
  engine: ManualPremises;
  reference: string;
  error: string | null;
  onChange: (p: ManualPremises) => void;
}) {
  const { m, p, engine, onChange } = props;
  const lane = m.lane;
  const own = p.terminalReturn !== null;
  // Ao escolher "outro retorno" sem um medido, o ponto de partida é a taxa
  // mais cinco pontos — uma vantagem que se vê no número, e não zero.
  const starting = engine.terminalReturn ?? m.engineTerminalRate + 0.05;
  const modes = (
    <Modes
      label="Retorno do capital novo na perpetuidade"
      value={own ? 'own' : 'neutral'}
      options={[
        { value: 'neutral', label: 'Igual à taxa: crescer não cria valor' },
        { value: 'own', label: 'Outro retorno' },
      ]}
      onChange={(v) => onChange(p.copyWith({ terminalReturn: v === 'own' ? starting : null }))}
    />
  );
  if (!own) {
    return (
      <FieldCard
        label={ManualCopy.label(ManualField.terminalReturn, lane)}
        explanation={ManualCopy.explanation(ManualField.terminalReturn, lane)}
        changed={engine.terminalReturn !== null}
        error={props.error}
        onBackToEngine={engine.terminalReturn === null ? null : () => onChange(p.copyWith({ terminalReturn: engine.terminalReturn }))}
      >
        {modes}
        <p className="text-caption text-fg-2">{props.reference}</p>
      </FieldCard>
    );
  }
  return (
    <NumericField
      field={ManualField.terminalReturn}
      label={ManualCopy.label(ManualField.terminalReturn, lane)}
      explanation={ManualCopy.explanation(ManualField.terminalReturn, lane)}
      reference={props.reference}
      value={p.terminalReturn!}
      engineValue={engine.terminalReturn ?? Number.NaN}
      unit="rate"
      step={0.0025}
      grid={0.0025}
      minimum={0.02}
      maximum={0.5}
      error={props.error}
      onChange={(v) => onChange(p.copyWith({ terminalReturn: v }))}
      onBackToEngine={() => onChange(p.copyWith({ terminalReturn: engine.terminalReturn }))}
      modes={modes}
    />
  );
}
