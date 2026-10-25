import type { FeasibilityVerdict } from '../core';
import { Fmt } from './fmt';

/**
 * Compõe, para a tela, a frase que explica o veredito de viabilidade.
 *
 * O núcleo devolve `FeasibilityReason` mais os números, e a decisão de texto
 * fica onde ela é revisada junto do resto da interface.
 */
export const FeasibilityCopy = {
  of(verdict: FeasibilityVerdict): string {
    const rate = verdict.requiredAnnualRate;
    const required = rate === null ? '—' : Fmt.percent(rate, { decimals: 2 });
    const cdi = Fmt.percent(verdict.anchors.riskFreeCagr, { decimals: 2 });
    const market = Fmt.percent(verdict.anchors.marketCagr, { decimals: 2 });
    const years = verdict.anchors.observedYears;

    switch (verdict.reason.name) {
      case 'unsolvable':
        return 'O plano informado não tem solução: revise prazo, aportes e valor desejado.';
      case 'contributionsAlreadySuffice':
        return 'Os aportes sozinhos já superam a meta: não é necessária rentabilidade alguma.';
      case 'belowRiskFree':
        return (
          `A meta exige ${required} a.a., abaixo do CDI (${cdi} a.a. nos últimos ${years} anos). ` +
          'Ela é atingível em renda fixa, sem correr risco de mercado.'
        );
      case 'withinMarket':
        return `A meta exige ${required} a.a., dentro do retorno histórico do Ibovespa (${market} a.a.).`;
      case 'aboveMarket':
        return (
          `A meta exige ${required} a.a., acima do retorno histórico do Ibovespa (${market} a.a.). ` +
          'Depende de superar o mercado de forma consistente, o que é historicamente pouco frequente.'
        );
      case 'farAboveMarket':
        return (
          `A meta exige ${required} a.a., mais que o dobro do retorno histórico do Ibovespa ` +
          `(${market} a.a.). Revise prazo, aporte ou valor desejado.`
        );
      default: {
        // beyondAnyReference: o caso extremo cita o múltiplo — "3,2 vezes"
        // informa mais que "muito acima".
        const multiple = verdict.marketMultiple;
        const times =
          multiple === null ? '' : ` — ${Fmt.ratio(multiple)} vezes o retorno histórico do Ibovespa (${market} a.a.)`;
        return (
          `A meta exige ${required} a.a.${times}. Nenhuma carteira diversificada sustentou esse ` +
          'patamar na janela observada. Ajuste prazo, aporte mensal ou valor desejado.'
        );
      }
    }
  },
};
