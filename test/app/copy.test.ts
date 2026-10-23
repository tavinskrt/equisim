import { describe, expect, it } from 'vitest';

import {
  InvalidInput,
  ManualGroup,
  ManualTerminal,
  MultipleKind,
  MultipleRefusal,
  OrderingReading,
  QuantityUnit,
  ScenarioBand,
  SkillReading,
  SkillReadingCodec,
  TransversalOrdering,
  ValuationCaveat,
  ValuationModel,
} from '../../src/core';
import { DomainCopy, FailureCopy, Fmt, SkillCopy } from '../../src/copy';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { readPublicJson } from '../data/public-assets';

/**
 * Item B21, decisões 122 e 125 — **o erro do núcleo transporta a grandeza, e
 * a frase é montada na apresentação**; o rótulo de tela saiu dos enums.
 */
describe('A apresentação escreve o número, e na unidade certa', () => {
  it('fração vira percentual', () => {
    const text = FailureCopy.of(
      new InvalidInput('Os pesos devem somar 100%.', {
        field: 'weights',
        actual: 0.7,
        limit: 1.0,
        unit: QuantityUnit.fraction,
      }),
    );
    expect(text).toContain('Entrada inválida');
    expect(text).toContain('70,0%');
    expect(text).toContain('100,0%');
  });

  it('contagem vira inteiro, sem casa decimal', () => {
    const text = FailureCopy.of(
      new InvalidInput('Limite de ativos por carteira excedido.', {
        field: 'assets',
        actual: 18,
        limit: 15,
        unit: QuantityUnit.count,
      }),
    );
    expect(text).toContain('Informado: 18.');
    expect(text).toContain('Limite: 15.');
    expect(text, 'meio ativo não existe').not.toContain('18,0');
  });

  it('sem unidade declarada, a tela não inventa número', () => {
    const text = FailureCopy.of(new InvalidInput('O prazo deve ser de ao menos um mês.', { field: 'months' }));
    expect(text).toContain('O prazo deve ser de ao menos um mês.');
    expect(text).not.toContain('Informado');
  });

  it('sem limite, escreve só o medido', () => {
    const text = FailureCopy.of(new InvalidInput('Regra qualquer.', { actual: 0.42, unit: QuantityUnit.fraction }));
    expect(text).toContain('Informado: 42,0%.');
    expect(text).not.toContain('Limite');
  });
});

describe('Rótulos de tela dos enums', () => {
  const check = <T extends { name: string }>(values: readonly T[], label: (v: T) => string) => {
    const labels = values.map(label);
    values.forEach((v, i) => {
      expect(labels[i]!.trim().length, v.name).toBeGreaterThan(0);
      expect(labels[i], v.name).not.toBe(v.name);
    });
    expect(new Set(labels).size, 'dois valores com o mesmo rótulo').toBe(values.length);
  };

  it('todo valor tem rótulo próprio', () => {
    check(ValuationModel.values, DomainCopy.model);
    check(ScenarioBand.values, DomainCopy.band);
    check(ValuationCaveat.values, DomainCopy.caveat);
    check(TransversalOrdering.values, DomainCopy.ordering);
    check(MultipleKind.values, DomainCopy.multiple);
    check(MultipleRefusal.values, DomainCopy.refusal);
    check(ManualGroup.values, DomainCopy.group);
    check(ManualTerminal.values, DomainCopy.terminal);
  });

  it('a tela lê o que lia antes da mudança', () => {
    expect(DomainCopy.model(ValuationModel.dcfFcff)).toBe('DCF por fluxo da firma');
    // Pelas premissas, e não pelo resultado (decisão 148, item B38).
    expect(DomainCopy.band(ScenarioBand.bear)).toBe('Premissas mais duras');
    expect(DomainCopy.band(ScenarioBand.bull)).toBe('Premissas mais brandas');
    expect(DomainCopy.multiple(MultipleKind.evToEbitda)).toBe('EV/EBITDA');
  });
});

