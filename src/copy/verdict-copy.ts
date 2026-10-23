import type { ManualValuationRecord, ValuationResult } from '../core';
import { Fmt, type Trend } from './fmt';

/**
 * O veredito em linguagem simples do modo Essencial.
 *
 * **É leitura do número, e não recomendação.** O motor estima um preço justo;
 * o veredito diz, em uma frase, onde o preço de hoje está contra ele e com que
 * cautela ler a distância. Os limiares são de apresentação — não mudam conta
 * nenhuma — e estão declarados na decisão 152.
 */
export const VerdictCopy = {
  /**
   * Distância abaixo da qual preço e preço justo são "parecidos". Dez por
   * cento é menos que a sensibilidade de ±1 p.p. na taxa de desconto produz
   * num DCF típico: dentro dela, o motor não distingue os dois.
   */
  nearBand: 0.1,

  /**
   * Acima disto o número deixa de ser estimativa e vira sintoma — o mesmo
   * limiar da marca ⚠ da carteira: preço justo ao dobro ou à metade quase
   * sempre sai de exercício-base atípico ou de demonstrativo incompleto.
   */
  outlierThreshold: 1.0,

  of(result: ValuationResult): { title: string; sentence: string; tone: Trend; outlier: boolean } {
    const upside = result.upside;
    const outlier = Math.abs(upside) >= VerdictCopy.outlierThreshold;
    const fair = Fmt.money(result.fairValue.reais);
    const distance = Fmt.percent(Math.abs(upside), { decimals: 0 });
    if (outlier) {
      return {
        title: 'Diferença grande demais para ler como precisão',
        sentence:
          `Pelas premissas do motor, a ação valeria ${fair} — ${distance} ${upside > 0 ? 'acima' : 'abaixo'} ` +
          'do preço de hoje. Distâncias acima de 100% quase sempre vêm de um exercício-base atípico ou de ' +
          'um demonstrativo incompleto: confira as premissas e as ressalvas antes de confiar.',
        tone: 'caution',
        outlier,
      };
    }
    if (Math.abs(upside) < VerdictCopy.nearBand) {
      return {
        title: 'Preço perto do preço justo',
        sentence:
          `Pelas premissas do motor, a ação valeria ${fair}, a ${distance} do preço de hoje. ` +
          'Nessa distância, o motor não distingue os dois: a diferença cabe numa mudança pequena de premissa.',
        tone: 'neutral',
        outlier,
      };
    }
    return upside > 0
      ? {
          title: 'Preço abaixo do preço justo do motor',
          sentence:
            `Pelas premissas do motor, a ação valeria ${fair} — ${distance} acima do preço de hoje. ` +
            'É a discordância entre o modelo e o mercado, sem prazo para se realizar, e não um retorno previsto.',
          tone: 'positive',
          outlier,
        }
      : {
          title: 'Preço acima do preço justo do motor',
          sentence:
            `Pelas premissas do motor, a ação valeria ${fair} — ${distance} abaixo do preço de hoje. ` +
            'O mercado paga mais do que as premissas sustentam; isso não diz quando, nem se, o preço vai cair.',
          tone: 'negative',
          outlier,
        };
  },

  /** A linha do valuation do usuário, quando ele confirmou um que discorda do motor (decisão 151). */
  mine(record: ManualValuationRecord, marketToday: number): string {
    const upside = marketToday > 0 ? record.fairValuePerShare / marketToday - 1 : null;
    return (
      `Seu valuation de ${Fmt.date(record.savedAt)}: ${Fmt.money(record.fairValuePerShare)} por ação` +
      (upside === null ? '.' : `, ${Fmt.percent(upside, { decimals: 1, signed: true })} contra o preço de hoje.`)
    );
  },
};
