import {
  CapmInputs,
  DateTime,
  ImpliedPremiumCodec,
  type ImpliedPremiumPackage,
  MarketPremiumSource,
} from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/** O prêmio, de onde ele veio e a ressalva, quando há o que ressalvar. */
export interface MarketPremiumReading {
  readonly premium: number;
  readonly source: MarketPremiumSource;
  readonly note: string | null;
}

/**
 * O prêmio de risco de mercado do CAPM, da série do prêmio implícito
 * empacotada com o aplicativo (decisão 142).
 *
 * **Por que vem empacotado.** O prêmio implícito iguala o valor de mercado
 * somado das companhias listadas ao dinheiro que elas distribuem — somar a
 * bolsa inteira, os proventos de doze meses de cada companhia e a contagem de
 * ações de cada data para avaliar **um** ativo não cabe no aplicativo. A série
 * trimestral é medida por `tool/implied-premium.ts` e versionada; a média de
 * dez anos, que é o prêmio, sai dela aqui, pelo núcleo.
 *
 * **Sem pacote, o prêmio é o parametrizado de 5,5%** — o anterior à decisão
 * 142 —, e a ressalva diz isso. Diferente do prior do beta, o pacote velho
 * continua valendo: a média de dez anos anda devagar (um trimestre a mais move
 * um quadragésimo dela), e trocá-la pelos 5,5% seria um salto muito maior que
 * a defasagem. A ressalva só diz de quando ela é.
 */
export class MarketPremiumRepository {
  /** Data de referência, para medir a defasagem do pacote. */
  readonly today: () => DateTime;

  /**
   * Defasagem a partir da qual a ressalva aparece, em dias.
   *
   * **Seis meses**: o pacote ganha um trimestre a cada três meses, e com dois
   * trimestres sem regravação a média já deixou de ser a da série publicada.
   */
  static readonly daysWithoutCaveat = 183;

  private readonly pkg: () => Promise<ImpliedPremiumPackage | null>;

  constructor(args: { loadPackage: PackageLoader; today?: () => DateTime }) {
    this.today = args.today ?? (() => DateTime.now());
    this.pkg = memoizedPackage<ImpliedPremiumPackage | null>(
      args.loadPackage,
      (json) => ImpliedPremiumCodec.decode(json),
      null,
    );
  }

  async reading(): Promise<MarketPremiumReading> {
    const noPackage: MarketPremiumReading = {
      premium: CapmInputs.defaultMarketPremium,
      source: MarketPremiumSource.parameterized,
      note:
        'A série do prêmio implícito não veio no pacote do build: o ' +
        'prêmio de mercado é o parametrizado de 5,5%, e não a média de dez ' +
        'anos do prêmio implícito no preço da bolsa (decisão 142).',
    };
    const p = await this.pkg();
    if (p === null) return noPackage;
    // **Dia civil, e não instante**, pelo mesmo motivo do prior do beta: no
    // salto do horário de verão a diferença em horas erra um dia, e a data do
    // pacote é um dia em UTC.
    const now = this.today();
    const day = DateTime.utc(now.year, now.month, now.day);
    // A média é a da data do pacote. Calculada até hoje, com o pacote
    // defasado, a janela perderia os trimestres antigos sem ganhar os novos.
    const mean = p.normalizedAt(day.isBefore(p.generatedAt) ? day : p.generatedAt);
    if (mean === null) return noPackage;
    const days = day.difference(p.generatedAt).inDays;
    if (days > MarketPremiumRepository.daysWithoutCaveat) {
      return {
        premium: mean,
        source: MarketPremiumSource.impliedNormalized,
        note:
          'O prêmio de mercado é a média de dez anos do prêmio implícito ' +
          `medida em ${p.generatedAt.toIso8601String().substring(0, 10)}, mais ` +
          `de ${MarketPremiumRepository.daysWithoutCaveat} dias atrás: os trimestres seguintes ainda não ` +
          'entraram nela.',
      };
    }
    return { premium: mean, source: MarketPremiumSource.impliedNormalized, note: null };
  }
}
