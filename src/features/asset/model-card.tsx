import { ValuationModel, type ValuationResult } from '../../core';
import { DomainCopy, Fmt } from '../../copy';
import { Panel } from '../../ui/card';
import { HintPopover } from '../../ui/hint';
import { Metric, MetricRow } from '../../ui/metric';

/**
 * O modelo aplicado: o método, a taxa que desconta e quanto do preço justo
 * vem da perpetuidade. **Não há nota de confiança** — a decisão 32 mediu que a
 * contagem de ressalvas ordenava ao contrário do retorno realizado.
 */
export function ModelCard({ result }: { result: ValuationResult }) {
  const d = result.diagnostics;
  const firm = result.model === ValuationModel.dcfFcff;
  return (
    <Panel
      title="Modelo aplicado"
      subtitle="Escolhido pelo que os dados sustentam"
      actions={
        <HintPopover
          title="Modelo aplicado"
          entries={[
            {
              term: 'DCF por fluxo da firma',
              meaning:
                'Desconta o caixa da operação ao custo médio ponderado do capital (WACC) e subtrai a dívida líquida: é a via de quem tem dívida relevante no balanço.',
            },
            {
              term: 'DCF sobre lucro distribuível',
              meaning:
                'Desconta o que sobra ao acionista depois de reinvestir, ao custo do capital próprio (Ke): é a via de bancos, seguradoras e de quem a firma não descreve bem.',
            },
            {
              term: 'Peso do terminal',
              meaning:
                'Fração do preço justo que vem da perpetuidade, e não dos dez anos projetados. Quanto maior, mais o número depende de premissa de longo prazo.',
            },
          ]}
        />
      }
    >
      <MetricRow>
        <Metric label="Método" value={DomainCopy.model(result.model)} size="sm" />
        <Metric
          label="Taxa de desconto"
          value={Fmt.percent(result.discountRate)}
          hint={firm ? 'WACC' : 'custo do capital próprio'}
          size="sm"
        />
        {d !== null && d.costOfEquity > 0 && firm && (
          <Metric label="Custo do capital próprio" value={Fmt.percent(d.costOfEquity)} hint="Ke, pelo CAPM" size="sm" />
        )}
        {d !== null && (
          <Metric
            label="Peso do terminal"
            value={Fmt.percent(d.terminalShare, { decimals: 0 })}
            hint="do preço justo vem da perpetuidade"
            size="sm"
            tone={d.terminalShare >= 0.75 ? 'caution' : 'neutral'}
          />
        )}
        {d !== null && (
          <Metric label="Crescimento no ano 1" value={Fmt.percent(d.growthRate, { decimals: 1 })} hint="do lucro de partida" size="sm" />
        )}
      </MetricRow>
    </Panel>
  );
}
