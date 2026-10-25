import { describe, expect, it } from 'vitest';

import {
  B3Registry,
  B3RegistryCodec,
  DateTime,
  err,
  InsufficientData,
  ok,
  type Result,
  Ticker,
  TreasuryCurve,
  TreasuryQuote,
  TreasuryQuotesCodec,
} from '../../src/core';
import { ApiClient } from '../../src/data/network/api-client';
import { ApiConfig, BrapiMode } from '../../src/data/config/api-config';
import { TreasuryDatasource } from '../../src/data/datasources/treasury-datasource';
import { B3RegistryRepository } from '../../src/data/repositories/b3-registry-repository';
import { RiskFreeCurveRepository } from '../../src/data/repositories/risk-free-curve-repository';
import { expectClose } from '../core/helpers';
import { clientWith, FixtureTransport } from './fixture-transport';

const config = new ApiConfig({
  mode: BrapiMode.direct,
  brapiBaseUrl: 'https://brapi.dev/api',
  bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
});

const catalog = `
{"result":{"resources":[
  {"format":"PDF","url":"https://exemplo.gov.br/taxa.pdf"},
  {"format":"CSV","url":"https://exemplo.gov.br/precotaxatesourodireto.csv"}
]}}`;

/**
 * Cabeçalho, o dia mais recente — com um título que a curva não usa no meio
 * —, e o dia anterior, que a leitura não pode alcançar.
 */
const csv =
  'Tipo Titulo;Data Vencimento;Data Base;Taxa Compra Manha;' +
  'Taxa Venda Manha;PU Compra Manha;PU Venda Manha;PU Base Manha\n' +
  'Tesouro Selic;01/03/2027;10/09/2026;0,00;0,01;19854,30;19843,06;19843,06\n' +
  'Tesouro Prefixado;01/01/2027;10/09/2026;13,56;13,68;960,00;959,00;959,00\n' +
  'Tesouro Prefixado;01/01/2029;10/09/2026;13,93;14,05;750,00;749,00;749,00\n' +
  'Tesouro Prefixado com Juros Semestrais;01/01/2037;10/09/2026;14,33;14,45;900,00;899,00;899,00\n' +
  'Tesouro Prefixado;01/01/2027;09/09/2026;99,99;99,99;1,00;1,00;1,00\n';

const source = (fixture: FixtureTransport): TreasuryDatasource => new TreasuryDatasource(clientWith(fixture, config));

describe('Tesouro direto do arquivo — item A2.1', () => {
  it('lê só o dia mais recente, e só os prefixados', async () => {
    const r = await source(
      new FixtureTransport({ bodies: { package_show: catalog, 'precotaxatesourodireto.csv': csv } }),
    ).latest();
    const quotes = r.unwrap();
    expect(quotes).toHaveLength(3);
    expect(new Set(quotes.map((q) => q.baseDate.key))).toEqual(new Set([DateTime.utc(2026, 9, 10).key]));
    expect(quotes.every((q) => q.rate < 0.2), 'a linha de 09/09, com 99,99%, não pode ter sido lida').toBe(true);
    // A taxa exata de cada título, e não só a ordem de grandeza: "13,56" é
    // 13,56% ao ano — a vírgula decimal lida errado passaria pelo teto de 20%
    // e deslocaria a curva inteira (lente `risco`, 16/09/2026).
    const byMaturityDate = new Map(quotes.map((q) => [q.maturity.toIso8601String().substring(0, 10), q.rate]));
    expectClose(byMaturityDate.get('2027-01-01'), 0.1356, 1e-12);
    expectClose(byMaturityDate.get('2029-01-01'), 0.1393, 1e-12);
    expectClose(byMaturityDate.get('2037-01-01'), 0.1433, 1e-12);
  });

  it('catálogo sem CSV é falha declarada', async () => {
    const r = await source(new FixtureTransport({ bodies: { package_show: '{"result":{"resources":[]}}' } })).latest();
    expect(r.isErr).toBe(true);
  });

  it('arquivo fora do ar é falha, e não lista vazia', async () => {
    const r = await source(
      new FixtureTransport({ bodies: { package_show: catalog }, failures: { 'precotaxatesourodireto.csv': 503 } }),
    ).latest();
    expect(r.isErr).toBe(true);
  });

  it('CSV com o formato quebrado é falha, e não exceção crua', async () => {
    // Lente `risco`, 20/09/2026. Coluna renomeada, separador trocado ou taxa
    // ilegível têm de virar `Result.err`, e não estourar na leitura.
    const unreadableRate =
      'Tipo Titulo;Data Vencimento;Data Base;Taxa Compra Manha;Taxa Venda Manha;' +
      'PU Compra Manha;PU Venda Manha;PU Base Manha\n' +
      'Tesouro Prefixado;01/01/2027;10/09/2026;;;;;\n';
    const commaSeparator =
      'Tipo Titulo,Data Vencimento,Data Base,Taxa Compra Manha\n' + 'Tesouro Prefixado,01/01/2027,10/09/2026,13.56\n';
    for (const body of ['', 'coisa;outra;terceira\n1;2;3\n', unreadableRate, commaSeparator]) {
      const r = await source(
        new FixtureTransport({ bodies: { package_show: catalog, 'precotaxatesourodireto.csv': body } }),
      ).latest();
      expect(r.isErr, body.length === 0 ? '(vazio)' : body).toBe(true);
    }
  });
});

