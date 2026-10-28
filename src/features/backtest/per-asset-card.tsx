import type { AssetPerformance, BacktestOutcome } from '../../core';
import { Fmt, trendOf } from '../../copy';
import { Card, Divider, SectionHeader } from '../../ui/card';
import { cn } from '../../ui/cn';
import { HintPopover } from '../../ui/hint';
import { TickerLogo } from '../../ui/ticker-logo';
import { toneText } from '../../ui/tone';
import { useAssetOverlay } from '../shell/use-asset-overlay';
import { perAssetGlossary } from './glossary';
import { PortfolioBadge, PortfolioColors } from './portfolio-badge';

/** Ativos de uma carteira, do melhor para o pior retorno no período. */
export function ranked(outcome: BacktestOutcome | null): AssetPerformance[] {
  if (outcome === null) return [];
  return [...outcome.perAsset.values()].sort((a, b) => b.totalReturn - a.totalReturn);
}

const pct1 = (v: number) => Fmt.percent(v, { decimals: 1, signed: true });

/**
 * Nomeia o par que a ordenação põe lado a lado: o **pior ativo detido** (fim
 * da Principal) e o **melhor candidato** (topo da Reserva). **Não promete
 * resultado** — a simulação não roda a carteira trocada. E o candidato que não
 * superou ninguém também é dito: uma observação que só fala a favor deixa de
 * ser observação.
 */
export function adjacentPairSentence(worstHolding: AssetPerformance, bestCandidate: AssetPerformance): string {
  const difference = (bestCandidate.totalReturn - worstHolding.totalReturn) * 100;
  return difference > 0
    ? `No encontro das duas listas: ${worstHolding.ticker.value} é o pior retorno da Principal (${pct1(worstHolding.totalReturn)}) e ${bestCandidate.ticker.value} o melhor da Reserva (${pct1(bestCandidate.totalReturn)}) — ${Fmt.points(difference)} de diferença.`
    : `Nenhum candidato da Reserva superou o pior ativo da Principal no período: ${worstHolding.ticker.value} rendeu ${pct1(worstHolding.totalReturn)} e ${bestCandidate.ticker.value}, o melhor da Reserva, ${pct1(bestCandidate.totalReturn)}.`;
}

/**
 * **Desempenho por ativo** das duas carteiras num cartão só, cada uma do
 * melhor ao pior retorno: o pior ativo detido fica no fim da primeira lista e o
 * melhor candidato no topo da segunda — encostados.
 */
export function PerAssetCard({ principal, reserve }: { principal: BacktestOutcome | null; reserve: BacktestOutcome | null }) {
  const principalAssets = ranked(principal);
  const reserveAssets = ranked(reserve);
  if (principalAssets.length === 0 && reserveAssets.length === 0) return null;
  const hasBoth = principalAssets.length > 0 && reserveAssets.length > 0;

  return (
    <Card className="p-4 sm:p-5">
      <SectionHeader
        title="Desempenho por ativo"
        subtitle={hasBoth ? 'Do melhor ao pior retorno em cada carteira' : 'A deriva de peso é sinal de decisão, não defeito'}
        actions={
          <HintPopover
            title="Desempenho por ativo"
            intro="Cada linha é um ativo dentro da sua carteira, do melhor ao pior retorno no período. A Reserva guarda candidatos a entrar na Principal: com as duas listas ordenadas, o pior ativo detido fica no fim da primeira e o melhor candidato no topo da segunda."
            entries={perAssetGlossary}
            size="md"
          />
        }
      />
      {principalAssets.length > 0 && <AssetGroup label="Principal" color={PortfolioColors.principal} assets={principalAssets} />}
      {hasBoth && (
        <>
          <Divider className="my-3" />
          {/* A frase mora ENTRE os grupos porque é a junção que ela descreve. */}
          <p className="text-body-sm text-fg-2">{adjacentPairSentence(principalAssets[principalAssets.length - 1]!, reserveAssets[0]!)}</p>
          <p className="mt-1 text-caption text-fg-3">A simulação não roda a carteira trocada — a distância é o que os retornos do período dizem, não recomendação de troca.</p>
        </>
      )}
      {reserveAssets.length > 0 && <AssetGroup label="Reserva" color={PortfolioColors.reserve} assets={reserveAssets} className={hasBoth ? 'mt-3' : undefined} />}
    </Card>
  );
}

function AssetGroup(props: { label: string; color: string; assets: readonly AssetPerformance[]; className?: string }) {
  const { open } = useAssetOverlay();
  return (
    <div className={cn('mt-4', props.className)}>
      <PortfolioBadge name={props.label} color={props.color} />
      <table className="mt-1 w-full text-body-sm">
        <caption className="sr-only">Desempenho dos ativos da {props.label}</caption>
        <thead className="sr-only">
          <tr>
            <th scope="col">Ativo</th>
            <th scope="col">Peso alvo e atual</th>
            <th scope="col">Retorno e deriva</th>
          </tr>
        </thead>
        <tbody>
          {props.assets.map((a) => (
            <tr key={a.ticker.value} className="border-b border-divider last:border-0">
              <th scope="row" className="w-24 py-2.5 pr-3 text-left align-top sm:w-28">
                <button
                  type="button"
                  onClick={() => open(a.ticker)}
                  className="-mx-1 inline-flex min-h-11 items-center gap-1.5 rounded px-1 text-left font-semibold text-fg hover:text-brand sm:min-h-0"
                  aria-label={`Abrir o Raio-X de ${a.ticker.value}`}
                >
                  <TickerLogo ticker={a.ticker} size="sm" />
                  <span>{a.ticker.value}</span>
                </button>
              </th>
              <td className="py-2.5 align-top">
                <p className="num text-caption text-fg-2">
                  alvo {Fmt.percent(a.targetWeight.value, { decimals: 1 })} → atual {Fmt.percent(a.currentWeight, { decimals: 1 })}
                </p>
                <WeightBar target={a.targetWeight.value} current={a.currentWeight} color={props.color} />
                <p className="num mt-1 truncate text-caption text-fg-3">
                  {a.shares.toLocaleString('pt-BR')} {a.shares === 1 ? 'ação' : 'ações'} · {Fmt.money(a.invested.reais)} destinados
                </p>
              </td>
              <td className="py-2.5 pl-3 text-right align-top whitespace-nowrap">
                <p className={cn('num font-semibold', toneText[trendOf(a.totalReturn)])}>{pct1(a.totalReturn)}</p>
                <p className="num text-caption text-fg-3">{Fmt.points(a.drift)}</p>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * O peso atual em barra, com o alvo como marca vertical: a deriva é a
 * distância entre o fim da barra e a marca. Na cor da carteira — deriva não é
 * alerta, e as cores de estado ficam reservadas para estado.
 */
function WeightBar({ target, current, color }: { target: number; current: number; color: string }) {
  const clamp = (v: number) => Math.min(1, Math.max(0, v)) * 100;
  return (
    <div className="relative mt-1.5 h-1.5 rounded-full bg-divider" aria-hidden>
      <div className="absolute inset-y-0 left-0 rounded-full" style={{ width: `${clamp(current)}%`, background: color }} />
      <div className="absolute -inset-y-1 w-0.5 rounded-full bg-fg" style={{ left: `calc(${clamp(target)}% - 1px)` }} />
    </div>
  );
}
