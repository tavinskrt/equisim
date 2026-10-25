import { describe, expect, it } from 'vitest';

import {
  Asset,
  CvmDocumentCodec,
  CvmDocumentKind,
  CvmPeriodDocument,
  DateTime,
  err,
  type FundamentalsRepository,
  FundamentalsSnapshot,
  InsufficientData,
  ok,
  type Result,
  Sector,
  Ticker,
} from '../../src/core';
import { CvmFundamentalsRepository } from '../../src/data/repositories/cvm-fundamentals-repository';
import type { PackageLoader } from '../../src/data/repositories/package-loader';

const ticker = Ticker.parse('WEGE3');
const utc = (y: number, m: number, d: number): DateTime => DateTime.utc(y, m, d);

/** Mercado de teste: sete exercícios de dezembro, com valor de mercado. */
class Market implements FundamentalsRepository {
  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const out: FundamentalsSnapshot[] = [];
    for (let year = 2016; year <= 2022; year++) {
      out.push(new FundamentalsSnapshot({ ticker: t, fiscalPeriodEnd: utc(year, 12, 31), netIncome: 9, marketCap: 1000 }));
    }
    return ok(out);
  }

  async profile(t: Ticker): Promise<Result<Asset>> {
    return ok(new Asset({ ticker: t, name: 'WEG', sector: new Sector({ key: 'x', label: 'X' }) }));
  }

  async universe(): Promise<Result<Ticker[]>> {
    return ok([ticker]);
  }
}

class MarketOffline extends Market {
  override async history(_t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    return err(new InsufficientData('Sem conexão com a fonte de dados.'));
  }
}

function cvmPackage(): string {
  const documents: CvmPeriodDocument[] = [];
  for (let year = 2019; year <= 2022; year++) {
    documents.push(
      new CvmPeriodDocument({
        kind: CvmDocumentKind.dfp,
        periodStart: utc(year, 1, 1),
        periodEnd: utc(year, 12, 31),
        current: new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: utc(year, 12, 31),
          netIncome: 10,
          totalAssets: 500,
          receiptDate: utc(year + 1, 3, 1),
        }),
      }),
    );
  }
  return JSON.stringify(CvmDocumentCodec.encodePackage(new Map([['WEGE3', documents]]), { generatedAt: utc(2026, 9, 14) }));
}

const april2023 = (): DateTime => DateTime.local(2023, 4, 1);

function repository(loadPackage: PackageLoader, market: FundamentalsRepository = new Market()): CvmFundamentalsRepository {
  return new CvmFundamentalsRepository({ market, loadPackage, today: april2023 });
}

describe('CvmFundamentalsRepository', () => {
  it('com pacote, a CVM entra campo a campo e o mercado segue', async () => {
    const s = (await repository(async () => cvmPackage()).history(ticker)).unwrap();
    expect(s).toHaveLength(7);
    expect(s.at(-1)!.netIncome, 'a CVM vence onde tem').toBe(10);
    expect(s.at(-1)!.totalAssets).toBe(500);
    expect(s.at(-1)!.marketCap, 'mercado continua do mercado').toBe(1000);
    expect(s[0]!.netIncome, 'antes da CVM, só o mercado').toBe(9);
  });

  it('sem pacote, o repositório é transparente', async () => {
    const repo = repository(async () => {
      throw new Error('asset ausente');
    });
    const s = (await repo.history(ticker)).unwrap();
    expect(s.every((x) => Math.abs(x.netIncome! - 9) < 1e-9)).toBe(true);
    expect(s).toHaveLength(7);
  });

  it('pacote corrompido também não derruba a avaliação', async () => {
    expect((await repository(async () => '{isto não é json').history(ticker)).isOk).toBe(true);
  });

  it('a série ancorada fica desligada por padrão — decisão 73', () => {
    expect(repository(async () => cvmPackage()).anchored).toBe(false);
  });

  it('o pacote é lido uma vez só', async () => {
    let readings = 0;
    const repo = repository(async () => {
      readings++;
      return cvmPackage();
    });
    await repo.history(ticker);
    await repo.history(ticker);
    await repo.history(ticker);
    expect(readings).toBe(1);
  });

  it('nem quando várias avaliações pedem o pacote ao mesmo tempo', async () => {
    // Telas diferentes pedem ativos diferentes em paralelo, e cada leitura é
    // um JSON de 9 MB decodificado na thread da interface.
    let readings = 0;
    const repo = repository(async () => {
      readings++;
      await Promise.resolve();
      return cvmPackage();
    });
    const r = await Promise.all([0, 1, 2, 3].map(() => repo.history(ticker)));
    expect(readings).toBe(1);
    expect(r.every((x) => Math.abs(x.unwrap().at(-1)!.netIncome! - 10) < 1e-9)).toBe(true);
  });

  it('falha da série de mercado passa adiante, e não vira série da CVM sozinha', async () => {
    // O mercado dá preço, valor de mercado e contagem; sem ele a série da CVM
    // não forma avaliação, e fingir que forma esconderia a falha.
    const r = await repository(async () => cvmPackage(), new MarketOffline()).history(ticker);
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull).toBeInstanceOf(InsufficientData);
  });
});

describe('A ausência aparece — item A1.10', () => {
  function withPackage(loadPackage: PackageLoader, today?: DateTime): CvmFundamentalsRepository {
    return new CvmFundamentalsRepository({
      market: new Market(),
      loadPackage,
      today: () => today ?? DateTime.local(2026, 10, 1),
    });
  }

  it('pacote ausente vira ressalva, e a série continua', async () => {
    const repo = withPackage(async () => {
      throw new Error('asset ausente');
    });
    expect(await repo.coverageNote(ticker)).toContain('não trouxe o pacote');
    expect((await repo.history(ticker)).isOk).toBe(true);
  });

  it('JSON inválido é ilegível, e diz por quê', async () => {
    expect(await withPackage(async () => '{isto não é json').coverageNote(ticker)).toContain('JSON é inválido');
  });

  it('versão que o leitor não conhece é ilegível, e não vazio', async () => {
    const repo = withPackage(async () =>
      JSON.stringify({ versao: CvmDocumentCodec.version + 1, geradoEm: '2026-09-14', tickers: {} }),
    );
    expect(await repo.coverageNote(ticker)).toContain('versão');
  });

  it('pacote sem ativo nenhum é ilegível', async () => {
    const repo = withPackage(async () =>
      JSON.stringify({ versao: CvmDocumentCodec.version, geradoEm: '2026-09-14', tickers: {} }),
    );
    expect(await repo.coverageNote(ticker)).toContain('não traz ativo nenhum');
  });

  it('ativo fora do pacote é declarado, com a data do pacote', async () => {
    expect(await withPackage(async () => cvmPackage()).coverageNote(Ticker.parse('PETR4'))).toContain('14/09/2026');
  });

  it('ativo coberto por pacote recente não leva ressalva', async () => {
    expect(await withPackage(async () => cvmPackage()).coverageNote(ticker)).toBeNull();
  });

  it('pacote defasado é declarado', async () => {
    const repo = withPackage(async () => cvmPackage(), DateTime.local(2027, 3, 1));
    expect(await repo.coverageNote(ticker)).toContain('há 168 dias');
  });
});
