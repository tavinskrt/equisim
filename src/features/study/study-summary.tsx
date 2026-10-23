import { CapmInputs, ExpectedReturn, MarketAnchors, Portfolio, RequiredReturnSolver } from '../../core';
import { Fmt, Lexicon, trendOf } from '../../copy';
import { useAnchors, usePortfolioSignals, usePortfolioValuations, usePremium, useSkill } from '../../app/hooks';
import { useStudy } from '../../app/state/study-store';
import { Card } from '../../ui/card';
import { Skeleton } from '../../ui/feedback';
import { HintPopover } from '../../ui/hint';
import { Metric } from '../../ui/metric';

/**
 * O resumo do estudo: quantos ativos, o **retorno esperado da carteira** e o
 * exigido pela meta.
 *
 * O esperado é o mesmo estimador do cartão da meta — `Ke + z × prêmio`, com
 * `z` da ordenação que a validação escolheu (item B1). **Não usa o preço
 * justo**, nem o do usuário: a régua de quem decide precisa ser a validada.
 */
export function StudySummary() {
  const study = useStudy((s) => s.study);
  const principal = study.principal;
  const valuations = usePortfolioValuations(principal);
  const signals = usePortfolioSignals(principal);
  const skill = useSkill();
  const anchors = useAnchors();
  const premium = usePremium();
  const spot = (anchors.status === 'success' ? anchors.data : MarketAnchors.fallback2026).currentRiskFreeRate;

  let expected: number | null = null;
  let coverage = 0;
  const ordering = skill.status === 'success' ? (skill.data?.premiumOrdering ?? null) : null;
  if (valuations.status === 'success' && valuations.data.size > 0 && signals.status === 'success' && skill.status !== 'pending') {
    expected = ExpectedReturn.forPortfolioOrdered({
      portfolio: principal,
      valuations: valuations.data,
      signals: signals.data,
      ordering,
      spotRiskFree: spot,
      riskPremium: premium.status === 'success' ? premium.data.premium : CapmInputs.defaultMarketPremium,
    });
    coverage = ExpectedReturn.coverage({ portfolio: principal, valuations: valuations.data });
  }
  const loading = !principal.isEmpty && expected === null && valuations.status === 'pending';

  const required = study.goal === null ? null : RequiredReturnSolver.solve(study.goal);
  const requiredAnnual = required !== null && required.isOk ? required.unwrap().annual : null;

  return (
    <Card className="grid grid-cols-2 gap-4 p-4 sm:grid-cols-4 sm:p-5">
      <Metric label="Ativos na Principal" value={`${principal.length} / ${Portfolio.maxAssets}`} />
      <Metric
        label={Lexicon.expected}
        value={loading ? <Skeleton className="h-6 w-20" label="Calculando o retorno esperado" /> : expected === null ? '—' : Fmt.percent(expected, { decimals: 1, signed: true })}
        hint={
          expected === null
            ? 'ao ano, quando houver avaliação'
            : `${ordering === null ? 'Ke dos ativos, sem prêmio' : 'Ke dos ativos + prêmio pela ordenação medida'} · ${Fmt.percent(coverage, { decimals: 0 })} da carteira avaliada`
        }
        // O sinal é contra o CDI, e não contra zero: o estimador é sempre não
        // negativo, e pintar de verde uma carteira que espera menos que a renda
        // fixa inverteria a leitura.
        tone={expected === null ? 'neutral' : trendOf(expected - spot)}
        help={
          <HintPopover
            title={Lexicon.expected}
            intro={
              <>
                O custo do capital próprio (Ke) de cada ativo, pelo CAPM, mais um prêmio só quando uma ordenação provou habilidade nas
                coortes de validação. É ao ano, ponderado pelo peso. A cor compara com o CDI de hoje ({Fmt.percent(spot)} a.a.): acima
                dele, a carteira espera mais que a renda fixa.
              </>
            }
          />
        }
      />
      <Metric
        label={Lexicon.required}
        value={requiredAnnual === null ? '—' : Fmt.percent(requiredAnnual, { decimals: 1 })}
        hint={study.goal === null ? 'defina a meta' : Lexicon.requiredPerYear}
      />
      <Metric label="Reserva" value={String(study.reserve.length)} hint="candidatos" />
    </Card>
  );
}
