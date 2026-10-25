import { describe, expect, it } from 'vitest';

import { CvmAccountLine, CvmChart, CvmLayout } from '../../src/core';
import { expectClose } from './helpers';

const line = (code: string, label: string, value: number): CvmAccountLine =>
  CvmAccountLine.approximate({ code, label, value });

/**
 * Linhas de nível ≤ 2 da DRE consolidada de uma companhia **não financeira**,
 * no plano padrão da CVM.
 */
const corporateIncomeStatement = (): CvmAccountLine[] => [
  line('3.01', 'Receita de Venda de Bens e/ou Serviços', 1000),
  line('3.02', 'Custo dos Bens e/ou Serviços Vendidos', -600),
  line('3.03', 'Resultado Bruto', 400),
  line('3.04', 'Despesas/Receitas Operacionais', -150),
  line('3.05', 'Resultado Antes do Resultado Financeiro e dos Tributos', 250),
  line('3.06', 'Resultado Financeiro', -50),
  line('3.07', 'Resultado Antes dos Tributos sobre o Lucro', 200),
  line('3.08', 'Imposto de Renda e Contribuição Social sobre o Lucro', -60),
  line('3.09', 'Resultado Líquido das Operações Continuadas', 140),
  line('3.10', 'Resultado Líquido de Operações Descontinuadas', 0),
  line('3.11', 'Lucro/Prejuízo Consolidado do Período', 140),
  line('3.99', 'Lucro por Ação - (Reais / Ação)', 1.4),
];

/**
 * DRE **consolidada** do layout de banco "**da** Intermediação Financeira" —
 * o do Itaú. Valores em bilhões, de 2024.
 */
const bankDaIntermediationConsolidated = (): CvmAccountLine[] => [
  line('3.01', 'Receitas da Intermediação Financeira', 335.3),
  line('3.02', 'Despesas da Intermediação Financeira', -199.6),
  line('3.03', 'Resultado Bruto Intermediação Financeira', 135.7),
  line('3.04', 'Outras Despesas/Receitas Operacionais', -88.2),
  line('3.05', 'Resultado Antes dos Tributos sobre o Lucro', 47.6),
  line('3.06', 'Imposto de Renda e Contribuição Social sobre o Lucro', -5.4),
  line('3.07', 'Resultado Líquido das Operações Continuadas', 42.1),
  line('3.08', 'Resultado Líquido das Operações Descontinuadas', 0),
  line('3.09', 'Lucro/Prejuízo Consolidado do Período', 42.1),
  line('3.99', 'Lucro por Ação - (R$ / Ação)', 3.9),
];

/** DRE **individual** do mesmo layout. Aqui `3.11` é uma armadilha. */
const bankDaIntermediationIndividual = (): CvmAccountLine[] => [
  line('3.01', 'Receitas da Intermediação Financeira', 20.6),
  line('3.05', 'Resultado Operacional', 33.6),
  line('3.07', 'Resultado Antes Tributação/Participações', 33.6),
  line('3.08', 'Provisão para IR e Contribuição Social', 3.7),
  line('3.09', 'IR Diferido', 0.0),
  line('3.10', 'Participações/Contribuições Estatutárias', -0.02),
  line('3.11', 'Reversão dos Juros sobre Capital Próprio', 0.0),
  line('3.13', 'Lucro/Prejuízo do Período', 37.3),
  line('3.99', 'Lucro por Ação - (R$ / Ação)', 3.5),
];

/**
 * Layout de banco "**de** Intermediação", em que o lucro volta ao 3.11 e
 * convive com uma linha de operações continuadas que também casa com "lucro".
 */
const bankDeIntermediationConsolidated = (): CvmAccountLine[] => [
  line('3.01', 'Receitas de Intermediação Financeira', 100),
  line('3.07', 'Lucro ou Prejuízo das Operações Continuadas', 25),
  line('3.11', 'Lucro ou Prejuízo Líquido Consolidado do Período', 22),
  line('3.99', 'Lucro por Ação - (R$ / Ação)', 2.2),
];

