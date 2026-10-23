import { type BetaPrior, BetaPriorCodec, type BetaPriorPackage, DateTime } from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/** O prior e a ressalva, quando há o que ressalvar. */
export interface BetaPriorReading {
  readonly prior: BetaPrior | null;
  readonly note: string | null;
}

/**
 * Prior transversal do beta empacotado com o aplicativo (item B11).
 *
 * **Por que vem empacotado.** Resolvê-lo é varrer o universo inteiro — cinco
 * anos de cotação, o histórico de fundamentos e o perfil de cada papel — para
 * avaliar **um** ativo. Sem ele não há beta desalavancado, e o motor cai no
 * beta cru e no WACC estático, que são o recuo das decisões 40 e 41: o
 * caminho de taxas resolvido, a rota derivada com taxas coerentes e a recusa
 * de estrutura nunca agiam em produção. Gerado por
 * `tool/beta-prior-package.ts` e versionado, como o pacote da curva.
 *
 * **Sem pacote, o repositório é transparente**: devolve `null`, e a avaliação
 * segue com o beta cru — o comportamento anterior, declarado na tela.
 */
export class BetaPriorRepository {
  /** Data de referência, para medir a defasagem do pacote. */
  readonly today: () => DateTime;

  /**
   * Defasagem máxima aceita do pacote, em dias.
   *
   * **Um ano, e a folga é medida.** O prior é mediana transversal de betas
   * desalavancados sobre janela de cinco anos: um dia entra e outro sai, e a
   * mediana quase não anda — medido em `beta_prior.md`. O limite existe para
   * que um pacote esquecido por anos não continue passando por atual, e não
   * porque a grandeza expire depressa. Compare-se com os sete dias da curva
   * (decisão 86), que é taxa de um dia.
   */
  static readonly validityDays = 365;

  private readonly pkg: () => Promise<BetaPriorPackage | null>;

  constructor(args: { loadPackage: PackageLoader; today?: () => DateTime }) {
    this.today = args.today ?? (() => DateTime.now());
    this.pkg = memoizedPackage<BetaPriorPackage | null>(args.loadPackage, (json) => BetaPriorCodec.decode(json), null);
  }

  /**
   * O prior e a ressalva, quando há o que ressalvar.
   *
   * A ressalva não é aviso de erro: ela diz **qual motor rodou**. Sem prior, o
   * beta é o cru e as taxas não são resolvidas, e quem lê o preço justo tem de
   * saber disso.
   */
  async reading(): Promise<BetaPriorReading> {
    const p = await this.pkg();
    if (p === null) {
      return {
        prior: null,
        note:
          'O prior transversal do beta não veio no pacote do build: o beta ' +
          'é o da regressão crua, sem encolhimento, e o custo de capital não ' +
          'é resolvido contra a alavancagem da própria projeção.',
      };
    }
    // **Dia civil, e não instante.** A diferença em horas absolutas, no salto
    // do horário de verão, cai uma hora antes ou depois — o bastante para a
    // validade valer 364 ou 366 dias conforme a época. É a mesma correção que
    // `MacroRepositoryImpl.coversStart` já traz.
    const now = this.today();
    const days = DateTime.utc(now.year, now.month, now.day).difference(
      DateTime.utc(p.generatedAt.year, p.generatedAt.month, p.generatedAt.day),
    ).inDays;
    if (days > BetaPriorRepository.validityDays) {
      return {
        prior: null,
        note:
          `O prior transversal do beta é de ${p.generatedAt.toIso8601String().substring(0, 10)}, mais de ` +
          `${BetaPriorRepository.validityDays} dias atrás: não foi usado, e o beta é o da regressão crua.`,
      };
    }
    return { prior: p.prior, note: null };
  }
}
