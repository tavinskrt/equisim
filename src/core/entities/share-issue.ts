import type { DateTime } from '../lang/date-time';
import type { Money } from '../value-objects/money';

/**
 * Uma emissão de ações **por valor**, como o Formulário de Referência da CVM a
 * declara (item B28).
 *
 * Subscrição pública ou particular, incorporação, conversão de título,
 * exercício de opção ou de bônus de subscrição: tudo o que põe ações novas em
 * circulação **trazendo alguma coisa em troca**. **Bonificação não é emissão
 * aqui**: ela redistribui capital que já estava no balanço, e quem a trata é o
 * ajuste dos eventos de ações ([ShareEvent]).
 *
 * **Por que a cascata precisa disto.** O capital próprio sai do último balanço
 * publicado, e o divisor é a contagem que forma a cotação de hoje. Uma emissão
 * entre as duas datas entra no divisor e não entra no patrimônio: o preço
 * justo por papel saía subavaliado na proporção do capital captado.
 */
export class ShareIssue {
  /** Data da emissão — ou da deliberação, quando o formulário não traz a da emissão. */
  readonly date: DateTime;

  /** Valor total da emissão, em centavos inteiros. */
  readonly amount: Money;

  /** Ações emitidas, na base do dia da emissão — inteiras. Informativo. */
  readonly shares: number;

  /**
   * `true` quando o valor é o **da emissão**, declarado por ela — o quadro de
   * aumentos do Formulário de Referência.
   *
   * `false` quando é só a **variação do capital integralizado** entre duas
   * versões do formulário, que é o que resta desde que a CVM tirou o quadro de
   * aumentos, em 2023. **A cascata não a soma**: diz que ela existe e quanto o
   * preço justo mudaria se fosse emissão por valor.
   */
  readonly declared: boolean;

  constructor(args: { date: DateTime; amount: Money; shares: number; declared?: boolean }) {
    this.date = args.date;
    this.amount = args.amount;
    this.shares = args.shares;
    this.declared = args.declared ?? true;
  }

  /** Valor e quantidade positivos. */
  get isUsable(): boolean {
    return this.amount.isPositive && this.shares > 0;
  }
}