describe('A ressalva do prêmio segue a medição, e não um texto fixo (item B1.0)', () => {
  const order = (ic: number, passes = false) =>
    new OrderingReading({ ic, overlapT: passes ? 3.1 : 0.7, overlapCritical: 2.7, neweyWestT: passes ? 3.0 : 1.2 });

  const reading = (o: {
    t?: number;
    nw?: number;
    upsideIc?: number;
    icBm?: number;
    bmPasses?: boolean;
    compositePasses?: boolean;
    upsidePasses?: boolean;
  } = {}) =>
    new SkillReading({
      months: 36,
      cohorts: 22,
      conditionalCoefficient: 0.03,
      overlapT: o.t ?? 0.24,
      overlapCritical: 2.7,
      neweyWestT: o.nw ?? 0.69,
      orderings: new Map([
        [TransversalOrdering.composite, order(0.15, o.compositePasses)],
        [TransversalOrdering.bookToMarket, order(o.icBm ?? 0.18, o.bmPasses)],
        [TransversalOrdering.potential, order(o.upsideIc ?? 0.09, o.upsidePasses)],
      ]),
    });

  it('com a leitura do pacote, diz de onde sai o prêmio e o que se mediu do potencial', () => {
    const packaged = SkillReadingCodec.decode(readPublicJson(AssetPaths.skillReading))!;
    expect(packaged.demonstrated, 'se o C1 aprovar, este teste muda junto com o plano').toBe(false);
    const text = SkillCopy.caveat(packaged)!;
    const premium = packaged.premiumOrdering;
    if (premium === null) expect(text).toContain('O retorno esperado não leva prêmio');
    else expect(text).toContain(`O prêmio sobre o Ke sai de ${DomainCopy.ordering(premium)}`);
    expect(text).toContain('O potencial do valuation sozinho não comprovou');
    expect(text).toContain(`t corrigido de ${Fmt.ratio(packaged.overlapT, 2)}`);
  });

  it('com o potencial comprovado e dando o prêmio, a ressalva some', () => {
    expect(SkillCopy.caveat(reading({ t: 3.1, nw: 2.4, upsidePasses: true }))).toBeNull();
  });

  it('sem pacote, diz que não mediu, e o esperado fica sem prêmio', () => {
    const text = SkillCopy.caveat(null)!;
    expect(text).toContain('não veio medida');
    expect(text).toContain('sem prêmio');
  });

  it('a ordenação do prêmio é a da regra, com o número dela', () => {
    expect(SkillCopy.caveat(reading({ bmPasses: true }))).toContain(
      'O prêmio sobre o Ke sai de o valor patrimonial sobre o preço',
    );
    const composite = SkillCopy.caveat(reading({ bmPasses: true, compositePasses: true }))!;
    expect(composite).toContain('sai de o composto');
    expect(composite).toContain('correlação de postos de 0,15');
  });

  it('nenhuma ordenação comprovada: sem prêmio, e a tela diz', () => {
    const nothing = SkillCopy.caveat(reading())!;
    expect(nothing.startsWith('Nenhuma ordenação comprovou habilidade')).toBe(true);
    expect(nothing).toContain('é o Ke de cada ativo');
  });

  it('ordenar pior que o B/M só é dito quando o IC é menor', () => {
    expect(SkillCopy.caveat(reading())).toContain('ordenou pior que ele — correlação de postos de 0,09 contra 0,18');
    expect(SkillCopy.caveat(reading({ upsideIc: 0.2 }))).not.toContain('pior');
  });

  it('a perna do critério que falhou é a que a frase cita', () => {
    const nw = SkillCopy.caveat(reading({ t: 2.9, nw: 1.5 }))!;
    expect(nw).toContain('não passou no Newey-West');
    expect(nw).toContain('t de 1,50, contra 2,00 exigido');
  });
});

describe('Formatação brasileira', () => {
  it('vírgula decimal, ponto de milhar e sinal explícito só quando pedido', () => {
    expect(Fmt.percent(0.155)).toBe('15,50%');
    expect(Fmt.percent(0.155, { decimals: 1, signed: true })).toBe('+15,5%');
    expect(Fmt.percent(-0.02, { signed: true })).toBe('-2,00%');
    expect(Fmt.percent(0, { signed: true })).toBe('0,00%');
    expect(Fmt.percent(Number.NaN)).toBe('—');
    expect(Fmt.ratio(1234.5, 1)).toBe('1.234,5');
    expect(Fmt.points(3.5)).toBe('+3,5 p.p.');
    expect(Fmt.months(125)).toBe('10 anos e 5 meses');
    expect(Fmt.money(1234.56).replace(/\s/g, ' ')).toBe('R$ 1.234,56');
  });
});
