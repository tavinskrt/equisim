/**
 * Falhas de domínio, modeladas como tipos selados.
 *
 * O campo `kind` faz o papel do `sealed` do Dart: um `switch` sobre ele é
 * exaustivo para o compilador, o que impede o padrão clássico de esquecer um
 * caso de erro.
 */
export abstract class Failure {
  /**
   * **Diagnóstico técnico**, não texto de tela.
   *
   * Diz o que falhou com a precisão que a auditoria e o log precisam — quais
   * tickers ficaram sem cotação, qual pesos somaram, quantos pregões
   * sobraram. É a única forma de a falha carregar essa especificidade, e por
   * isso segue em português e legível.
   *
   * **Quem compõe a frase da interface é a camada de apresentação**, a partir
   * do tipo selado e dos campos estruturados de cada variante — ver
   * `failureCopy`, em `src/ui/copy/`. O núcleo não decide hierarquia de texto,
   * tom nem formatação de número: isso é decisão de tela.
   */
  readonly message: string;

  abstract readonly kind: 'InsufficientData' | 'InvalidInput' | 'ComputationFailure' | 'DataQualityFailure';

  protected constructor(message: string) {
    this.message = message;
  }

  /** Nome do tipo, como o `runtimeType` do Dart. */
  get runtimeType(): string {
    return this.kind;
  }

  toString(): string {
    return `${this.kind}: ${this.message}`;
  }
}

/** Dados insuficientes ou ausentes para executar o cálculo. */
export class InsufficientData extends Failure {
  readonly kind = 'InsufficientData' as const;

  /**
   * O que ficou sem dado — normalmente o ticker, para a interface agrupar as
   * falhas por ativo em vez de listar mensagens soltas.
   */
  readonly subject: string | null;

  constructor(message: string, options: { subject?: string | null } = {}) {
    super(message);
    this.subject = options.subject ?? null;
  }
}

/**
 * Unidade da grandeza que uma regra de domínio comparou.
 *
 * **Existe para a apresentação saber escrever o número** (item B21, decisão
 * 122). Sem ela, a tela teria de deduzir o formato pelo nome do campo — o que
 * é acoplamento por convenção de string, e quebra calado quando alguém
 * renomeia o campo.
 */
export enum QuantityUnit {
  /** Fração de um inteiro: `1.005` é 100,5%. */
  fraction = 'fraction',
  /** Contagem de coisas: ativos, meses, pregões. */
  count = 'count',
  /** Reais. */
  currency = 'currency',
}

/** Entrada do usuário viola uma invariante do domínio. */
export class InvalidInput extends Failure {
  readonly kind = 'InvalidInput' as const;

  /** Campo do formulário a destacar, quando a falha é atribuível a um. */
  readonly field: string | null;

  /**
   * Valor medido que produziu a recusa, quando há um número a citar.
   *
   * O domínio diz **quanto**; a apresentação decide como escrever (decisão 59).
   */
  readonly actual: number | null;

  /**
   * O limite que a regra impõe, na mesma unidade de [actual] (item B21,
   * decisão 122).
   */
  readonly limit: number | null;

  /** Unidade de [actual] e [limit]. `null` quando não há número a escrever. */
  readonly unit: QuantityUnit | null;

  constructor(
    message: string,
    options: {
      field?: string | null;
      actual?: number | null;
      limit?: number | null;
      unit?: QuantityUnit | null;
    } = {},
  ) {
    super(message);
    this.field = options.field ?? null;
    this.actual = options.actual ?? null;
    this.limit = options.limit ?? null;
    this.unit = options.unit ?? null;
  }
}

/**
 * O modelo não converge ou a equação não tem solução no domínio aceitável.
 *
 * Distingue-se de [InsufficientData] por não ser corrigível com mais dados: os
 * dados existem, e é o modelo que não se aplica a eles.
 */
export class ComputationFailure extends Failure {
  readonly kind = 'ComputationFailure' as const;

  constructor(message: string) {
    super(message);
  }
}

/**
 * Os dados existem mas não passam no controle de qualidade
 * (ex.: DY calculado divergente do publicado pela fonte).
 */
export class DataQualityFailure extends Failure {
  readonly kind = 'DataQualityFailure' as const;

  /**
   * Desvio medido em fração (`0.12` para 12%), quando o portão de qualidade
   * consegue quantificá-lo.
   */
  readonly observedDeviation: number | null;

  constructor(message: string, options: { observedDeviation?: number | null } = {}) {
    super(message);
    this.observedDeviation = options.observedDeviation ?? null;
  }
}

/** União das variantes, para `switch` exaustivo sobre `kind`. */
export type AnyFailure = InsufficientData | InvalidInput | ComputationFailure | DataQualityFailure;
