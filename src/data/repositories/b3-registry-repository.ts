import {
  Asset,
  type B3Classification,
  type B3Issuer,
  B3RegistryCodec,
  type FundamentalsRepository,
  type FundamentalsSnapshot,
  ok,
  OfficialShareCount,
  type Result,
  Sector,
  type Ticker,
} from '../../core';
import { memoizedPackage, type PackageLoader } from './package-loader';

/**
 * Registro de emissores da B3 empacotado com o aplicativo (item A3.3).
 *
 * Dá à ponte por papel a **contagem oficial de ações** — o árbitro que as duas
 * contagens da fonte de preços não tinham (decisão 83). Gerado por
 * `tool/b3-package.ts` e versionado, como o pacote da CVM.
 *
 * **Sem pacote, o repositório é transparente**: sem contagem oficial, a ponte
 * segue a regra da fonte, que é a de antes.
 */
export class B3RegistryRepository {
  private readonly issuers: () => Promise<Map<string, B3Issuer>>;

  constructor(args: { loadPackage: PackageLoader }) {
    this.issuers = memoizedPackage(args.loadPackage, (json) => B3RegistryCodec.decodePackage(json), new Map());
  }

  /**
   * Contagem oficial do emissor de [ticker], ou `null`.
   *
   * O emissor é a raiz de quatro letras: `PETR3` e `PETR4` são a mesma
   * companhia, e a contagem é o total das classes.
   */
  async officialSharesFor(ticker: Ticker): Promise<OfficialShareCount | null> {
    const t = ticker.value;
    if (t.length < 4) return null;
    const e = (await this.issuers()).get(t.substring(0, 4));
    const total = e?.totalShares ?? null;
    if (e === undefined || total === null) return null;
    return new OfficialShareCount({ total, asOf: e.consultedOn });
  }

  /** Classificação setorial oficial do emissor de [ticker], ou `null` (item A5, decisão 87). */
  async classificationFor(ticker: Ticker): Promise<B3Classification | null> {
    const t = ticker.value;
    if (t.length < 4) return null;
    return (await this.issuers()).get(t.substring(0, 4))?.classification ?? null;
  }
}

/**
 * Perfil com a classificação setorial **oficial da B3**, sobre o perfil de
 * outra fonte (item A5, decisão 87).
 *
 * **A B3 arbitra o setor; o resto do perfil segue da fonte.** O nome continua
 * o da fonte de preços. Onde a B3 não classifica o emissor, o perfil passa
 * intacto — recuo para a taxonomia da fonte, que é a de antes.
 *
 * **E a classificação sobrevive à falha do perfil.** A Porta 1 depende do
 * setor, e o setor oficial está no pacote: um perfil que a fonte não entregou
 * não pode mandar um banco para a via da firma. Sem o nome, o ativo leva o
 * próprio código.
 */
export class OfficialSectorFundamentalsRepository implements FundamentalsRepository {
  /** Fonte do histórico, do universo e do nome. */
  readonly inner: FundamentalsRepository;

  /** De onde vem a classificação. */
  readonly classification: (ticker: Ticker) => Promise<B3Classification | null>;

  constructor(args: {
    inner: FundamentalsRepository;
    classification: (ticker: Ticker) => Promise<B3Classification | null>;
  }) {
    this.inner = args.inner;
    this.classification = args.classification;
  }

  history(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    return this.inner.history(ticker);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.inner.universe();
  }

  async profile(ticker: Ticker): Promise<Result<Asset>> {
    const profile = await this.inner.profile(ticker);
    let official: B3Classification | null;
    try {
      official = await this.classification(ticker);
    } catch {
      return profile;
    }
    if (official === null) return profile;
    const sector = new Sector({ key: official.sectorKey, label: official.sector });
    const industry = official.industry.length === 0 ? null : official.industry;
    return ok(
      new Asset({
        ticker,
        name: profile.isOk ? profile.unwrap().name : ticker.value,
        sector,
        industry,
      }),
    );
  }
}
