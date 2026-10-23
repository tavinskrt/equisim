import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  AuditEvent,
  AuditIds,
  AuditRecorder,
  CalculationTrace,
  CapmInputs,
  DateTime,
  FundamentalsSnapshot,
  Ticker,
  TraceSample,
  TraceSamplePoint,
  ValuationCascade,
  ValuationInputs,
  ValuationModel,
} from '../../src/core';
import { day, expectClose } from './helpers';

/** Fixtures mínimas para uma cascata que chega ao DCF por FCFF. */
const history = (ticker: Ticker): FundamentalsSnapshot[] => {
  const out: FundamentalsSnapshot[] = [];
  for (let year = 2016; year <= 2025; year++) {
    const k = year - 2015;
    out.push(
      new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(year, 12, 31),
        netIncome: 1000.0 * k,
        ebit: 1400.0 * k,
        ebitda: 1800.0 * k,
        incomeBeforeTax: 1300.0 * k,
        incomeTaxExpense: 300.0 * k,
        interestExpense: 120.0,
        operatingCashFlow: 1600.0 * k,
        freeCashFlow: 1200.0 * k,
        shortTermDebt: 400.0,
        longTermDebt: 1600.0,
        cash: 300.0,
        nopat: 1000.0 * k,
        sharesOutstanding: 1000.0,
        sharesOutstandingAsOf: 1000.0,
        marketCap: 20000.0,
        // Patrimônio acompanhando o lucro retido: é o que reconstitui base de
        // capital e retorno, sem os quais nenhuma via se sustenta.
        bookValuePerShare: 8.0 * k,
        enterpriseToEbitda: 6.0,
      }),
    );
  }
  return out;
};

const inputsFor = (ticker: Ticker): ValuationInputs =>
  new ValuationInputs({
    ticker,
    asOf: day(2026, 8, 20),
    fundamentals: history(ticker),
    marketPrice: 20.0,
    capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055 }),
    projectionYears: 5,
  });

const ticker = Ticker.parse('PETR4');

it('o WACC pondera o capital próprio pelo divisor, e não pelo VM da fonte — decisão 83', () => {
  // Sem beta desalavancado, a taxa sai do WACC estático. Com o valor de
  // mercado da fonte 2,6x menor que o real — o erro de contagem que a ponte
  // arbitra —, o peso do capital próprio não pode readquirir o erro: o
  // divisor é conciliado pelas demonstrações, e o WACC tem de ser o mesmo do
  // caso consistente.
  const consistent = ValuationCascade.evaluate(inputsFor(ticker)).unwrap();
  const corrupted = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 8, 20),
      fundamentals: history(ticker).map(
        (s) =>
          new FundamentalsSnapshot({
            ticker: s.ticker,
            fiscalPeriodEnd: s.fiscalPeriodEnd,
            netIncome: s.netIncome,
            ebit: s.ebit,
            ebitda: s.ebitda,
            incomeBeforeTax: s.incomeBeforeTax,
            incomeTaxExpense: s.incomeTaxExpense,
            interestExpense: s.interestExpense,
            operatingCashFlow: s.operatingCashFlow,
            freeCashFlow: s.freeCashFlow,
            shortTermDebt: s.shortTermDebt,
            longTermDebt: s.longTermDebt,
            cash: s.cash,
            nopat: s.nopat,
            sharesOutstanding: s.sharesOutstanding,
            sharesOutstandingAsOf: s.sharesOutstandingAsOf,
            marketCap: 20000.0 / 2.6,
            bookValuePerShare: s.bookValuePerShare,
            enterpriseToEbitda: s.enterpriseToEbitda,
          }),
      ),
      marketPrice: 20.0,
      capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055 }),
      projectionYears: 5,
    }),
  ).unwrap();
  expectClose(corrupted.discountRate, consistent.discountRate, 1e-12);
});

