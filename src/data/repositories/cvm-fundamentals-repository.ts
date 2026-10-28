import {
  type Asset,
  CvmDocumentCodec,
  type CvmPeriodDocument,
  CvmSeries,
  DateTime,
  type FundamentalsRepository,
  type FundamentalsSnapshot,
  interpolateJson,
  isJsonObject,
  ok,
  PointInTimeView,
  type Result,
  type Ticker,
} from '../../core';
import type { PackageLoader } from './package-loader';

/** O pacote lido, ou o motivo de não ter sido. */
interface CvmPackage {
  readonly documents: Map<string, CvmPeriodDocument[]>;
  readonly generatedAt: DateTime | null;
  readonly missing: boolean;
  readonly reason: string | null;
}

const missingPackage: CvmPackage = { documents: new Map(), generatedAt: null, missing: true, reason: null };

function unreadable(reason: string): CvmPackage {
  return { documents: new Map(), generatedAt: null, missing: false, reason };
}

/**
 * Fundamentos do aplicativo com a demonstração da CVM mesclada (item A1.9).
 *
 * **Decora** o repositório de mercado em vez de substituí-lo: preço, valor de
 * mercado e a contagem corrente continuam vindo de lá, e a CVM entra campo a
 * campo por `CvmSeries` — a mesma montagem que a validação usa, e não uma
 * cópia dela.
 *
 * **De onde vêm os documentos.** De um pacote versionado com o aplicativo,
 * gerado por `tool/cvm-package.ts` a partir da base ingerida (decisão 80).
 * A CVM não é API de tempo real — publica arquivos anuais de centenas de
 * megabytes —, e levar a ingestão ao navegador seria baixar 750 MB para ler
 * 375 tickers.
 *
 * **Sem pacote, a avaliação segue — e diz que seguiu sem ele.** Pacote
 * ausente, corrompido ou de versão desconhecida não derruba a avaliação: ela
 * volta a ter só a fonte de mercado. Mas isso deixou de ser silencioso
 * (item A1.10): [coverageNote] devolve a ressalva que a tela mostra.
 */
export class CvmFundamentalsRepository implements FundamentalsRepository {
  /** Repositório de mercado decorado. */
  readonly market: FundamentalsRepository;

  /** Lê o conteúdo do pacote. No aplicativo, um `fetch`; em teste, uma string fixa. */
  readonly loadPackage: PackageLoader;

  /**
   * Data da avaliação. Recebida por função para que o repositório não chame
   * o relógio por conta própria.
   */
  readonly today: () => DateTime;

  /**
   * Usa a série ancorada no trimestre (decisão 73).
   *
   * **Desligada por padrão**, e a razão está medida: a série ancorada move a
   * ordenação de metade do universo (correlação de postos de 0,683 contra a
   * anual, decisão 78), e se isso é informação ou ruído só a coorte
   * trimestral dirá.
   */
  readonly anchored: boolean;

  /**
   * Idade, em dias, a partir da qual o pacote é declarado defasado.
   *
   * A DFP sai até o fim de março e o ITR até 45 dias depois do trimestre: um
   * pacote com mais de cem dias perdeu, com certeza, um ciclo de entrega.
   */
  static readonly maxAgeDays = 100;

  /**
   * A **leitura em curso**, e não o resultado dela: avaliações pedidas ao
   * mesmo tempo esperam a mesma leitura, em vez de cada uma decodificar os
   * 9 MB do pacote.
   */
  private pkg: Promise<CvmPackage> | null = null;

  constructor(args: {
    market: FundamentalsRepository;
    loadPackage: PackageLoader;
    today: () => DateTime;
    anchored?: boolean;
  }) {
    this.market = args.market;
    this.loadPackage = args.loadPackage;
    this.today = args.today;
    this.anchored = args.anchored ?? false;
  }

  private loaded(): Promise<CvmPackage> {
    return (this.pkg ??= this.read());
  }

  private async read(): Promise<CvmPackage> {
    let raw: string;
    try {
      raw = await this.loadPackage();
    } catch {
      return missingPackage;
    }
    let json: unknown;
    try {
      json = JSON.parse(raw);
    } catch {
      return unreadable('o JSON é inválido');
    }
    if (!isJsonObject(json)) return unreadable('o conteúdo não é um objeto JSON');
    if (json['versao'] !== CvmDocumentCodec.version) {
      return unreadable(
        `versão ${interpolateJson(json['versao'])}, e este leitor conhece a ${CvmDocumentCodec.version}`,
      );
    }
    const documents = CvmDocumentCodec.decodePackage(json);
    if (documents.size === 0) return unreadable('o pacote não traz ativo nenhum');
    const generatedAt = DateTime.tryParse(interpolateJson(json['geradoEm']));
    return { documents, generatedAt, missing: false, reason: null };
  }

  /**
   * A ressalva que a avaliação de [ticker] deve levar, ou `null`.
   *
   * Texto de narrativa, como os avisos da cascata: é o que a tela de
   * avaliação mostra no cartão de ressalvas.
   */
  async coverageNote(ticker: Ticker): Promise<string | null> {
    const p = await this.loaded();
    const t = ticker.value;
    if (p.missing) {
      return (
        'Este build não trouxe o pacote de demonstrações da CVM: os ' +
        `fundamentos de ${t} vêm só da fonte de mercado, sem a data de ` +
        'recebimento observada nem a ação em tesouraria.'
      );
    }
    if (p.reason !== null) {
      return (
        'O pacote de demonstrações da CVM deste build não pôde ser lido ' +
        `— ${p.reason}. Os fundamentos de ${t} vêm só da fonte de mercado.`
      );
    }
    const docs = p.documents.get(t);
    const date = p.generatedAt === null ? null : formatDay(p.generatedAt);
    if (docs === undefined || docs.length === 0) {
      return (
        `O pacote da CVM${date === null ? '' : ` de ${date}`} não traz ` +
        `demonstração de ${t}: os fundamentos vêm só da fonte de mercado.`
      );
    }
    const generated = p.generatedAt;
    if (generated !== null) {
      const age = utcDay(this.today()).difference(utcDay(generated)).inDays;
      if (age > CvmFundamentalsRepository.maxAgeDays) {
        return (
          `O pacote da CVM é de ${date}, há ${age} dias: demonstrações de ` +
          `${t} entregues depois disso não entram nesta avaliação.`
        );
      }
    }
    return null;
  }

  async history(ticker: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const base = await this.market.history(ticker);
    if (base.isErr) return base;
    const documents = (await this.loaded()).documents.get(ticker.value);
    if (documents === undefined || documents.length === 0) return base;

    const view = new PointInTimeView(this.today());
    const assembled = CvmSeries.build({
      documents,
      market: base.unwrap(),
      published: (s) => view.isPublished(s),
      anchored: this.anchored,
      // O ano corrente anualizado fecha a série anual (decisão 153).
      yearToDate: CvmSeries.yearToDateByDefault,
    });
    return ok([...assembled.series]);
  }

  profile(ticker: Ticker): Promise<Result<Asset>> {
    return this.market.profile(ticker);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.market.universe();
  }
}

function utcDay(d: DateTime): DateTime {
  return DateTime.utc(d.year, d.month, d.day);
}

/** `DD/MM/AAAA`, como a narrativa da avaliação escreve datas. */
export function formatDay(d: DateTime): string {
  return `${String(d.day).padStart(2, '0')}/${String(d.month).padStart(2, '0')}/${d.year}`;
}
