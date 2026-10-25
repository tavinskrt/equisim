import { describe, expect, it } from 'vitest';

import { DateTime, FreConcessionTerm } from '../../src/core';
import { expectDate } from './helpers';

const d = (y: number, m: number, dd: number): DateTime => DateTime.utc(y, m, dd);

describe('Fim do contrato no texto do FRE — item A6', () => {
  // Os textos são os do formulário, copiados das companhias do universo.
  it('mês por extenso, com e sem "até"', () => {
    expectDate(FreConcessionTerm.endOf('Junho de 2042'), d(2042, 6, 30));
    expectDate(FreConcessionTerm.endOf('até novembro de 2027'), d(2027, 11, 30));
    expectDate(FreConcessionTerm.endOf('Até agosto de 2030.'), d(2030, 8, 31));
    expectDate(FreConcessionTerm.endOf('até Julho/2025'), d(2025, 7, 31));
    expectDate(FreConcessionTerm.endOf('até Fevereiro de 2016'), d(2016, 2, 29));
    expectDate(FreConcessionTerm.endOf('Março de 2035'), d(2035, 3, 31));
  });

  it('data completa, com ponto ou barra, e o intervalo vale pelo fim', () => {
    expectDate(FreConcessionTerm.endOf('até 20.03.2033'), d(2033, 3, 20));
    expectDate(FreConcessionTerm.endOf('Válido até 07/07/2045'), d(2045, 7, 7));
    expectDate(FreConcessionTerm.endOf('de 08.03.2018 a 08.03.2048'), d(2048, 3, 8));
    expectDate(FreConcessionTerm.endOf('De 11/08/2017 até 11/08/2047'), d(2047, 8, 11));
    expectDate(FreConcessionTerm.endOf('23.09.2022'), d(2022, 9, 23));
  });

  it('prazo contado a partir de um início', () => {
    expectDate(FreConcessionTerm.endOf('30 anos, a partir de 03/2019'), d(2049, 3, 31));
    expectDate(FreConcessionTerm.endOf('30 anos, a partir 06.07.1994'), d(2024, 7, 6));
  });

  it('com prorrogação, vale o prazo de hoje', () => {
    expectDate(FreConcessionTerm.endOf('2028, prorrogável até 2058'), d(2028, 12, 31));
    expectDate(FreConcessionTerm.endOf('Até 27/08/23 (Prorr. 27/08/38)'), d(2023, 8, 27));
  });

  it('recusa o que não dá data absoluta', () => {
    expect(FreConcessionTerm.endOf('Prazo indeterminado')).toBeNull();
    expect(FreConcessionTerm.endOf('Vide item 9.1 deste formulário')).toBeNull();
    expect(FreConcessionTerm.endOf('6 anos')).toBeNull();
    expect(FreConcessionTerm.endOf('35 anos (vencimento do contrato)')).toBeNull();
    expect(FreConcessionTerm.endOf('')).toBeNull();
    expect(FreConcessionTerm.endOf(null)).toBeNull();
    expect(FreConcessionTerm.endOf('31/02/2030'), 'data que não existe não vira março').toBeNull();
  });
});

describe('Resumo por companhia', () => {
  it('contrato vencido na data do formulário não conta', () => {
    const r = FreConcessionTerm.summarize(
      ['até Fevereiro de 2016', 'até julho/2045', 'até Dezembro/2035', 'Prazo indeterminado'],
      d(2019, 1, 1),
    );
    expect(r.contracts).toBe(4);
    expect(r.readCount).toBe(3);
    expect(r.inForceCount).toBe(2);
    expectDate(r.end, d(2035, 12, 31), 'mediana baixa de dois');
  });

  it('sem contrato vigente, sem fim', () => {
    const r = FreConcessionTerm.summarize(['Vide item 9.1'], d(2022, 1, 1));
    expect(r.end).toBeNull();
    expect(r.readCount).toBe(0);
  });
});
