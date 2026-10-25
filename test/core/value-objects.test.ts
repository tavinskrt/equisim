import { describe, expect, it } from 'vitest';

import {
  ArgumentError,
  DateRange,
  FormatException,
  Money,
  SeededRandom,
  Ticker,
  UnsupportedError,
  Weight,
  Weights,
} from '../../src/core';
import { day, expectClose } from './helpers';

describe('Money', () => {
  it('converte reais para centavos sem erro de arredondamento', () => {
    expect(Money.fromReais(10.55).cents).toBe(1055);
    expect(Money.fromReais(0.1).cents).toBe(10);
    expect(Money.fromReais(1 / 3).cents).toBe(33);
  });

  it('arredonda o decimal escrito meio afastado de zero (B21, dec. 125)', () => {
    // `1.005 * 100` é `100.49999999999999`: o produto binário perde o meio,
    // e a regra do BRL manda subir.
    expect(Money.fromReais(1.005).cents).toBe(101);
    expect(Money.fromReais(2.675).cents).toBe(268);
    expect(Money.fromReais(-1.005).cents).toBe(-101);
    expect(Money.fromReais(0.005).cents).toBe(1);
    expect(Money.fromReais(0.0049999).cents).toBe(0);
    expect(Money.fromReais(10.125).cents).toBe(1013);
    // Um valor que já chega com erro de conta é arredondado pelo que é.
    expect(Money.fromReais(0.1 + 0.2).cents).toBe(30);
    expect(Money.fromReais(1e-7).cents).toBe(0);
    expect(Money.fromReais(123456789.995).cents).toBe(12345679000);
    expect(Money.fromReais(2e15).cents).toBe(200000000000000000);
    // O Dart não tem `-0` inteiro; o centavo também não pode ter.
    expect(Money.fromReais(-0.0).cents === 0).toBe(true);
    expect(() => Money.fromReais(Number.NaN)).toThrow(UnsupportedError);
    expect(() => Money.fromReais(Number.POSITIVE_INFINITY)).toThrow(UnsupportedError);
  });

  it('o número do balanço não perde centavo (B21, decisão 125)', () => {
    // A CVM é lida em centavos exatos (`CvmAccountLine.fromText`), e o
    // `FundamentalsSnapshot` a guarda em reais `number`. A ida e volta
    // centavo → número → Money é exata em toda a faixa de um balanço: o
    // maior ativo total do universo passa pouco de R$ 1,5 trilhão, e o
    // double tem casa de centavo até R$ 90 trilhões.
    const cases = [
      1,
      99,
      12345,
      123456789,
      150000000000037, // R$ 1,5 trilhão e 37 centavos
      987654321098765, // R$ 9,9 trilhões
      -4567890123401,
    ];
    const rnd = new SeededRandom(7);
    for (let i = 0; i < 20000; i++) {
      cases.push(rnd.nextInt(2 ** 32) * rnd.nextInt(2 ** 20) * (rnd.nextBool() ? 1 : -1));
    }
    for (const c of cases) {
      if (Math.abs(c) >= 1e17) continue; // fora do alcance de centavo do double
      expect(Money.fromReais(c / 100).cents, `${c} centavos`).toBe(c);
    }
  });

  it('somas repetidas não acumulam erro de ponto flutuante', () => {
    // Em double, somar 0,10 dez vezes produz 0.9999999999999999.
    let total = Money.zero;
    for (let i = 0; i < 10; i++) total = total.plus(Money.fromReais(0.1));
    expect(total.cents).toBe(100);
    expect(total.reais).toBe(1.0);
  });

  it('multiplicação por peso arredonda para o centavo', () => {
    expect(Money.fromReais(1000).times(1 / 3).cents).toBe(33333);
  });

  it('comparações e sinal', () => {
    expect(Money.fromReais(3).lte(Money.fromReais(5))).toBe(true);
    expect(Money.fromReais(-2).isPositive).toBe(false);
    expect(Money.fromReais(2).negate().cents).toBe(-200);
    expect(Money.zero.isZero).toBe(true);
  });
});

