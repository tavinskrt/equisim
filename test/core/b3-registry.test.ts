import { describe, expect, it } from 'vitest';

import { B3Classification, B3Registry, B3RegistryCodec, DateTime, type JsonObject } from '../../src/core';
import { expectClose, expectDate } from './helpers';

const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

const ev = (
  label: string,
  factor: string,
  recordDate: string,
  options: { isin?: string; issued?: string } = {},
): JsonObject => ({
  assetIssued: options.issued ?? '',
  factor,
  approvedOn: '01/01/2020',
  isinCode: options.isin ?? 'BRXXXXACNOR0',
  label,
  lastDatePrior: recordDate,
  remarks: '',
});

describe('Números e datas da B3', () => {
  it('ponto de milhar e vírgula decimal', () => {
    expect(B3Registry.parseNumber('5.730.834.040')).toBe(5730834040);
    expectClose(B3Registry.parseNumber('0,05000000000')!, 0.05, 1e-15);
    expect(B3Registry.parseNumber('9.900,00000000000')).toBe(9900);
    expect(B3Registry.parseNumber('')).toBeNull();
  });

  it('dd/mm/aaaa', () => {
    expectDate(B3Registry.parseDate('15/04/2024'), d(2024, 4, 15));
    expect(B3Registry.parseDate('2024-04-15')).toBeNull();
  });
});

describe('Convenção do fator — conferida contra o preço', () => {
  it('desdobramento e bonificação são acréscimo percentual', () => {
    // BBAS3, 2024: "DESDOBRAMENTO 100" e o preço caiu pela metade.
    expect(B3Registry.multiplier('DESDOBRAMENTO', 100)).toBe(2);
    expect(B3Registry.multiplier('DESDOBRAMENTO', 900)).toBe(10);
    expect(B3Registry.multiplier('BONIFICACAO', 25)).toBe(1.25);
  });

  it('grupamento é multiplicador', () => {
    // AERI3, 2024: "GRUPAMENTO 0,05" — 20 para 1.
    expect(B3Registry.multiplier('GRUPAMENTO', 0.05)).toBe(0.05);
  });

  it('cisão, incorporação e resgate ficam de fora', () => {
    expect(B3Registry.multiplier('CIS RED CAP', 100)).toBeNull();
    expect(B3Registry.multiplier('INCORPORACAO', 100)).toBeNull();
    expect(B3Registry.multiplier('RESG TOTAL RV', 100)).toBeNull();
    expect(B3Registry.multiplier('GRUPAMENTO', 0)).toBeNull();
  });
});

describe('Eventos', () => {
  it('mesma data e ISIN se compõem', () => {
    // VIVT3, 2025: grupamento de 40 para 1 e desdobramento de 1 para 80 no
    // mesmo dia — o preço caiu pela metade. Lido um a um, erra por 40x.
    const e = B3Registry.events([
      ev('GRUPAMENTO', '0,02500000000', '14/04/2025'),
      ev('DESDOBRAMENTO', '7.900,00000000000', '14/04/2025'),
    ]);
    expect(e).toHaveLength(1);
    expectClose(e[0]!.factor, 2.0, 1e-12);
    expect(e[0]!.labels).toEqual(['GRUPAMENTO', 'DESDOBRAMENTO']);
  });

  it('a mesma entrada repetida por papel emitido conta uma vez', () => {
    const e = B3Registry.events([
      ev('DESDOBRAMENTO', '100,00000000000', '15/04/2024', { issued: 'A' }),
      ev('DESDOBRAMENTO', '100,00000000000', '15/04/2024', { issued: 'B' }),
    ]);
    expect(e).toHaveLength(1);
    expect(e[0]!.factor).toBe(2);
  });

  it('ISIN diferente não se compõe', () => {
    const e = B3Registry.events([
      ev('BONIFICACAO', '10,00000000000', '23/12/2025', { isin: 'BRAAAAACNOR0' }),
      ev('BONIFICACAO', '10,00000000000', '23/12/2025', { isin: 'BRAAAAACNPR0' }),
    ]);
    expect(e).toHaveLength(2);
  });

  it('a data ex é o dia útil seguinte à data-com', () => {
    // Sexta 12/09/2025 → segunda 15/09/2025.
    const friday = B3Registry.events([ev('BONIFICACAO', '10', '12/09/2025')]);
    expectDate(friday[0]!.exDate, d(2025, 9, 15));
    // Sexta antes do Carnaval de 2024 → quarta de cinzas.
    const carnival = B3Registry.events([ev('BONIFICACAO', '10', '09/02/2024')]);
    expectDate(carnival[0]!.exDate, d(2024, 2, 14));
  });
});