describe('com o coletor isolado', () => {
  beforeEach(() => AuditRecorder.detach());
  afterEach(() => AuditRecorder.detach());

  it('o rastro da via da firma descreve a conta que o preço sai — decisão 102', () => {
    // A ponte `EV − D` saiu do preço, e o rastro continuava mostrando-a: a
    // lente `metodo` apontou em 16/09/2026. O passo do capital próprio precisa
    // somar ao preço justo que a avaliação devolve.
    const events: AuditEvent[] = [];
    AuditRecorder.attach((e) => events.push(e));
    const r = ValuationCascade.evaluate(inputsFor(ticker)).unwrap();
    expect(r.model).toBe(ValuationModel.dcfFcff);
    const calculations = events[events.length - 1]!.calculations;
    expect(calculations.map((c) => c.formulaName)).not.toContain('Ponte do valor da firma ao preço justo por papel');
    const steps = calculations.filter((c) => c.formulaName === 'Capital próprio pelo fluxo do acionista derivado');
    expect(steps).toHaveLength(1);
    expectClose(steps[0]!.finalValue, r.fairValue.reais, 0.005);
  });

  describe('AuditRecorder', () => {
    it('desligado, não constrói transação nenhuma', () => {
      expect(AuditRecorder.isActive).toBe(false);
      expect(AuditRecorder.begin('/qualquer')).toBeNull();
    });

    it('ligado, entrega o evento ao consumidor acoplado', () => {
      const received: AuditEvent[] = [];
      AuditRecorder.attach((e) => received.push(e));

      const transaction = AuditRecorder.begin('/core/teste', { inputPayload: { a: 1 } });
      transaction!.step({
        formulaName: 'Soma',
        latex: String.raw`c = a + b`,
        variables: { a: 1, b: 2 },
        steps: ['Passo 1: 1 + 2 = 3'],
        result: 3,
        unit: 'unidades',
      });
      transaction!.complete({ c: 3 });

      expect(received).toHaveLength(1);
      expect(received[0]!.endpoint).toBe('/core/teste');
      expect(received[0]!.calculations).toHaveLength(1);
      expect(received[0]!.calculations[0]!.formulaName).toBe('Soma');
      expect(received[0]!.calculations[0]!.finalValue).toBe(3);
    });

    it('concluir duas vezes não duplica o evento', () => {
      const received: AuditEvent[] = [];
      AuditRecorder.attach((e) => received.push(e));

      const transaction = AuditRecorder.begin('/core/teste')!;
      transaction.complete({ ok: true });
      transaction.complete({ ok: true });
      expect(transaction.transactionId).not.toBe('');
      expect(received).toHaveLength(1);
    });
  });

  describe('Contrato de serialização', () => {
    it('o evento sobrevive à ida e volta em JSON', () => {
      const original = new AuditEvent({
        transactionId: AuditIds.uuidV4(),
        timestamp: DateTime.local(2026, 8, 23, 14, 32, 10),
        endpoint: '/core/valuation/PETR4',
        inputPayload: { marketPrice: 38.4 },
        outputPayload: { fairValue: 51.2 },
        executionTimeMs: 142,
        calculations: [
          new CalculationTrace({
            formulaName: 'CAPM',
            latexRepresentation: String.raw`K_e = R_f + \beta (R_m - R_f)`,
            mappedVariables: { R_f: 10.5, beta: 1.2 },
            intermediateSteps: ['Passo 1: 1,2 × 5,5% = 6,6%'],
            finalValue: 17.1,
            unit: '% a.a.',
          }),
        ],
      });

      // O canal entre janelas e o arquivo exportado passam pelo texto: a ida
      // e volta é pelo JSON serializado, e não pelo objeto.
      const restored = AuditEvent.fromJson(JSON.parse(JSON.stringify(original.toJson())) as Record<string, unknown>);

      expect(restored.transactionId).toBe(original.transactionId);
      expect(restored.timestamp.toUtc().toIso8601String()).toBe(original.timestamp.toUtc().toIso8601String());
      expect(restored.endpoint).toBe(original.endpoint);
      expect(restored.inputPayload).toEqual(original.inputPayload);
      expect(restored.outputPayload).toEqual(original.outputPayload);
      expect(restored.executionTimeMs).toBe(142);
      expect(restored.calculations).toHaveLength(1);
      expect(restored.calculations[0]!.latexRepresentation).toBe(original.calculations[0]!.latexRepresentation);
      expect(restored.calculations[0]!.mappedVariables['beta']).toBe(1.2);
      expect(restored.calculations[0]!.finalValue).toBe(17.1);
    });

    it('a amostra da mediana sobrevive à ida e volta em JSON', () => {
      // O painel roda em outra janela: o que não atravessar o BroadcastChannel
      // simplesmente não existe para quem audita.
      const trace = new CalculationTrace({
        formulaName: 'Normalização do fluxo-base',
        latexRepresentation: String.raw`F_0 = \min(\max(F_{obs}, m(1-\tau)), m(1+\tau))`,
        finalValue: 0.702,
        unit: 'R$',
        sample: new TraceSample({
          title: 'Exercícios da amostra',
          unit: 'R$',
          summary: 0.468,
          lowerBound: 0.234,
          upperBound: 0.702,
          selected: 0.702,
          points: [
            new TraceSamplePoint({ label: '2021', value: 0.38 }),
            new TraceSamplePoint({ label: '2022', value: 0.242 }),
            new TraceSamplePoint({ label: '2023', value: 0.468, definesResult: true }),
            new TraceSamplePoint({ label: '2024', value: 0.866 }),
            new TraceSamplePoint({ label: '2025', value: 4.445, isObserved: true }),
          ],
        }),
      });

      const restored = CalculationTrace.fromJson(trace.toJson());
      const sample = restored.sample!;

      expect(sample.points.map((p) => p.label)).toEqual(['2021', '2022', '2023', '2024', '2025']);
      expect(sample.points[2]!.definesResult).toBe(true);
      expect(sample.points[sample.points.length - 1]!.isObserved).toBe(true);
      expect(sample.summary).toBe(0.468);
      expect(sample.lowerBound).toBe(0.234);
      expect(sample.upperBound).toBe(0.702);
      expect(sample.selected).toBe(0.702);
    });

    it('rastro sem amostra não carrega a chave no JSON', () => {
      const trace = new CalculationTrace({
        formulaName: 'CAPM',
        latexRepresentation: String.raw`K_e = R_f + \beta (R_m - R_f)`,
      });
      expect('sample' in trace.toJson()).toBe(false);
      expect(CalculationTrace.fromJson(trace.toJson()).sample).toBeNull();
    });

    it('uuid v4 tem o formato da RFC 4122', () => {
      const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
      for (let i = 0; i < 200; i++) {
        expect(AuditIds.uuidV4()).toMatch(pattern);
      }
    });
  });

  describe('Instrumentação da cascata', () => {
    it('sem coletor acoplado, o resultado é idêntico', () => {
      const withoutAudit = ValuationCascade.evaluate(inputsFor(ticker));

      const captured: AuditEvent[] = [];
      AuditRecorder.attach((e) => captured.push(e));
      const withAudit = ValuationCascade.evaluate(inputsFor(ticker));
      AuditRecorder.detach();

      expect(withoutAudit.isOk).toBe(true);
      expect(withAudit.isOk).toBe(true);
      // O ponto do teste: instrumentar não pode mover o número. Se mexer, a
      // auditoria estaria documentando um cálculo que não é o de produção.
      expect(withAudit.unwrap().fairValue.cents).toBe(withoutAudit.unwrap().fairValue.cents);
      expect(withAudit.unwrap().discountRate).toBe(withoutAudit.unwrap().discountRate);
      expect(withAudit.unwrap().model).toBe(withoutAudit.unwrap().model);
    });

    it('uma avaliação bem-sucedida emite um evento com as fórmulas', () => {
      const captured: AuditEvent[] = [];
      AuditRecorder.attach((e) => captured.push(e));

      const result = ValuationCascade.evaluate(inputsFor(ticker));

      expect(result.isOk).toBe(true);
      expect(captured).toHaveLength(1);

      const event = captured[0]!;
      expect(event.endpoint).toBe('/core/valuation/PETR4');
      expect(event.outputPayload['status']).toBe('ok');
      expect(event.inputPayload['ticker']).toBe('PETR4');

      const names = event.calculations.map((c) => c.formulaName);
      expect(names).toContain('Custo do capital próprio (CAPM)');
      expect(
        names.some((n) => n.includes('WACC') || n.includes('degeneração')),
        'a taxa de desconto precisa estar documentada',
      ).toBe(true);
      expect(names.some((n) => n.includes('perpetuidade'))).toBe(true);
      expect(names[names.length - 1], 'o veredito fecha a cadeia de raciocínio').toBe(
        'Margem de segurança e potencial de valorização',
      );
    });

    it('cada fórmula traz símbolos, etapas e resultado', () => {
      const captured: AuditEvent[] = [];
      AuditRecorder.attach((e) => captured.push(e));
      ValuationCascade.evaluate(inputsFor(ticker));

      for (const trace of captured[0]!.calculations) {
        expect(trace.latexRepresentation, `${trace.formulaName} sem expressão em LaTeX`).not.toBe('');
        expect(trace.intermediateSteps.length, `${trace.formulaName} sem decomposição`).toBeGreaterThan(0);
        expect(Object.keys(trace.mappedVariables).length, `${trace.formulaName} sem variáveis mapeadas`).toBeGreaterThan(
          0,
        );
        expect(trace.finalValue, `${trace.formulaName} sem resultado`).not.toBeNull();
      }
    });

    it('a convergência ao ciclo publica a amostra de retorno, por ano', () => {
      const captured: AuditEvent[] = [];
      AuditRecorder.attach((e) => captured.push(e));
      ValuationCascade.evaluate(inputsFor(ticker));

      const base = captured[0]!.calculations.find((c) => c.formulaName.includes('Base do fluxo'))!;
      const sample = base.sample!;

      // A amostra é do **retorno** sobre a base de capital, não do fluxo
      // absoluto: é sobre ele que a decisão 25 passou a normalizar, e é a série
      // que precisa ficar visível para quem confere a conta.
      expect(sample.title).toContain('Retorno');
      expect(sample.summaryLabel).toBe('mediana do ciclo');
      expect(sample.unit).toBe('%');

      // Um retorno por exercício, a partir do segundo — o primeiro só fornece a
      // base de abertura.
      expect(sample.points.length).toBeGreaterThan(0);
      expect(sample.points[sample.points.length - 1]!.isObserved).toBe(true);
      const central = sample.points.filter((p) => p.definesResult).length;
      expect(central >= 1 && central <= 2, 'um ponto central em amostra ímpar, dois em par').toBe(true);

      // A mediana publicada é a dos pontos publicados, exceto o observado —
      // que é justamente o que se compara contra o ciclo.
      const window = sample.points.filter((p) => !p.isObserved).map((p) => p.value);
      window.sort((a, b) => a - b);
      const mid = Math.trunc(window.length / 2);
      const median = window.length % 2 === 1 ? window[mid]! : (window[mid - 1]! + window[mid]!) / 2;
      expectClose(sample.summary, median, 0.02);
    });

    it('o CAPM registrado reproduz o Ke usado no desconto', () => {
      const captured: AuditEvent[] = [];
      AuditRecorder.attach((e) => captured.push(e));
      const inputs = inputsFor(ticker);
      ValuationCascade.evaluate(inputs);

      const capm = captured[0]!.calculations.find((c) => c.formulaName.includes('CAPM'))!;

      // A conferência que a banca faria à mão, feita no teste.
      const rf = capm.mappedVariables['R_f (% a.a.)'] as number;
      const beta = capm.mappedVariables['beta'] as number;
      const premium = capm.mappedVariables['R_m - R_f (% a.a.)'] as number;

      expectClose(rf + beta * premium, capm.finalValue!, 0.01);
      expectClose(capm.finalValue! / 100, inputs.capm.costOfEquity, 1e-4);
    });

    it('avaliação recusada também emite evento, com o motivo', () => {
      const captured: AuditEvent[] = [];
      AuditRecorder.attach((e) => captured.push(e));

      const result = ValuationCascade.evaluate(
        new ValuationInputs({
          ticker,
          asOf: day(2026, 8, 20),
          fundamentals: [],
          marketPrice: 20.0,
          capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
        }),
      );

      expect(result.isErr).toBe(true);
      expect(captured).toHaveLength(1);
      expect(captured[0]!.outputPayload['status']).toBe('falha');
      expect(typeof captured[0]!.outputPayload['motivo']).toBe('string');
    });
  });
});
