import { describe, expect, it } from 'vitest';

import {
  CurveVertex,
  DateTime,
  TreasuryCsv,
  TreasuryCurve,
  TreasuryQuote,
  TreasuryQuotesCodec,
  YieldCurve,
} from '../../src/core';
import { expectClose, expectDate } from './helpers';

const ref = DateTime.utc(2026, 9, 10);

const curve = (pts: readonly (readonly [number, number])[]): YieldCurve =>
  YieldCurve.of(
    ref,
    pts.map(([y, r]) => new CurveVertex(y, r)),
  )!;

describe('Curva', () => {
  it('plana devolve a mesma taxa em todo prazo e todo forward', () => {
    const c = curve([
      [0.5, 0.1],
      [2, 0.1],
      [5, 0.1],
      [10, 0.1],
    ]);
    for (const t of [0.25, 1.0, 3.7, 10.0, 15.0]) expectClose(c.spotRate(t), 0.1, 1e-12, `spot ${t}`);
    for (const f of c.annualForwards(12)) expectClose(f, 0.1, 1e-12);
    expectClose(c.terminalRate(10), 0.1, 1e-12);
  });

  it('reproduz a taxa de cada vértice', () => {
    const c = curve([
      [0.3, 0.1356],
      [2.3, 0.1393],
      [5.3, 0.1429],
      [10.3, 0.1433],
    ]);
    for (const v of c.vertices) expectClose(c.spotRate(v.years), v.rate, 1e-12);
  });

  it('o forward entre dois vértices fecha o fator composto', () => {
    // (1+z2)^t2 = (1+z1)^t1 · (1+f)^(t2−t1)
    const c = curve([
      [1, 0.1],
      [3, 0.12],
      [5, 0.13],
    ]);
    const f = c.forwardRate(1, 3);
    expectClose(Math.pow(1.1, 1) * Math.pow(1 + f, 2), Math.pow(1.12, 3), 1e-12);
  });

  it('curva inclinada: forward acima da taxa à vista', () => {
    const c = curve([
      [1, 0.05],
      [5, 0.08],
      [10, 0.1],
    ]);
    expect(c.forwardRate(4, 5)).toBeGreaterThan(c.spotRate(5));
    const fw = c.annualForwards(10);
    expect(fw[0]).toBeLessThan(fw[fw.length - 1]!);
  });

  it('além do último vértice segue o forward do último segmento', () => {
    const c = curve([
      [1, 0.1],
      [5, 0.11],
      [10, 0.12],
    ]);
    const last = c.forwardRate(5, 10);
    expectClose(c.forwardRate(10, 11), last, 1e-12);
    expectClose(c.terminalRate(15), last, 1e-12);
  });

  it('antes do primeiro vértice, taxa à vista plana', () => {
    const c = curve([
      [1, 0.1],
      [5, 0.11],
      [10, 0.12],
    ]);
    expectClose(c.spotRate(0.5), 0.1, 1e-12);
  });
});

describe('Montagem', () => {
  it('com menos de três vértices não há curva', () => {
    expect(
      YieldCurve.of(ref, [new CurveVertex(1, 0.1), new CurveVertex(5, 0.11)]),
      'dois pontos são a interpolação que a curva veio substituir',
    ).toBeNull();
  });

  it('descarta o que é registro corrompido', () => {
    const c = YieldCurve.of(ref, [
      new CurveVertex(1, 0.1),
      new CurveVertex(-1, 0.1),
      new CurveVertex(2, Number.NaN),
      new CurveVertex(3, 1.5),
      new CurveVertex(5, 0.11),
      new CurveVertex(10, 0.12),
    ])!;
    expect(c.vertices.length).toBe(3);
  });

  it('prazo repetido fica com o primeiro informado', () => {
    const c = YieldCurve.of(ref, [
      new CurveVertex(2, 0.1393), // LTN
      new CurveVertex(2, 0.1373), // NTN-F de mesmo vencimento
      new CurveVertex(5, 0.14),
      new CurveVertex(10, 0.143),
    ])!;
    expectClose(c.spotRate(2), 0.1393, 1e-12);
  });
});

