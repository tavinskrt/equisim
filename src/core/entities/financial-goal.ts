import { InvalidInput } from '../failures/failure';
import { err, ok, type Result } from '../failures/result';
import type { Money } from '../value-objects/money';

/**
 * Plano patrimonial declarado pelo usuário.
 *
 * Os quatro parâmetros definem a carteira: aporte inicial, aporte mensal,
 * prazo e valor desejado ao final. A rentabilidade necessária é **derivada**
 * deles, não informada.
 */
export class FinancialGoal {
  /** V₀ — aporte inicial. */
  readonly initialContribution: Money;

  /** PMT — aporte mensal. */
  readonly monthlyContribution: Money;

  /** n — prazo em meses. */
  readonly months: number;

  /** V_f — patrimônio desejado ao final. */
  readonly targetWealth: Money;

  private constructor(args: {
    initialContribution: Money;
    monthlyContribution: Money;
    months: number;
    targetWealth: Money;
  }) {
    this.initialContribution = args.initialContribution;
    this.monthlyContribution = args.monthlyContribution;
    this.months = args.months;
    this.targetWealth = args.targetWealth;
  }

  /**
   * Declara o plano **sem conferir invariante alguma**.
   *
   * O nome é o aviso: quem chama isto assume a conferência. Existe para
   * desserializar documento gravado antes desta validação existir, e montar
   * caso de teste deliberadamente inválido. **No caminho normal, use [create].**
   */
  static unvalidated(args: {
    initialContribution: Money;
    monthlyContribution: Money;
    months: number;
    targetWealth: Money;
  }): FinancialGoal {
    return new FinancialGoal(args);
  }

  /**
   * Constrói o plano conferindo as invariantes que o tornam resolvível.
   *
   * Devolve [InvalidInput] com o campo apontado em `field`, para a interface
   * destacá-lo sem interpretar a mensagem.
   *
   * **Por que aqui e não só no solver.** A entidade circula por toda a
   * aplicação, e quem a recebe não tem como saber se ela passou por validação
   * em algum ponto. Fechar a invariante na construção é o que dispensa cada
   * consumidor de reconferir.
   */
  static create(args: {
    initialContribution: Money;
    monthlyContribution: Money;
    months: number;
    targetWealth: Money;
  }): Result<FinancialGoal> {
    if (args.months <= 0) {
      return err(new InvalidInput('O prazo deve ser de ao menos um mês.', { field: 'months' }));
    }
    if (args.initialContribution.cents < 0 || args.monthlyContribution.cents < 0) {
      return err(new InvalidInput('Os aportes não podem ser negativos.', { field: 'contribution' }));
    }
    if (args.targetWealth.cents <= 0) {
      return err(new InvalidInput('O valor desejado deve ser positivo.', { field: 'targetWealth' }));
    }
    if (args.initialContribution.isZero && args.monthlyContribution.isZero) {
      return err(
        new InvalidInput('Sem aporte inicial nem mensal, não há capital para render.', {
          field: 'contribution',
        }),
      );
    }
    return ok(new FinancialGoal(args));
  }

  /** Capital que o próprio investidor aporta ao longo do plano, sem rendimento algum. */
  get totalContributed(): Money {
    return this.initialContribution.plus(this.monthlyContribution.times(this.months));
  }

  /** A meta é atingível apenas com os aportes, sem qualquer rentabilidade. */
  get reachableWithoutReturn(): boolean {
    return this.targetWealth.lte(this.totalContributed);
  }
}

/** Rentabilidade requerida para o plano. */
export class RequiredReturn {
  /** Taxa mensal, em fração. */
  readonly monthly: number;

  constructor(args: { monthly: number }) {
    this.monthly = args.monthly;
  }

  /**
   * Taxa anual equivalente: `(1 + i)¹² − 1`.
   *
   * Conversão por **composição**, nunca por multiplicação: `i × 12` erra por
   * dezenas de pontos percentuais nas taxas que uma meta agressiva exige.
   */
  get annual(): number {
    return Math.pow(1 + this.monthly, 12) - 1;
  }
}
