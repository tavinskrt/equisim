/**
 * Os pacotes de dados versionados que o build serve, relativos à raiz
 * publicada (`public/` no repositório, a raiz do site no Hosting).
 *
 * Moram em `public/assets/` porque não têm hash no nome: são regerados pelas
 * ferramentas de `tool/` e servidos como estão, com cache próprio (ver
 * `firebase.json`). O JavaScript com hash vai para `/static`.
 */
export const AssetPaths = {
  /**
   * Demonstrações da CVM. Gerado por `tool/cvm-package.ts` e
   * versionado. Ausente, a avaliação segue só com a fonte de
   * mercado, e a ressalva diz isso.
   */
  cvmPackage: 'assets/cvm/documentos.json',

  /** Registro de emissores da B3. */
  b3Registry: 'assets/b3/emissores.json',

  /** Prior transversal do beta. */
  betaPrior: 'assets/mercado/beta_prior.json',

  /** Medianas de múltiplos por grupo de pares. */
  peerMultiples: 'assets/mercado/multiplos_setoriais.json',

  /** Série do prêmio implícito, de onde sai o prêmio de mercado do CAPM. */
  marketPremium: 'assets/mercado/premio_implicito.json',

  /** Composição declarada das units, da FCA da CVM. */
  unitComposition: 'assets/cvm/units.json',

  /** Espécie do controle acionário, da FCA da CVM. */
  shareholderControl: 'assets/cvm/controle.json',

  /** Proventos da B3. */
  cashDividends: 'assets/b3/proventos.json',

  /** Prazo das outorgas. */
  concessionTerms: 'assets/cvm/outorgas.json',

  /** Eventos de capital (itens B28 e B29). */
  capitalEvents: 'assets/cvm/capital.json',

  /** Faixa calibrada. */
  calibratedBand: 'assets/validacao/banda_calibrada.json',

  /** Preço justo ponto no tempo das coortes trimestrais. */
  upsideCohorts: 'assets/validacao/upside_coortes.json',

  /** Leitura da habilidade. */
  skillReading: 'assets/validacao/habilidade.json',

  /** Cotações recentes do Tesouro. */
  treasuryQuotes: 'assets/tesouro/curva.json',

  /** Ativos em recuperação judicial, que a Porta 0 recusa. */
  distressedTickers: 'config/distressed_tickers.json',
} as const;

export type AssetPath = (typeof AssetPaths)[keyof typeof AssetPaths];