describe('Detecção de layout', () => {
  it('reconhece os quatro planos pela conta 3.01', () => {
    expect(CvmChart.of(corporateIncomeStatement()).layout).toBe(CvmLayout.corporate);
    expect(CvmChart.of(bankDaIntermediationConsolidated()).layout).toBe(CvmLayout.financialIntermediation);
    expect(CvmChart.of(bankDeIntermediationConsolidated()).layout).toBe(CvmLayout.financialIntermediation);
    expect(CvmChart.of([line('3.01', 'Receitas das Atividades Seguradoras/Resseguradoras', 10)]).layout).toBe(
      CvmLayout.insurer,
    );
  });

  it('a preposição não decide: "da" e "de" caem no mesmo layout', () => {
    // Os dois rótulos diferem por uma letra, e a conferência mostrou que
    // eles têm o lucro em códigos diferentes. Quem resolve isso é a busca
    // por descrição, não a detecção — o layout dos dois é o mesmo.
    expect(CvmChart.of(bankDaIntermediationConsolidated()).layout).toBe(
      CvmChart.of(bankDeIntermediationConsolidated()).layout,
    );
  });

  it('balanço sem DRE ainda é legível', () => {
    const c = CvmChart.of([line('1', 'Ativo Total', 900), line('1.01', 'Ativo Circulante', 300)]);
    expect(c.totalAssets).toBe(900);
    expect(c.currentAssets).toBe(300);
  });

  it('documento sem nada reconhecível não inventa layout', () => {
    const c = CvmChart.of([line('9.99', 'Outra coisa', 1)]);
    expect(c.layout).toBe(CvmLayout.unknown);
    expect(c.netIncome).toBeNull();
    expect(c.ebit).toBeNull();
  });
});

describe('Lucro líquido — onde o código engana', () => {
  it('não financeira: 3.11', () => {
    expect(CvmChart.of(corporateIncomeStatement()).netIncome).toBe(140);
  });

  it('banco consolidado: 3.09, e NÃO o 3.05 de antes dos tributos', () => {
    const c = CvmChart.of(bankDaIntermediationConsolidated());
    expect(c.netIncome).toBe(42.1);
    expect(c.netIncome).not.toBe(47.6);
  });

  it('banco individual: 3.13, e NÃO a reversão de JCP do 3.11', () => {
    // Esta é a armadilha que a conferência pegou. Casar o código `3.11`
    // devolveria 0,0 — "Reversão dos Juros sobre Capital Próprio" — em vez
    // dos R$ 37,3 bi de lucro. Decisão 67.
    const c = CvmChart.of(bankDaIntermediationIndividual());
    expect(c.netIncome).toBe(37.3);
    expect(c.netIncome).not.toBe(0.0);
  });

  it('operações continuadas não vencem o resultado final', () => {
    // No layout "de Intermediação" as duas linhas casam com "lucro"; a que
    // vale é a de baixo.
    expect(CvmChart.of(bankDeIntermediationConsolidated()).netIncome).toBe(22);
  });

  it('lucro por ação nunca é confundido com lucro', () => {
    for (const rows of [
      corporateIncomeStatement(),
      bankDaIntermediationConsolidated(),
      bankDaIntermediationIndividual(),
      bankDeIntermediationConsolidated(),
    ]) {
      const c = CvmChart.of(rows);
      expect(c.netIncome).not.toBeNull();
      expect(c.netIncome!, 'o LPA é de uma ordem de grandeza menor').toBeGreaterThan(10);
    }
  });
});

describe('EBIT — a recusa é o comportamento certo', () => {
  it('existe na não financeira', () => {
    expect(CvmChart.of(corporateIncomeStatement()).ebit).toBe(250);
  });

  it('é nulo em banco, e não o resultado antes dos tributos', () => {
    // Ler o 3.05 do Itaú como EBIT daria R$ 47,6 bi contra R$ 42,1 bi de
    // lucro — 13% de erro num número que a via da firma usaria. Banco não
    // tem EBIT: a estrutura não separa operação de financeiro.
    expect(CvmChart.of(bankDaIntermediationConsolidated()).ebit).toBeNull();
    expect(CvmChart.of(bankDaIntermediationIndividual()).ebit).toBeNull();
  });

  it('é nulo em seguradora', () => {
    expect(
      CvmChart.of([
        line('3.01', 'Receitas das Atividades Seguradoras/Resseguradoras', 10),
        line('3.05', 'Resultado Antes dos Tributos', 3),
      ]).ebit,
    ).toBeNull();
  });

  it('recusa mesmo em layout corporativo se o 3.05 desmentir o rótulo', () => {
    const c = CvmChart.of([
      line('3.01', 'Receita de Venda de Bens', 100),
      line('3.05', 'Resultado Antes dos Tributos sobre o Lucro', 30),
    ]);
    expect(c.layout).toBe(CvmLayout.corporate);
    expect(c.ebit, 'o código está certo e a descrição diz outra coisa').toBeNull();
  });
});

describe('Ordenação de código', () => {
  it('3.11 vem depois de 3.9, e não antes', () => {
    // Comparação lexicográfica diria o contrário, e o plano da CVM chega a
    // dois dígitos por nível.
    const c = CvmChart.of([
      line('3.01', 'Receita de Venda', 100),
      line('3.9', 'Lucro parcial', 5),
      line('3.11', 'Lucro do Período', 9),
    ]);
    expect(c.netIncome).toBe(9);
  });
});

