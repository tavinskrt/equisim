import { EligibilityGate } from '../../core';
import { Fmt } from '../../copy';
import { Card } from '../../ui/card';

/**
 * **A Porta 0**, explicada antes da escolha: o motor só avalia o que a
 * calibragem dele cobre. Os parâmetros das guardas foram calibrados sobre
 * ativos líquidos, e extrapolá-los em silêncio inflaria o preço justo
 * justamente onde o beta sai viesado para baixo (decisão 25).
 */
export function PortaZeroExplainer({ className }: { className?: string }) {
  return (
    <Card className={`bg-sunken p-4 ${className ?? ''}`}>
      <p className="text-body-sm font-semibold text-fg">O que o motor avalia (Porta 0)</p>
      <ul className="mt-2 space-y-1.5 text-body-sm text-fg-2">
        <li>
          • Liquidez: volume financeiro diário mediano de ao menos{' '}
          <span className="num font-semibold text-fg">{Fmt.compactMoney(EligibilityGate.minAverageDailyTradedValue)}</span> nos
          últimos {EligibilityGate.liquidityWindowDays} pregões. Pregão sem negócio gera retorno zero falso, que puxa o beta
          para baixo e infla o preço justo.
        </li>
        <li>
          • Histórico: ao menos <span className="num font-semibold text-fg">{EligibilityGate.minPublishedPeriods}</span> exercícios
          publicados — o mínimo para os testes de ciclo e de tendência terem poder.
        </li>
        <li>• Patrimônio líquido positivo em pelo menos um dos dois últimos exercícios.</li>
        <li>• Fora de recuperação judicial ou extrajudicial.</li>
      </ul>
      <p className="mt-2 text-caption text-fg-3">
        Fundos imobiliários estão fora do escopo. Um ativo fora da Porta 0 entra na carteira e no backtest, mas fica sem preço
        justo.
      </p>
    </Card>
  );
}