/** Fonte do dia com a leitura trocada. */
class StubSource extends TreasuryDatasource {
  constructor(private readonly read: () => Promise<Result<TreasuryQuote[]>>) {
    super(new ApiClient(config));
  }

  override latest(): Promise<Result<TreasuryQuote[]>> {
    return this.read();
  }
}

describe('Curva do aplicativo — decisão 84', () => {
  const quotesOf = (base: DateTime): TreasuryQuote[] => [
    new TreasuryQuote({ type: TreasuryCurve.ltn, maturity: DateTime.utc(2027, 1, 1), baseDate: base, rate: 0.1356 }),
    new TreasuryQuote({ type: TreasuryCurve.ltn, maturity: DateTime.utc(2029, 1, 1), baseDate: base, rate: 0.1393 }),
    new TreasuryQuote({ type: TreasuryCurve.ntnF, maturity: DateTime.utc(2037, 1, 1), baseDate: base, rate: 0.1433 }),
  ];
  const packageOf = (base: DateTime): string =>
    JSON.stringify(TreasuryQuotesCodec.encode(quotesOf(base), { generatedAt: base }));
  const offline = (): StubSource => new StubSource(async () => err(new InsufficientData('sem rede')));
  const noPackage = async (): Promise<string> => {
    throw new Error('sem pacote');
  };

  it('a do dia vence a do pacote', async () => {
    const repo = new RiskFreeCurveRepository({
      remote: new StubSource(async () => ok(quotesOf(DateTime.utc(2026, 9, 10)))),
      loadPackage: async () => packageOf(DateTime.utc(2026, 9, 1)),
    });
    const c = (await repo.readAt(DateTime.local(2026, 9, 11))).curve;
    expect(c!.referenceDate.equals(DateTime.utc(2026, 9, 10))).toBe(true);
  });

  it('sem rede, o pacote recente serve', async () => {
    const repo = new RiskFreeCurveRepository({ remote: offline(), loadPackage: async () => packageOf(DateTime.utc(2026, 9, 8)) });
    const c = (await repo.readAt(DateTime.local(2026, 9, 11))).curve;
    expect(c!.referenceDate.equals(DateTime.utc(2026, 9, 8))).toBe(true);
  });

  it('pacote velho não vira curva: a cascata recua, declarando', async () => {
    const repo = new RiskFreeCurveRepository({ remote: offline(), loadPackage: async () => packageOf(DateTime.utc(2026, 6, 1)) });
    expect((await repo.readAt(DateTime.local(2026, 9, 11))).curve).toBeNull();
  });

  it('falha da busca não fica guardada: a próxima avaliação tenta de novo', async () => {
    let calls = 0;
    const repo = new RiskFreeCurveRepository({
      remote: new StubSource(async () => {
        calls++;
        return calls === 1 ? err(new InsufficientData('sem rede')) : ok(quotesOf(DateTime.utc(2026, 9, 10)));
      }),
      loadPackage: noPackage,
    });
    expect((await repo.readAt(DateTime.local(2026, 9, 11))).curve).toBeNull();
    expect((await repo.readAt(DateTime.local(2026, 9, 11))).curve).not.toBeNull();
    expect(calls).toBe(2);
  });

  it('a busca vale pelo dia: no dia seguinte, busca de novo', async () => {
    let calls = 0;
    const repo = new RiskFreeCurveRepository({
      remote: new StubSource(async () => {
        calls++;
        return ok(quotesOf(DateTime.utc(2026, 9, 10)));
      }),
      loadPackage: noPackage,
    });
    await repo.readAt(DateTime.local(2026, 9, 11, 9));
    await repo.readAt(DateTime.local(2026, 9, 11, 18));
    expect(calls, 'o mesmo dia usa a mesma busca').toBe(1);
    await repo.readAt(DateTime.local(2026, 9, 12));
    expect(calls).toBe(2);
  });

  it('na web, só o pacote — decisão 86', async () => {
    const repo = new RiskFreeCurveRepository({ remote: null, loadPackage: async () => packageOf(DateTime.utc(2026, 9, 8)) });
    const r = await repo.readAt(DateTime.local(2026, 9, 11));
    expect(r.curve!.referenceDate.equals(DateTime.utc(2026, 9, 8))).toBe(true);
    expect(r.note, 'com curva, a avaliação já diz a data').toBeNull();
  });

  it('na web, pacote vencido: a ressalva diz a data e o remédio', async () => {
    const repo = new RiskFreeCurveRepository({ remote: null, loadPackage: async () => packageOf(DateTime.utc(2026, 6, 1)) });
    const r = await repo.readAt(DateTime.local(2026, 9, 11));
    expect(r.curve).toBeNull();
    expect(r.note).toContain('Na web');
    expect(r.note).toContain('01/06/2026');
    expect(r.note).toContain('build novo');
  });

  it('na web, sem pacote legível, a ressalva diz isso', async () => {
    const repo = new RiskFreeCurveRepository({ remote: null, loadPackage: async () => '{isto não é json' });
    const r = await repo.readAt(DateTime.local(2026, 9, 11));
    expect(r.curve).toBeNull();
    expect(r.note).toContain('não pôde ser lido');
  });

  it('nas ferramentas, sem o Tesouro e com pacote vencido, a ressalva não fala em build', async () => {
    const repo = new RiskFreeCurveRepository({ remote: offline(), loadPackage: async () => packageOf(DateTime.utc(2026, 6, 1)) });
    const r = await repo.readAt(DateTime.local(2026, 9, 11));
    expect(r.curve).toBeNull();
    expect(r.note).toContain('O Tesouro não trouxe');
    expect(r.note).toContain('01/06/2026');
    expect(r.note, 'com a fonte do dia o remédio é a rede, e não um build').not.toContain('build novo');
  });
});

