// A composição declarada das units, do formulário cadastral da CVM (item B16).
//
// Cada caso de leitura de texto é uma linha **real** da FCA, copiada do
// arquivo: a coluna é texto livre, e o que garante que o leitor serve é ele
// acertar as dezoito formas que as companhias de fato escreveram.
import { describe, expect, it } from 'vitest';

import { UnitComposition, UnitCompositionCodec } from '../../src/core';
import { day } from './helpers';

describe('Leitura do texto declarado', () => {
  it('as nove units do universo saem com a composição certa', () => {
    // Cada string é a linha da FCA da companhia, com o ano em comentário.
    const declared: Record<string, { text: string; shares: number }> = {
      ALUP11: { text: '1 ON E 2 PN', shares: 3 },
      BPAC11: { text: '1 ON E 2 PNA', shares: 3 },
      BRBI11: { text: '2 ações preferenciais e 1 ação ordinária', shares: 3 },
      ENGI11: { text: '1 ação ordinária e 4 ações preferenciais', shares: 5 },
      IGTI11: { text: '1 ON e 2 PN', shares: 3 },
      KLBN11: { text: '1 KLBN3 + 4 KLBN4', shares: 5 },
      SANB11: { text: '1 ON + 1 PN', shares: 2 },
      SAPR11: { text: '1 ON e 4 PN', shares: 5 },
      TAEE11: { text: '1 ON / 2 PN', shares: 3 },
    };
    for (const [ticker, e] of Object.entries(declared)) {
      expect(UnitCompositionCodec.parse(e.text), ticker).toBe(e.shares);
    }
  });

  it('código de três letras conta, e a ENGI11 de 2018 é o caso', () => {
    // A FCA de 2018 declara "1 ENG3 e 4 ENGI4": exigir quatro letras no
    // código somava só o 4, e a unit saía com uma ação a menos.
    expect(UnitCompositionCodec.parse('1 ENG3 e 4 ENGI4')).toBe(5);
    expect(UnitCompositionCodec.parse('1 VVAR3 + 2 VVAR4')).toBe(3);
  });

  it('recibo de subscrição não é ação', () => {
    // A BMGB11 declara "1 PN + 3 Recibos de Subscrição" e tem **uma** ação.
    expect(UnitCompositionCodec.parse('1 PN + 3 Recibos de Subscrição')).toBe(1);
  });

  it('texto sem espécie reconhecível devolve nulo', () => {
    expect(UnitCompositionCodec.parse('')).toBeNull();
    expect(UnitCompositionCodec.parse('Vide item 9.1')).toBeNull();
  });

  it('composição acima do teto é recusada, e não confinada', () => {
    // Confinar devolveria um divisor plausível para um texto que o leitor
    // não entendeu. Recusar manda quem chama recuar para a razão medida.
    expect(UnitCompositionCodec.parse('11 ON + 3 PN')).toBeNull();
    expect(UnitCompositionCodec.parse('6 ON + 4 PN')).toBe(10);
  });
});

describe('O formulário vigente na data', () => {
  const series = [
    new UnitComposition({ year: 2018, shares: 4, declared: '1 ON + 3 PN' }),
    new UnitComposition({ year: 2021, shares: 5, declared: '1 ON + 4 PN' }),
    new UnitComposition({ year: 2024, shares: 3, declared: '1 ON + 2 PN' }),
  ];

  it('vale o mais recente até a data, e nunca um posterior', () => {
    expect(UnitCompositionCodec.at(series, day(2019, 6, 30))?.shares).toBe(4);
    expect(UnitCompositionCodec.at(series, day(2021, 1, 1))?.shares).toBe(5);
    expect(
      UnitCompositionCodec.at(series, day(2023, 12, 31))?.shares,
      'o formulário de 2024 seria conhecimento futuro em 2023',
    ).toBe(5);
    expect(UnitCompositionCodec.at(series, day(2026, 9, 14))?.shares).toBe(3);
  });

  it('antes do primeiro formulário não há composição', () => {
    expect(UnitCompositionCodec.at(series, day(2017, 12, 31))).toBeNull();
  });
});

describe('Pacote', () => {
  it('ida e volta preserva ano, contagem e texto', () => {
    const pkg = UnitCompositionCodec.encodePackage(
      new Map([['SAPR11', [new UnitComposition({ year: 2025, shares: 5, declared: '1 ON e 4 PN' })]]]),
      { generatedAt: day(2026, 9, 14) },
    );
    const parsed = UnitCompositionCodec.decodePackage(pkg);
    expect(parsed.get('SAPR11')).toHaveLength(1);
    const [only] = parsed.get('SAPR11')!;
    expect(only!.shares).toBe(5);
    expect(only!.year).toBe(2025);
    expect(only!.declared).toBe('1 ON e 4 PN');
  });

  it('entrada malformada é pulada, e não derruba a leitura', () => {
    const parsed = UnitCompositionCodec.decodePackage({
      versao: UnitCompositionCodec.version,
      units: {
        AAAA11: [
          { ano: 2025, acoes: 0 },
          { ano: 2024, acoes: 99 },
          { ano: 2023, acoes: 3, texto: '1 ON + 2 PN' },
        ],
        BBBB11: 'lixo',
      },
    });
    expect([...parsed.keys()]).toEqual(['AAAA11']);
    expect(parsed.get('AAAA11')).toHaveLength(1);
    expect(parsed.get('AAAA11')![0]!.shares).toBe(3);
  });

  it('pacote sem units devolve mapa vazio', () => {
    expect(UnitCompositionCodec.decodePackage({}).size).toBe(0);
  });
});
