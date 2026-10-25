import { type BaseNormalization, ValuationLane, ValuationParameters } from '../core';
import { Fmt } from './fmt';

/**
 * O texto que explica a normalização do lucro de partida.
 *
 * **O núcleo diz o que decidiu, e com que números**; a frase é montada aqui,
 * com a formatação brasileira (decisões 122 e 125). Pedido do orientador em
 * 14/10/2026: entender o porquê das normalizações e a direção de cada uma.
 */
export const NormalizationCopy = {
  /** O nome do retorno da via, como se diz. */
  returnRate(lane: ValuationLane): string {
    return lane === ValuationLane.firm ? 'retorno sobre o capital investido' : 'retorno sobre o patrimônio';
  },

  /** A pergunta que abre a explicação. */
  question(n: BaseNormalization): string {
    switch (n.outcome.name) {
      case 'upward':
        return 'Por que o motor subiu o lucro de partida?';
      case 'downward':
        return 'Por que o motor baixou o lucro de partida?';
      case 'rebuilt':
        return 'Por que o motor reconstruiu o lucro de partida?';
      case 'imposed':
        return 'Por que este fator?';
      default:
        return 'Por que o motor usou o lucro publicado?';
    }
  },

  /** O resumo em duas ou três palavras, para o selo. */
  badge(n: BaseNormalization): string {
    switch (n.outcome.name) {
      case 'upward':
        return `Para cima, ${x(n.factor)}`;
      case 'downward':
        return `Para baixo, ${x(n.factor)}`;
      case 'withinNormal':
        return 'Dentro do normal';
      case 'trend':
        return 'Novo patamar';
      case 'healthLocked':
        return 'Travada pela queda';
      case 'rebuilt':
        return 'Reconstruído do ciclo';
      case 'noCycle':
        return 'Sem ciclo medível';
      default:
        return `Imposto, ${x(n.factor)}`;
    }
  },

  /** A regra, que vale para todo ativo. */
  rule(n: BaseNormalization): string {
    const years = n.windowYears;
    const window = years === null ? '' : `, de ${years.first} a ${years.last}`;
    return (
      'Um ano só pode ter sido um pico ou um vale, e o preço justo é proporcional ao lucro de ' +
      `partida. Por isso o motor compara o ${NormalizationCopy.returnRate(n.lane)} do ` +
      `${n.latestMonths === null ? 'último exercício' : 'ano corrente, anualizado do último ITR,'} com o retorno típico da empresa — a mediana dos ` +
      `${n.cycleWindow.length} exercícios anteriores${window} — e só parte de outro lucro ` +
      'quando os dois destoam.'
    );
  },

  /**
   * O ano do último ponto, dizendo quando ele é o ano corrente anualizado
   * (decisão 153): `2026 (6 meses anualizados)`.
   */
  period(n: BaseNormalization): string {
    const year = String(n.latestYear ?? '');
    const months = n.latestMonths;
    return months === null ? year : `${year} (${months} ${months === 1 ? 'mês anualizado' : 'meses anualizados'})`;
  },

  /** A resposta para este ativo, com os números dele. */
  answer(n: BaseNormalization): string {
    const year = NormalizationCopy.period(n);
    const current = pct(n.latestReturn);
    const typical = pct(n.cycleReturn);
    switch (n.outcome.name) {
      case 'upward':
        return (
          `Em ${year} a empresa rendeu ${current}, abaixo do seu típico de ${typical}. O motor lê o ` +
          'último ano como um vale e parte do lucro que a empresa de hoje teria rendendo o típico: ' +
          `${x(n.factor)} sobre o lucro publicado.`
        );
      case 'downward':
        return (
          `Em ${year} a empresa rendeu ${current}, acima do seu típico de ${typical}. O motor lê o ` +
          'último ano como um pico e parte do lucro que a empresa de hoje teria rendendo o típico: ' +
          `${x(n.factor)} sobre o lucro publicado.`
        );
      case 'withinNormal':
        return (
          `Em ${year} a empresa rendeu ${current}, contra o seu típico de ${typical} — dentro do ` +
          'normal dela. Não há o que corrigir, e a base é o lucro publicado.'
        );
      case 'trend':
        return (
          `${current} em ${year} destoa do típico de ${typical}, mas o retorno vem mudando de ` +
          `patamar ano a ano, e em ${ValuationParameters.trendDriftWindow} anos essa tendência anda ` +
          'mais do que a volta ao típico. O motor lê o último ano como o novo normal, e a base é o ' +
          'lucro publicado.'
        );
      case 'healthLocked':
        return (
          `${current} em ${year} está abaixo do típico de ${typical}, e o motor subiria a base ` +
          `${x(n.rawFactor)}. Não subiu porque o lucro ou o EBITDA caiu ${pct(n.operationalDecline)} ` +
          `em ${ValuationParameters.operationalHealthWindow} anos, mais que o limite de ` +
          `${Fmt.percent(ValuationParameters.maxOperationalDecline, { decimals: 0 })}: quem perdeu ` +
          'mais da metade do resultado mudou de patamar, e trazê-lo de volta ao típico lhe daria ' +
          'um retorno que não vai se repetir. A base é o lucro publicado.'
        );
      case 'rebuilt':
        return (
          `Em ${year} a empresa deu prejuízo (${current}), e não há fator que corrija um lucro ` +
          `negativo. Com o típico positivo (${typical}) e ${pct(n.rebuiltPositiveShare)} da janela ` +
          'no lucro, o motor parte do típico sobre o capital de hoje: a afirmação de que a empresa ' +
          'volta ao que já foi.'
        );
      case 'noCycle':
        return 'A série não tem um retorno típico positivo com que comparar o último ano, e a base é o lucro publicado.';
      default:
        return 'O fator foi imposto de fora, por varredura de diagnóstico.';
    }
  },

  /** O teste de destoar, com os dois critérios, ou `null` quando ele não decidiu. */
  test(n: BaseNormalization): string | null {
    const ratio = n.ratio;
    const z = n.robustZ;
    if (ratio === null || z === null) return null;
    if (['rebuilt', 'noCycle', 'imposed'].includes(n.outcome.name)) return null;
    const byRatio = ratio < ValuationParameters.bandLow || ratio > ValuationParameters.bandHigh;
    const byDistance = z > ValuationParameters.robustZ;
    const verdict = !n.deviates
      ? 'Os dois dentro do normal: não destoou.'
      : byRatio && byDistance
        ? 'Destoou pelos dois critérios.'
        : byRatio
          ? 'Destoou pela razão.'
          : 'Destoou pela distância.';
    return (
      `O teste: o último ano dividido pelo típico dá ${Fmt.ratio(ratio, 2)} — o normal vai de ` +
      `${Fmt.ratio(ValuationParameters.bandLow, 2)} a ${Fmt.ratio(ValuationParameters.bandHigh, 2)} —, ` +
      `e a distância entre os dois é de ${Fmt.ratio(z, 1)} desvios típicos da janela — o normal vai ` +
      `até ${Fmt.ratio(ValuationParameters.robustZ, 1)}. ${verdict}`
    );
  },

  /** A conta da base, ou `null` quando a base é o lucro publicado. */
  account(n: BaseNormalization): string | null {
    const published = n.publishedProfit;
    const base = n.baseProfit;
    if (published === null || base === null) return null;
    switch (n.outcome.name) {
      case 'upward':
      case 'downward':
      case 'imposed': {
        const typical = n.saturated
          ? ''
          : ` — o mesmo que o capital com que a empresa começou ${n.latestYear} rendendo o típico de ${pct(n.cycleReturn)}`;
        return `A conta: ${millions(published)} × ${Fmt.ratio(n.factor, 2)} = ${millions(base)}${typical}.`;
      }
      case 'rebuilt':
        return (
          `A conta: o típico de ${pct(n.cycleReturn)} sobre o capital de hoje dá ${millions(base)}, ` +
          `no lugar do prejuízo de ${millions(published)}.`
        );
      default:
        return null;
    }
  },

  /** O que mais pesou na decisão, além do teste. */
  warnings(n: BaseNormalization): string[] {
    const out: string[] = [];
    if (n.saturated) {
      out.push(
        `Limite: a razão pedia ${x(n.rawFactor)}, e o fator foi limitado a ${x(n.factor)}. Ele fica ` +
          `entre ${Fmt.ratio(ValuationParameters.baseFactorFloor, 2)} e ` +
          `${Fmt.ratio(ValuationParameters.baseFactorCeiling, 2)} porque a normalização corrige um ` +
          'ano, e não inventa uma empresa.',
      );
    }
    if (n.cyclicalPrecedence && n.trendDominates && ['upward', 'downward'].includes(n.outcome.name)) {
      out.push(
        'O retorno tem tendência, mas a empresa é de commodity ou de setor cíclico pesado: ali a ' +
          'alta do ciclo tem cara de tendência, e o ciclo tem precedência (decisão 28).',
      );
    }
    if (n.healthExempt && n.factor > 1) {
      out.push(
        `O lucro ou o EBITDA caiu ${pct(n.operationalDecline)} em ` +
          `${ValuationParameters.operationalHealthWindow} anos, mas em commodity a queda entre pico ` +
          'e vale é do preço do insumo, e não mudança de patamar: a trava que impede subir não se ' +
          'aplica (decisão 30).',
      );
    }
    return out;
  },
};

function pct(v: number | null): string {
  return v === null ? '—' : Fmt.percent(v, { decimals: 1 });
}

function millions(v: number): string {
  return `R$ ${Fmt.ratio(v / 1e6, 1)} mi`;
}

function x(v: number): string {
  return `×${Fmt.ratio(v, 2)}`;
}