describe('Ticker', () => {
  it('normaliza e valida formato da B3', () => {
    expect(Ticker.parse(' petr4 ').value).toBe('PETR4');
    expect(Ticker.parse('taee11').value).toBe('TAEE11');
  });

  it('rejeita formatos inválidos', () => {
    expect(() => Ticker.parse('PET')).toThrow(FormatException);
    expect(() => Ticker.parse('PETR4X')).toThrow(FormatException);
    expect(Ticker.tryParse('!!!')).toBeNull();
  });

  it('Units são ações e não recebem tratamento especial', () => {
    // O universo vem de type=stock, que já exclui fundos; não há inferência
    // de classe pelo sufixo 11.
    expect(Ticker.parse('TAEE11').value).toBe('TAEE11');
    expect(Ticker.parse('BRBI11').value).toBe('BRBI11');
  });

  it('aceita dígito na raiz — B3SA3 é a própria bolsa', () => {
    // Um padrão de quatro letras excluiria B3SA3 da lista de ativos.
    expect(Ticker.parse('B3SA3').value).toBe('B3SA3');
    expect(Ticker.tryParse('B3SA3')).not.toBeNull();
  });

  it('rejeita ticker do mercado fracionário', () => {
    // PETR4F é o mesmo ativo que PETR4, negociado em lote fracionário.
    // Admiti-lo permitiria montar carteira com os dois como se fossem
    // empresas distintas. A fonte lista 403 deles em type=stock.
    expect(Ticker.tryParse('PETR4F')).toBeNull();
    expect(Ticker.tryParse('BBAS3F')).toBeNull();
    expect(Ticker.tryParse('VALE3F')).toBeNull();
  });

  it('rejeita classes especiais com sufixo de letra', () => {
    expect(Ticker.tryParse('MRSA6B')).toBeNull();
    expect(Ticker.tryParse('EQMA3B')).toBeNull();
  });

  it('primeiro caractere precisa ser letra', () => {
    expect(Ticker.tryParse('3PTR4')).toBeNull();
  });

  it('igualdade por valor — e a mesma instância, que serve de chave de Map', () => {
    expect(Ticker.parse('VALE3').equals(Ticker.parse('vale3'))).toBe(true);
    expect(Ticker.parse('VALE3')).toBe(Ticker.parse('vale3'));
  });
});

describe('Weights', () => {
  it('distribuição igualitária soma exatamente 1,0', () => {
    for (const n of [1, 3, 7, 15]) {
      const tickers = Array.from({ length: n }, (_, i) => Ticker.parse(`AAAA${i}`));
      const weights = Weights.equal(tickers);
      expectClose(Weights.sum(weights.values()), 1.0, 1e-12, `falhou com ${n} ativos`);
      expect(Weights.sumsToOne(weights.values())).toBe(true);
    }
  });

  it('três ativos: resíduo de 1/3 é absorvido, não perdido', () => {
    const tickers = [Ticker.parse('PETR4'), Ticker.parse('VALE3'), Ticker.parse('ITUB4')];
    expectClose(Weights.sum(Weights.equal(tickers).values()), 1.0, 1e-15);
  });

  it('rejeita peso fora do intervalo', () => {
    expect(() => Weight.fraction(1.5)).toThrow(ArgumentError);
    expect(() => Weight.fraction(-0.1)).toThrow(ArgumentError);
  });
});

describe('DateRange', () => {
  it('calcula anos', () => {
    expectClose(new DateRange(day(2020, 1, 15), day(2025, 1, 15)).years, 5.0, 0.02);
  });

  it('rejeita intervalo invertido', () => {
    expect(() => new DateRange(day(2025, 1, 1), day(2020, 1, 1))).toThrow(ArgumentError);
  });
});