describe('Registro da B3 no aplicativo — decisão 83', () => {
  const pkg = JSON.stringify(
    B3RegistryCodec.encodePackage(
      [B3Registry.issuer({ code: 'CTKA', totalNumberShares: '6.205.375' }, { consultedOn: DateTime.utc(2026, 9, 14) })!],
      { generatedAt: DateTime.utc(2026, 9, 14) },
    ),
  );

  it('a contagem vem pela raiz do ticker', async () => {
    const repo = new B3RegistryRepository({ loadPackage: async () => pkg });
    const c = await repo.officialSharesFor(Ticker.parse('CTKA4'));
    // **Igualdade, e não tolerância** (lente `risco`, 21/09/2026): a contagem
    // da B3 é inteiro publicado, e fração aqui é defeito de leitura.
    expect(c!.total).toBe(6205375);
    expect(c!.asOf.equals(DateTime.utc(2026, 9, 14))).toBe(true);
    expect(await repo.officialSharesFor(Ticker.parse('PETR4'))).toBeNull();
  });

  it('sem pacote, o repositório é transparente', async () => {
    const repo = new B3RegistryRepository({
      loadPackage: async () => {
        throw new Error('asset ausente');
      },
    });
    expect(await repo.officialSharesFor(Ticker.parse('CTKA4'))).toBeNull();
  });
});
