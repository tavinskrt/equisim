import type { DateTime, FinancialGoal, Portfolio } from '../../core';

/**
 * Um estudo: as duas carteiras e a meta que as motiva.
 *
 * Principal e Reserva vivem no **mesmo documento** porque só fazem sentido
 * juntas — a Reserva existe para alimentar a Principal. Guardá-las separadas
 * exigiria uma chave de ligação e abriria a possibilidade de estado
 * inconsistente entre as duas metades.
 */
export class PortfolioStudy {
  /**
   * Identificador do documento. `null` enquanto o estudo não foi gravado —
   * é o que distingue criação de atualização.
   */
  readonly id: string | null;

  /** Nome do estudo, editável pelo usuário. */
  readonly name: string;

  /** Carteira vigente. */
  readonly principal: Portfolio;

  /** Candidatos a substituição. */
  readonly reserve: Portfolio;

  /** Meta patrimonial. `null` enquanto o usuário não a declarou. */
  readonly goal: FinancialGoal | null;

  /**
   * Instante da última gravação, vindo do servidor. `null` num estudo ainda
   * não persistido.
   */
  readonly updatedAt: DateTime | null;

  constructor(args: {
    id?: string | null;
    name: string;
    principal: Portfolio;
    reserve: Portfolio;
    goal?: FinancialGoal | null;
    updatedAt?: DateTime | null;
  }) {
    this.id = args.id ?? null;
    this.name = args.name;
    this.principal = args.principal;
    this.reserve = args.reserve;
    this.goal = args.goal ?? null;
    this.updatedAt = args.updatedAt ?? null;
  }

  /**
   * Cópia com os campos informados substituídos.
   *
   * **[updatedAt] é sempre preservado**, nunca sobrescrito: quem o define é o
   * servidor na gravação, não o cliente. Passar `goal: null` **remove** a
   * meta; omitir o campo a preserva.
   */
  copyWith(args: {
    id?: string | null;
    name?: string;
    principal?: Portfolio;
    reserve?: Portfolio;
    goal?: FinancialGoal | null;
  }): PortfolioStudy {
    return new PortfolioStudy({
      id: args.id !== undefined ? args.id : this.id,
      name: args.name ?? this.name,
      principal: args.principal ?? this.principal,
      reserve: args.reserve ?? this.reserve,
      goal: args.goal !== undefined ? args.goal : this.goal,
      updatedAt: this.updatedAt,
    });
  }
}

/**
 * Ordena do mais recente para o mais antigo; estudos sem `updatedAt` —
 * gravação ainda não confirmada pelo servidor — vão para o fim.
 */
export function compareStudiesByRecency(a: PortfolioStudy, b: PortfolioStudy): number {
  const left = a.updatedAt;
  const right = b.updatedAt;
  if (left === null && right === null) return 0;
  if (left === null) return 1;
  if (right === null) return -1;
  return right.compareTo(left);
}
