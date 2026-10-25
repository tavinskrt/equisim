import { AlertTriangle, Ban } from 'lucide-react';

import { type ManualValuationRecord, type Ticker } from '../../core';
import { DomainCopy, FailureCopy, Fmt, trendOf, VerdictCopy } from '../../copy';
import { useValuation } from '../../app/hooks';
import { Amount } from '../../ui/amount';
import { Skeleton } from '../../ui/feedback';
import { Tooltip } from '../../ui/tooltip';

/**
 * A célula de potencial: o número, **o preço justo que o originou** e a marca
 * de ressalva. Mostrar o preço justo embaixo é o que transforma "+447%" de
 * número solto em afirmação verificável.
 *
 * Com valuation do usuário (decisão 151), o preço justo é o dele, marcado
 * "seu", e o potencial é contra a cotação **de hoje**.
 */
export function PotentialCell({ ticker, mine }: { ticker: Ticker; mine: ManualValuationRecord | null }) {
  const valuation = useValuation(ticker);
  const result = valuation.status === 'success' && valuation.data.isOk ? valuation.data.unwrap() : null;
  const refused = valuation.status === 'success' && valuation.data.isErr ? valuation.data.failureOrNull : null;
  const market = result?.marketPrice.reais ?? mine?.marketPrice ?? null;
  const isUser = mine !== null && market !== null && market > 0;

  if (valuation.status === 'pending' && !isUser) {
    return (
      <span className="flex flex-col items-end gap-1" role="status" aria-label="Calculando o potencial">
        <Skeleton className="h-4 w-12" />
        <Skeleton className="h-3 w-20" />
      </span>
    );
  }
  if (refused !== null && !isUser) {
    return (
      <Tooltip content={FailureCopy.of(refused)}>
        <span tabIndex={0} className="inline-flex items-center gap-1 text-caption text-blocked">
          <Ban aria-hidden className="size-3" />
          sem preço justo
        </span>
      </Tooltip>
    );
  }
  const fairValue = isUser ? mine.fairValuePerShare : (result?.fairValue.reais ?? null);
  const upside = isUser ? mine.fairValuePerShare / market - 1 : (result?.upside ?? null);
  if (upside === null) return <Amount tone="blocked">—</Amount>;

  const outlier = Math.abs(upside) >= VerdictCopy.outlierThreshold;
  const warnings = result !== null && result.warnings.length > 0;
  // Potencial fora da banda vira ressalva, não perda: âmbar diz "olhe as
  // premissas antes de confiar"; vermelho diria "caiu".
  const tone = outlier ? 'caution' : trendOf(upside);

  let tip: string;
  if (isUser) {
    tip =
      `Distância entre o preço de mercado e o seu preço justo, do valuation que você confirmou em ${Fmt.date(mine.savedAt)}.` +
      (result !== null ? ` O preço justo do motor é ${Fmt.money(result.fairValue.reais)}, e é ele que a validação mede.` : '') +
      ' Não é previsão de retorno, e não há prazo para se realizar.';
  } else {
    tip =
      `Distância entre o preço de mercado e o preço justo estimado${result === null ? '' : ` por ${DomainCopy.model(result.model)}`}. ` +
      'Não é previsão de retorno: só se realiza se o mercado convergir para essa estimativa, e não há prazo para isso.';
  }
  if (outlier) {
    tip +=
      ' Diferença acima de 100%: quase sempre vem de um exercício-base atípico ou de demonstrativo incompleto. Abra o Raio-X para ver as premissas e os avisos.';
  } else if (warnings) {
    tip += ' Esta avaliação tem ressalvas. Abra o Raio-X para lê-las.';
  }

  return (
    <Tooltip content={tip}>
      <span tabIndex={0} className="flex flex-col items-end">
        <span className="flex items-center gap-1">
          {(outlier || warnings) && <AlertTriangle aria-label="com ressalva" className="size-3 text-caution" />}
          <Amount tone={tone} className="text-body-sm font-semibold">
            {Fmt.percent(upside, { decimals: 0, signed: true })}
          </Amount>
        </span>
        {fairValue !== null && (
          <span className="num text-caption text-fg-3">
            {isUser ? 'seu' : 'justo'} {Fmt.money(fairValue)}
          </span>
        )}
      </span>
    </Tooltip>
  );
}