describe('Balanço e fluxo', () => {
  it('lê os códigos universais', () => {
    const c = CvmChart.of([
      line('1', 'Ativo Total', 900),
      line('1.01', 'Ativo Circulante', 300),
      line('1.02', 'Ativo Não Circulante', 600),
      line('2', 'Passivo Total', 900),
      line('2.01', 'Passivo Circulante', 200),
      line('2.02', 'Passivo Não Circulante', 300),
      line('2.03', 'Patrimônio Líquido Consolidado', 400),
      line('2.03.09', 'Participação dos Acionistas Não Controladores', 40),
      line('6.01', 'Caixa Líquido Atividades Operacionais', 120),
      line('6.02', 'Caixa Líquido Atividades de Investimento', -80),
    ]);
    expect(c.totalAssets).toBe(900);
    expect(c.totalLiabilities).toBe(900);
    expect(c.equity).toBe(400);
    expect(c.nonControllingInterests).toBe(40);
    expect(c.operatingCashFlow).toBe(120);
    expect(c.investingCashFlow).toBe(-80);
  });

  it('o PL do controlador não é confundido com o consolidado', () => {
    const c = CvmChart.of([
      line('2.07', 'Patrimônio Líquido Consolidado', 500),
      line('2.07.01', 'Patrimônio Líquido Atribuído ao Controlador', 460),
      line('2.07.02', 'Patrimônio Líquido Atribuído aos Não Controladores', 40),
    ]);
    expect(c.equity).toBe(500);
    expect(c.nonControllingInterests).toBe(40);
  });

  it('CapEx soma as grafias e recusa a ausência', () => {
    const c = CvmChart.of([
      line('6.02', 'Caixa Líquido Atividades de Investimento', -100),
      line('6.02.01', 'Aquisição de imobilizado', -60),
      line('6.02.02', 'Aquisição de Intangível', -25),
      line('6.02.03', 'Aplicações financeiras', -15),
    ]);
    expectClose(c.capex, -85, 1e-12, 'aplicação financeira não é CapEx');

    const missingLine = CvmChart.of([line('6.02', 'Caixa Líquido Atividades de Investimento', -100)]);
    expect(missingLine.capex, 'ausência de linha não é investimento zero').toBeNull();
  });
});

describe('Centavos vindos do texto', () => {
  const fromText = (value: string, scale?: number, code = 'x', label = 'y'): CvmAccountLine | null =>
    CvmAccountLine.fromText(scale === undefined ? { code, label, value } : { code, label, value, scale });

  it('a escala entra ANTES do arredondamento', () => {
    // R$ 1.000,50 em escala MIL sao 100.050 centavos. Arredondar para
    // centavos primeiro daria R$ 1,00, e a escala multiplicaria o residuo
    // descartado: R$ 1.000,00, cinquenta centavos a menos.
    expect(fromText('1.0005', 1000)!.cents).toBe(100050);
    expect(fromText('0.0001', 1000)!.cents).toBe(10);
  });

  it('o texto do CSV vira inteiro exato, com a escala', () => {
    // Como a CVM publica: dez casas decimais, todas zero, e escala MIL.
    const l = fromText('265438605.0000000000', 1000, '3.01', 'Receita')!;
    expect(l.cents).toBe(265438605 * 1000 * 100);
    expect(l.value).toBe(265438605.0 * 1000);
  });

  it('sinal, ausência de decimais e escala 1', () => {
    expect(fromText('-1234', undefined, '3.06', 'Financeiro')!.cents).toBe(-123400);
    expect(fromText('0.5')!.cents).toBe(50);
  });

  it('arredonda meio para cima além dos centavos', () => {
    expect(fromText('1.005')!.cents).toBe(101);
    expect(fromText('1.004')!.cents).toBe(100);
  });

  it('texto ilegível devolve nulo, e não zero', () => {
    for (const bad of ['', '  ', 'abc', '1.2.3', '1,5']) {
      expect(fromText(bad), bad).toBeNull();
    }
  });

  it('valor que não cabe em int é recusado, não estoura', () => {
    expect(fromText('99999999999999999999', 1000)).toBeNull();
  });

  it('a soma do CapEx é exata em centavos', () => {
    // Tres linhas cujos reais nao somam exato em ponto flutuante.
    const c = CvmChart.of([
      fromText('-0.10', undefined, '6.02.01', 'Aquisição de imobilizado')!,
      fromText('-0.20', undefined, '6.02.02', 'Aquisição de intangível')!,
      fromText('-0.30', undefined, '6.02.03', 'Adições ao imobilizado')!,
    ]);
    expect(c.capex).toBe(-0.6);
  });
});

describe('Normalização', () => {
  it('acento e caixa não impedem o casamento', () => {
    expect(CvmChart.normalize('Participação dos Acionistas Não Controladores')).toBe(
      'participacao dos acionistas nao controladores',
    );
    const c = CvmChart.of([line('3.01', 'RECEITA DE VENDA', 1), line('3.11', 'LUCRO DO PERIODO', 7)]);
    expect(c.layout).toBe(CvmLayout.corporate);
    expect(c.netIncome).toBe(7);
  });
});