describe('Emissor', () => {
  const json: JsonObject = {
    code: 'BBAS',
    totalNumberShares: '5.730.834.040',
    numberCommonShares: '5.730.834.040',
    numberPreferredShares: '0',
    stockDividends: [
      ev('DESDOBRAMENTO', '100,00000000000', '15/04/2024', { isin: 'BRBBASACNOR3' }),
      ev('GRUPAMENTO', '0,00100000000', '23/01/2004', { isin: 'BRBBASACNOR3' }),
    ],
  };

  it('lê contagem e eventos', () => {
    const e = B3Registry.issuer(json, { consultedOn: d(2026, 9, 14) })!;
    expect(e.code).toBe('BBAS');
    expect(e.totalShares).toBe(5730834040);
    expect(e.events).toHaveLength(2);
    expect(e.events[0]!.exDate.isBefore(e.events[1]!.exDate)).toBe(true);
  });

  it('sem código não é emissor', () => {
    expect(B3Registry.issuer({ code: '' }, { consultedOn: d(2026, 9, 14) })).toBeNull();
  });
});

describe('Pacote', () => {
  it('ida e volta preserva contagem e eventos', () => {
    const e = B3Registry.issuer(
      {
        code: 'VIVT',
        totalNumberShares: '1.624.086.235',
        stockDividends: [
          ev('GRUPAMENTO', '0,02500000000', '14/04/2025'),
          ev('DESDOBRAMENTO', '7.900,00000000000', '14/04/2025'),
        ],
      },
      { consultedOn: d(2026, 9, 14) },
    )!;
    const pkg = B3RegistryCodec.encodePackage([e], { generatedAt: d(2026, 9, 14) });
    const parsed = B3RegistryCodec.decodePackage(pkg).get('VIVT')!;
    expect(parsed.totalShares).toBe(e.totalShares);
    expectDate(parsed.consultedOn, d(2026, 9, 14));
    expect(parsed.events).toHaveLength(1);
    expectClose(parsed.events[0]!.factor, 2, 1e-12);
    expectDate(parsed.events[0]!.exDate, e.events[0]!.exDate);
  });

  it('versão desconhecida não é lida pela metade', () => {
    expect(B3RegistryCodec.decodePackage({ versao: 99, emissores: {} }).size).toBe(0);
  });
});

describe('Classificação setorial oficial — item A5', () => {
  it('lê setor, subsetor e segmento, com a pontuação da B3', () => {
    const c = B3Classification.parse(
      'Petróleo. Gás e Biocombustíveis / Petróleo. Gás e Biocombustíveis / Exploração. Refino e Distribuição',
    )!;
    expect(c.sector).toBe('Petróleo. Gás e Biocombustíveis');
    expect(c.segment).toBe('Exploração. Refino e Distribuição');
    expect(c.sectorKey).toBe('petroleo-gas-e-biocombustiveis');
    expect(c.industry).toBe('Petróleo. Gás e Biocombustíveis / Exploração. Refino e Distribuição');
  });

  it('a chave do setor casa com a da fonte onde os nomes coincidem', () => {
    expect(B3Classification.parse('Materiais Básicos / Mineração')!.sectorKey, 'é a chave de CyclicalSectors').toBe(
      'materiais-basicos',
    );
    expect(B3Classification.parse('Consumo não Cíclico / Bebidas')!.sectorKey).toBe('consumo-nao-ciclico');
  });

  it('texto vazio não é classificação', () => {
    expect(B3Classification.parse('')).toBeNull();
    expect(B3Classification.parse(null)).toBeNull();
    expect(B3Classification.parse(' / ')).toBeNull();
  });

  it('o emissor leva a classificação do detalhe, e o pacote a guarda', () => {
    const e = B3Registry.issuer(
      { code: 'SANB', totalNumberShares: '7.498.531.051' },
      {
        consultedOn: d(2026, 9, 14),
        detail: { industryClassification: 'Financeiro / Intermediários Financeiros / Bancos' },
      },
    )!;
    expect(e.classification!.sectorKey).toBe('financeiro');
    const parsed = B3RegistryCodec.decodePackage(B3RegistryCodec.encodePackage([e], { generatedAt: d(2026, 9, 14) })).get(
      'SANB',
    )!;
    expect(parsed.classification!.label).toBe('Financeiro / Intermediários Financeiros / Bancos');
  });

  it('pacote da versão 1 continua legível, sem classificação', () => {
    const parsed = B3RegistryCodec.decodePackage({
      versao: 1,
      geradoEm: '2026-09-14',
      emissores: { CTKA: { consultadoEm: '2026-09-14', total: 6205375, eventos: [] } },
    });
    expectClose(parsed.get('CTKA')!.totalShares, 6205375, 1e-6);
    expect(parsed.get('CTKA')!.classification).toBeNull();
  });

  it('versão futura não é lida pela metade', () => {
    expect(
      B3RegistryCodec.decodePackage({
        versao: B3RegistryCodec.version + 1,
        emissores: { CTKA: { consultadoEm: '2026-09-14' } },
      }).size,
    ).toBe(0);
  });
});
