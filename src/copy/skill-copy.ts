import { type SkillReading, SkillReading as Skill, TransversalOrdering } from '../core';
import { DomainCopy } from './domain-copy';
import { Fmt } from './fmt';

/**
 * O que a tela de metas diz sobre o prêmio do retorno esperado (itens B1.0 e
 * B1). **A frase sai da medição empacotada**, e não de texto fixo: ela cita o
 * número, e muda quando a medição mudar.
 */
export const SkillCopy = {
  /**
   * A frase do prêmio, ou `null` quando não há o que ressalvar: o prêmio sai
   * do potencial e o potencial está comprovado.
   */
  caveat(reading: SkillReading | null): string | null {
    if (reading === null) {
      return (
        'A habilidade de ordenar ações não veio medida neste aplicativo, e o retorno esperado ' +
        'ficou sem prêmio: é o Ke de cada ativo.'
      );
    }
    const n = (v: number) => Fmt.ratio(v, 2);
    const premium = reading.premiumOrdering;
    if (premium === TransversalOrdering.potential && reading.demonstrated) return null;

    const upside = aboutUpside(reading, n);
    if (premium === null) {
      return (
        'Nenhuma ordenação comprovou habilidade nas coortes de validação, ' +
        `em ${reading.months} meses — nem o potencial do valuation, nem o valor patrimonial ` +
        'sobre o preço, nem o composto dos dois com o lucro sobre o preço. O retorno esperado ' +
        `não leva prêmio: é o Ke de cada ativo. ${upside}`
      );
    }
    const r = reading.orderings.get(premium)!;
    return (
      `O prêmio sobre o Ke sai de ${DomainCopy.ordering(premium)}, que ordenou as ações nas ` +
      `coortes de validação em ${reading.months} meses: correlação de postos de ${n(r.ic)}, ` +
      `t corrigido de ${n(r.overlapT)} contra ${n(r.overlapCritical)} exigido. ${upside}`
    );
  },
};

/** O que a validação mediu do potencial dado o valor patrimonial. */
function aboutUpside(l: SkillReading, n: (v: number) => string): string {
  if (l.demonstrated) {
    return (
      'O potencial do valuation acrescenta ao valor patrimonial sobre o preço: ' +
      `t corrigido de ${n(l.overlapT)} contra ${n(l.overlapCritical)}.`
    );
  }
  const test =
    l.overlapT > l.overlapCritical
      ? 'o que ele acrescenta ao valor patrimonial sobre o preço não passou no Newey-West: ' +
        `t de ${n(l.neweyWestT)}, contra ${n(Skill.neweyWestFloor)} exigido`
      : 'não acrescentou ao valor patrimonial sobre o preço: ' +
        `t corrigido de ${n(l.overlapT)}, contra ${n(l.overlapCritical)} exigido`;
  const icP = l.potentialIc;
  const icB = l.bookToMarketIc;
  const worst =
    icP !== null && icB !== null && icP < icB
      ? ` ordenou pior que ele — correlação de postos de ${n(icP)} contra ${n(icB)} — e`
      : '';
  return `O potencial do valuation sozinho não comprovou saber ordenar ações:${worst} ${test}.`;
}
