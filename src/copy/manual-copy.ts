import {
  DcfCalculator,
  type Failure,
  InvalidInput,
  type ManualField,
  type ManualNotice,
  ValuationLane,
} from '../core';
import { FailureCopy } from './failure-copy';
import { Fmt } from './fmt';

/**
 * O texto da edição do valuation (decisão 147).
 *
 * **O núcleo diz o que aconteceu; a tela diz como se lê** — a separação das
 * decisões 122 e 125. Os avisos chegam como `ManualNoticeKind` com os anos, e
 * as recusas como `InvalidInput` com o campo, o medido e o limite.
 */
export const ManualCopy = {
  /** O nome do campo, na via da avaliação. */
  label(field: ManualField, lane: ValuationLane): string {
    const firm = lane === ValuationLane.firm;
    switch (field.name) {
      case 'baseProfit':
        return firm ? 'Lucro operacional de partida' : 'Lucro líquido de partida';
      case 'growth':
        return 'Crescimento nos primeiros anos';
      case 'discountRate':
        return 'Taxa de desconto';
      case 'perpetualGrowth':
        return 'Crescimento na perpetuidade';
      case 'returnOnCapital':
        return firm ? 'Retorno sobre o capital investido' : 'Retorno sobre o patrimônio';
      case 'retention':
        return 'Parcela do lucro reinvestida';
      default:
        return 'Retorno do capital novo';
    }
  },

  /** O que o campo é, em uma ou duas frases para quem não sabe finanças. */
  explanation(field: ManualField, lane: ValuationLane): string {
    const firm = lane === ValuationLane.firm;
    switch (field.name) {
      case 'baseProfit':
        return firm
          ? 'O lucro da operação depois do imposto e antes dos juros (NOPAT). A dívida entra depois, no que sobra ao acionista.'
          : 'O lucro do ano de onde a projeção parte.';
      case 'growth':
        return 'Quanto o lucro cresce no ano 1. Daí em diante, o caminho escolhido abaixo decide.';
      case 'discountRate':
        return 'Quanto o acionista exige por ano para ficar com a ação — o custo do capital próprio. Traz cada fluxo futuro a valor de hoje.';
      case 'perpetualGrowth':
        return 'Quanto o lucro cresce depois do ano 10, para sempre.';
      case 'returnOnCapital':
        return firm
          ? 'Quanto cada real investido na operação rende por ano. É dele que sai quanto do lucro precisa ser reinvestido para crescer; até o ano 10 ele converge ao custo médio do capital do motor.'
          : 'Quanto cada real do patrimônio rende por ano. É dele que sai quanto do lucro precisa ser reinvestido para crescer; até o ano 10 ele converge à taxa de desconto.';
      case 'retention':
        return 'A mesma parcela em todos os anos e na perpetuidade. O resto vai ao acionista.';
      default:
        return 'Quanto rende o dinheiro que a empresa reinveste depois do ano 10. Igual à taxa, crescer não cria valor — é o que o motor supõe sem vantagem competitiva comprovada.';
    }
  },

  /** Uma lista de anos como se diz: «no ano 3», «nos anos 3 e 4», «do ano 2 ao 10». */
  years(years: readonly number[]): string {
    if (years.length === 0) return '';
    if (years.length === 1) return `no ano ${years[0]}`;
    const first = years[0]!;
    const last = years[years.length - 1]!;
    if (last - first === years.length - 1 && years.length > 2) return `do ano ${first} ao ${last}`;
    return `nos anos ${years.slice(0, -1).join(', ')} e ${last}`;
  },

  /** O aviso, como frase. */
  warning(n: ManualNotice): string {
    switch (n.kind.name) {
      case 'confinedGrowth':
        return (
          `${capitalize(ManualCopy.years(n.years))}, o crescimento ficou abaixo do que você pediu: ` +
          'com o retorno sobre o capital desses anos, crescer mais exigiria reinvestir mais de 95% ' +
          'do lucro, e o motor não deixa. Suba o retorno ou escolha reinvestir uma parcela fixa.'
        );
      case 'negativeFlow':
        return (
          `${capitalize(ManualCopy.years(n.years))}, o fluxo do acionista é negativo: a empresa ` +
          'reinveste, ou paga de dívida, mais do que lucra, e precisaria de dinheiro de fora.'
        );
      case 'perpetualConcession':
        return (
          'Esta empresa é concessão: no motor, o excedente sobre o capital acaba no fim do contrato. ' +
          'Com a perpetuidade que você escolheu, ele passa a durar para sempre.'
        );
      default:
        return (
          'Com o capital novo rendendo a própria taxa, o crescimento na perpetuidade quase não muda ' +
          'o valor da perpetuidade — ele só guia o crescimento dos dez anos. Para ele pesar, dê ao ' +
          'capital novo um retorno diferente da taxa.'
        );
    }
  },

  /** A recusa da conta, como frase. A grandeza vem do núcleo, e o formato é daqui. */
  refusal(f: Failure): string {
    if (!(f instanceof InvalidInput)) return FailureCopy.of(f);
    switch (f.field) {
      case 'baseProfit':
        return 'O lucro de partida precisa ser positivo: o fluxo descontado parte dele.';
      case 'retention':
        return 'A parcela reinvestida precisa ficar entre 0% e 100%: reinvestir tudo para sempre não deixa nada ao acionista.';
      case 'terminalReturn':
        return 'O retorno do capital novo precisa ser positivo.';
      case 'perpetualGrowth':
        if (f.limit === -1) return 'Um crescimento de −100% ou menos zera o lucro.';
        return (
          'A taxa de desconto da perpetuidade precisa superar o crescimento perpétuo em pelo menos ' +
          `${Fmt.ratio((f.limit ?? DcfCalculator.minimumSpread) * 100, 1)} ponto percentual — a margem está em ` +
          `${Fmt.ratio((f.actual ?? 0) * 100, 2)}. Com elas próximas ou invertidas, a perpetuidade não tem valor finito.`
        );
      case 'growth':
        if (f.limit === -1) return 'Um crescimento de −100% ou menos zera o lucro.';
        return FailureCopy.of(f);
      case 'discountRate':
        return 'A taxa de desconto precisa ser positiva em todos os anos.';
      default:
        return FailureCopy.of(f);
    }
  },
};

function capitalize(s: string): string {
  return s.length === 0 ? s : `${s[0]!.toUpperCase()}${s.substring(1)}`;
}