describe('Tesouro Direto', () => {
  const q = (kind: string, maturity: DateTime, base: DateTime, rate: number): TreasuryQuote =>
    new TreasuryQuote({ type: kind, maturity, baseDate: base, rate });

  const friday = DateTime.utc(2026, 9, 11);
  const thursday = DateTime.utc(2026, 9, 10);
  const day = (base: DateTime, shift: number): TreasuryQuote[] => [
    q(TreasuryCurve.ltn, DateTime.utc(2027, 1, 1), base, 0.1356 + shift),
    q(TreasuryCurve.ltn, DateTime.utc(2029, 1, 1), base, 0.1393 + shift),
    q(TreasuryCurve.ntnF, DateTime.utc(2029, 1, 1), base, 0.1373 + shift),
    q(TreasuryCurve.ntnF, DateTime.utc(2037, 1, 1), base, 0.1433 + shift),
    q('Tesouro Selic', DateTime.utc(2030, 1, 1), base, 0.0001),
  ];

  it('usa a data-base mais recente até a avaliação', () => {
    const c = TreasuryCurve.at([...day(thursday, 0), ...day(friday, 0.01)], DateTime.utc(2026, 9, 13))!;
    expectDate(c.referenceDate, friday);
  });

  it('NUNCA olha para a frente', () => {
    // Avaliando na quinta, a curva de sexta ainda não existia.
    const c = TreasuryCurve.at([...day(thursday, 0), ...day(friday, 0.01)], thursday)!;
    expectDate(c.referenceDate, thursday);
    expectClose(c.vertices[0]!.rate, 0.1356, 1e-12);
  });

  it('sem data-base na última semana, não inventa curva', () => {
    expect(TreasuryCurve.at(day(thursday, 0), DateTime.utc(2026, 9, 30))).toBeNull();
  });

  it('LTN vence a NTN-F no mesmo vencimento, e a Selic não entra', () => {
    const c = TreasuryCurve.at(day(thursday, 0), thursday)!;
    expect(c.vertices.length, 'duas LTN e uma NTN-F longa; a NTN-F de 2029 e a Selic saem').toBe(3);
    const two = c.vertices.find((v) => v.years > 2 && v.years < 3)!;
    expectClose(two.rate, 0.1393, 1e-12);
  });

  it('o prazo é em dias úteis ÷ 252, como o PU do Tesouro — decisão 79', () => {
    const c = TreasuryCurve.at(day(thursday, 0), thursday)!;
    // `du` conferido contra o PU das LTN de 10/09/2026: 76 e 575.
    expectClose(c.vertices[0]!.years, 76 / 252, 1e-12);
    expectClose(c.vertices[1]!.years, 575 / 252, 1e-12);
  });
});

describe('Arquivo e pacote do Tesouro — item A2.1', () => {
  it('lê a linha do prefixado, e ignora cabeçalho e outros títulos', () => {
    const q = TreasuryCsv.parseLine('Tesouro Prefixado;01/01/2027;10/09/2026;13,56;13,68;960,00;959,00;959,00')!;
    expect(q.type).toBe(TreasuryCurve.ltn);
    expectDate(q.maturity, DateTime.utc(2027, 1, 1));
    expectDate(q.baseDate, DateTime.utc(2026, 9, 10));
    expectClose(q.rate, 0.1356, 1e-12);
    expect(TreasuryCsv.parseLine('Tipo Titulo;Data Vencimento;Data Base;Taxa')).toBeNull();
    expect(TreasuryCsv.parseLine('Tesouro Selic;01/03/2027;10/09/2026;0,01')).toBeNull();
    expect(TreasuryCsv.parseLine('Tesouro Prefixado;xx;10/09/2026;13,5')).toBeNull();
  });

  it('a data-base de qualquer título marca o fim do bloco', () => {
    expectDate(TreasuryCsv.baseDateOf('Tesouro Selic;01/03/2027;10/09/2026;0,01'), DateTime.utc(2026, 9, 10));
    expect(TreasuryCsv.baseDateOf('Tipo Titulo;Data Vencimento;Data Base')).toBeNull();
  });

  it('pacote de ida e volta, e versão desconhecida é lista vazia', () => {
    const q = new TreasuryQuote({
      type: TreasuryCurve.ntnF,
      maturity: DateTime.utc(2037, 1, 1),
      baseDate: DateTime.utc(2026, 9, 10),
      rate: 0.1433,
    });
    const json = TreasuryQuotesCodec.encode([q], { generatedAt: DateTime.utc(2026, 9, 10) });
    const decoded = TreasuryQuotesCodec.decode(json);
    expect(decoded).toHaveLength(1);
    const parsed = decoded[0]!;
    expect(parsed.type).toBe(q.type);
    expectDate(parsed.maturity, q.maturity);
    expectDate(parsed.baseDate, q.baseDate);
    expect(parsed.rate).toBe(q.rate);
    expect(TreasuryQuotesCodec.decode({ ...json, versao: 99 })).toEqual([]);
  });

  it('taxa corrompida no pacote fica de fora', () => {
    const json = {
      versao: TreasuryQuotesCodec.version,
      cotacoes: [{ tipo: TreasuryCurve.ltn, vencimento: '2027-01-01', dataBase: '2026-09-10', taxa: 13.56 }],
    };
    expect(TreasuryQuotesCodec.decode(json), 'taxa em percentual, e não em fração, é registro corrompido').toEqual([]);
  });
});
