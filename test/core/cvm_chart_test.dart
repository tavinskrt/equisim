import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Linhas de nível ≤ 2 da DRE consolidada de uma companhia **não financeira**,
/// no plano padrão da CVM.
List<CvmAccountLine> _corporateIncomeStatement() => [
      CvmAccountLine.approximate(
          code: '3.01', label: 'Receita de Venda de Bens e/ou Serviços',
          value: 1000),
      CvmAccountLine.approximate(
          code: '3.02', label: 'Custo dos Bens e/ou Serviços Vendidos',
          value: -600),
      CvmAccountLine.approximate(code: '3.03', label: 'Resultado Bruto', value: 400),
      CvmAccountLine.approximate(
          code: '3.04', label: 'Despesas/Receitas Operacionais', value: -150),
      CvmAccountLine.approximate(
          code: '3.05',
          label: 'Resultado Antes do Resultado Financeiro e dos Tributos',
          value: 250),
      CvmAccountLine.approximate(code: '3.06', label: 'Resultado Financeiro', value: -50),
      CvmAccountLine.approximate(
          code: '3.07',
          label: 'Resultado Antes dos Tributos sobre o Lucro',
          value: 200),
      CvmAccountLine.approximate(
          code: '3.08',
          label: 'Imposto de Renda e Contribuição Social sobre o Lucro',
          value: -60),
      CvmAccountLine.approximate(
          code: '3.09',
          label: 'Resultado Líquido das Operações Continuadas',
          value: 140),
      CvmAccountLine.approximate(
          code: '3.10',
          label: 'Resultado Líquido de Operações Descontinuadas',
          value: 0),
      CvmAccountLine.approximate(
          code: '3.11',
          label: 'Lucro/Prejuízo Consolidado do Período',
          value: 140),
      CvmAccountLine.approximate(
          code: '3.99', label: 'Lucro por Ação - (Reais / Ação)', value: 1.4),
    ];

/// DRE **consolidada** do layout de banco "**da** Intermediação Financeira" —
/// o do Itaú. Valores em bilhões, de 2024.
List<CvmAccountLine> _bankDaIntermediationConsolidated() => [
      CvmAccountLine.approximate(
          code: '3.01', label: 'Receitas da Intermediação Financeira',
          value: 335.3),
      CvmAccountLine.approximate(
          code: '3.02', label: 'Despesas da Intermediação Financeira',
          value: -199.6),
      CvmAccountLine.approximate(
          code: '3.03',
          label: 'Resultado Bruto Intermediação Financeira',
          value: 135.7),
      CvmAccountLine.approximate(
          code: '3.04',
          label: 'Outras Despesas/Receitas Operacionais',
          value: -88.2),
      CvmAccountLine.approximate(
          code: '3.05',
          label: 'Resultado Antes dos Tributos sobre o Lucro',
          value: 47.6),
      CvmAccountLine.approximate(
          code: '3.06',
          label: 'Imposto de Renda e Contribuição Social sobre o Lucro',
          value: -5.4),
      CvmAccountLine.approximate(
          code: '3.07',
          label: 'Resultado Líquido das Operações Continuadas',
          value: 42.1),
      CvmAccountLine.approximate(
          code: '3.08',
          label: 'Resultado Líquido das Operações Descontinuadas',
          value: 0),
      CvmAccountLine.approximate(
          code: '3.09',
          label: 'Lucro/Prejuízo Consolidado do Período',
          value: 42.1),
      CvmAccountLine.approximate(
          code: '3.99', label: 'Lucro por Ação - (R\$ / Ação)', value: 3.9),
    ];

/// DRE **individual** do mesmo layout. Aqui `3.11` é uma armadilha.
List<CvmAccountLine> _bankDaIntermediationIndividual() => [
      CvmAccountLine.approximate(
          code: '3.01', label: 'Receitas da Intermediação Financeira',
          value: 20.6),
      CvmAccountLine.approximate(
          code: '3.05', label: 'Resultado Operacional', value: 33.6),
      CvmAccountLine.approximate(
          code: '3.07',
          label: 'Resultado Antes Tributação/Participações',
          value: 33.6),
      CvmAccountLine.approximate(
          code: '3.08',
          label: 'Provisão para IR e Contribuição Social',
          value: 3.7),
      CvmAccountLine.approximate(code: '3.09', label: 'IR Diferido', value: 0.0),
      CvmAccountLine.approximate(
          code: '3.10',
          label: 'Participações/Contribuições Estatutárias',
          value: -0.02),
      CvmAccountLine.approximate(
          code: '3.11',
          label: 'Reversão dos Juros sobre Capital Próprio',
          value: 0.0),
      CvmAccountLine.approximate(
          code: '3.13', label: 'Lucro/Prejuízo do Período', value: 37.3),
      CvmAccountLine.approximate(
          code: '3.99', label: 'Lucro por Ação - (R\$ / Ação)', value: 3.5),
    ];

/// Layout de banco "**de** Intermediação", em que o lucro volta ao 3.11 e
/// convive com uma linha de operações continuadas que também casa com "lucro".
List<CvmAccountLine> _bankDeIntermediationConsolidated() => [
      CvmAccountLine.approximate(
          code: '3.01', label: 'Receitas de Intermediação Financeira',
          value: 100),
      CvmAccountLine.approximate(
          code: '3.07',
          label: 'Lucro ou Prejuízo das Operações Continuadas',
          value: 25),
      CvmAccountLine.approximate(
          code: '3.11',
          label: 'Lucro ou Prejuízo Líquido Consolidado do Período',
          value: 22),
      CvmAccountLine.approximate(
          code: '3.99', label: 'Lucro por Ação - (R\$ / Ação)', value: 2.2),
    ];

void main() {
  group('Detecção de layout', () {
    test('reconhece os quatro planos pela conta 3.01', () {
      expect(CvmChart.of(_corporateIncomeStatement()).layout, CvmLayout.corporate);
      expect(CvmChart.of(_bankDaIntermediationConsolidated()).layout,
          CvmLayout.financialIntermediation);
      expect(CvmChart.of(_bankDeIntermediationConsolidated()).layout,
          CvmLayout.financialIntermediation);
      expect(
        CvmChart.of([
          CvmAccountLine.approximate(
              code: '3.01',
              label: 'Receitas das Atividades Seguradoras/Resseguradoras',
              value: 10),
        ]).layout,
        CvmLayout.insurer,
      );
    });

    test('a preposição não decide: "da" e "de" caem no mesmo layout', () {
      // Os dois rótulos diferem por uma letra, e a conferência mostrou que
      // eles têm o lucro em códigos diferentes. Quem resolve isso é a busca
      // por descrição, não a detecção — o layout dos dois é o mesmo.
      expect(CvmChart.of(_bankDaIntermediationConsolidated()).layout,
          CvmChart.of(_bankDeIntermediationConsolidated()).layout);
    });

    test('balanço sem DRE ainda é legível', () {
      final c = CvmChart.of([
        CvmAccountLine.approximate(code: '1', label: 'Ativo Total', value: 900),
        CvmAccountLine.approximate(code: '1.01', label: 'Ativo Circulante', value: 300),
      ]);
      expect(c.totalAssets, 900);
      expect(c.currentAssets, 300);
    });

    test('documento sem nada reconhecível não inventa layout', () {
      final c = CvmChart.of([
        CvmAccountLine.approximate(code: '9.99', label: 'Outra coisa', value: 1),
      ]);
      expect(c.layout, CvmLayout.unknown);
      expect(c.netIncome, isNull);
      expect(c.ebit, isNull);
    });
  });

  group('Lucro líquido — onde o código engana', () {
    test('não financeira: 3.11', () {
      expect(CvmChart.of(_corporateIncomeStatement()).netIncome, 140);
    });

    test('banco consolidado: 3.09, e NÃO o 3.05 de antes dos tributos', () {
      final c = CvmChart.of(_bankDaIntermediationConsolidated());
      expect(c.netIncome, 42.1);
      expect(c.netIncome, isNot(47.6));
    });

    test('banco individual: 3.13, e NÃO a reversão de JCP do 3.11', () {
      // Esta é a armadilha que a conferência pegou. Casar o código `3.11`
      // devolveria 0,0 — "Reversão dos Juros sobre Capital Próprio" — em vez
      // dos R$ 37,3 bi de lucro. Decisão 67.
      final c = CvmChart.of(_bankDaIntermediationIndividual());
      expect(c.netIncome, 37.3);
      expect(c.netIncome, isNot(0.0));
    });

    test('operações continuadas não vencem o resultado final', () {
      // No layout "de Intermediação" as duas linhas casam com "lucro"; a que
      // vale é a de baixo.
      expect(CvmChart.of(_bankDeIntermediationConsolidated()).netIncome, 22);
    });

    test('lucro por ação nunca é confundido com lucro', () {
      for (final rows in [
        _corporateIncomeStatement(),
        _bankDaIntermediationConsolidated(),
        _bankDaIntermediationIndividual(),
        _bankDeIntermediationConsolidated(),
      ]) {
        final c = CvmChart.of(rows);
        expect(c.netIncome, isNotNull);
        expect(c.netIncome, greaterThan(10),
            reason: 'o LPA é de uma ordem de grandeza menor');
      }
    });
  });

  group('EBIT — a recusa é o comportamento certo', () {
    test('existe na não financeira', () {
      expect(CvmChart.of(_corporateIncomeStatement()).ebit, 250);
    });

    test('é nulo em banco, e não o resultado antes dos tributos', () {
      // Ler o 3.05 do Itaú como EBIT daria R$ 47,6 bi contra R$ 42,1 bi de
      // lucro — 13% de erro num número que a via da firma usaria. Banco não
      // tem EBIT: a estrutura não separa operação de financeiro.
      expect(CvmChart.of(_bankDaIntermediationConsolidated()).ebit, isNull);
      expect(CvmChart.of(_bankDaIntermediationIndividual()).ebit, isNull);
    });

    test('é nulo em seguradora', () {
      expect(
        CvmChart.of([
          CvmAccountLine.approximate(
              code: '3.01',
              label: 'Receitas das Atividades Seguradoras/Resseguradoras',
              value: 10),
          CvmAccountLine.approximate(
              code: '3.05', label: 'Resultado Antes dos Tributos', value: 3),
        ]).ebit,
        isNull,
      );
    });

    test('recusa mesmo em layout corporativo se o 3.05 desmentir o rótulo', () {
      final c = CvmChart.of([
        CvmAccountLine.approximate(
            code: '3.01', label: 'Receita de Venda de Bens', value: 100),
        CvmAccountLine.approximate(
            code: '3.05',
            label: 'Resultado Antes dos Tributos sobre o Lucro',
            value: 30),
      ]);
      expect(c.layout, CvmLayout.corporate);
      expect(c.ebit, isNull,
          reason: 'o código está certo e a descrição diz outra coisa');
    });
  });

  group('Ordenação de código', () {
    test('3.11 vem depois de 3.9, e não antes', () {
      // Comparação lexicográfica diria o contrário, e o plano da CVM chega a
      // dois dígitos por nível.
      final c = CvmChart.of([
        CvmAccountLine.approximate(code: '3.01', label: 'Receita de Venda', value: 100),
        CvmAccountLine.approximate(code: '3.9', label: 'Lucro parcial', value: 5),
        CvmAccountLine.approximate(code: '3.11', label: 'Lucro do Período', value: 9),
      ]);
      expect(c.netIncome, 9);
    });
  });

  group('Balanço e fluxo', () {
    test('lê os códigos universais', () {
      final c = CvmChart.of([
        CvmAccountLine.approximate(code: '1', label: 'Ativo Total', value: 900),
        CvmAccountLine.approximate(code: '1.01', label: 'Ativo Circulante', value: 300),
        CvmAccountLine.approximate(code: '1.02', label: 'Ativo Não Circulante', value: 600),
        CvmAccountLine.approximate(code: '2', label: 'Passivo Total', value: 900),
        CvmAccountLine.approximate(code: '2.01', label: 'Passivo Circulante', value: 200),
        CvmAccountLine.approximate(
            code: '2.02', label: 'Passivo Não Circulante', value: 300),
        CvmAccountLine.approximate(
            code: '2.03', label: 'Patrimônio Líquido Consolidado', value: 400),
        CvmAccountLine.approximate(
            code: '2.03.09',
            label: 'Participação dos Acionistas Não Controladores',
            value: 40),
        CvmAccountLine.approximate(
            code: '6.01',
            label: 'Caixa Líquido Atividades Operacionais',
            value: 120),
        CvmAccountLine.approximate(
            code: '6.02',
            label: 'Caixa Líquido Atividades de Investimento',
            value: -80),
      ]);
      expect(c.totalAssets, 900);
      expect(c.totalLiabilities, 900);
      expect(c.equity, 400);
      expect(c.nonControllingInterests, 40);
      expect(c.operatingCashFlow, 120);
      expect(c.investingCashFlow, -80);
    });

    test('o PL do controlador não é confundido com o consolidado', () {
      final c = CvmChart.of([
        CvmAccountLine.approximate(
            code: '2.07', label: 'Patrimônio Líquido Consolidado', value: 500),
        CvmAccountLine.approximate(
            code: '2.07.01',
            label: 'Patrimônio Líquido Atribuído ao Controlador',
            value: 460),
        CvmAccountLine.approximate(
            code: '2.07.02',
            label: 'Patrimônio Líquido Atribuído aos Não Controladores',
            value: 40),
      ]);
      expect(c.equity, 500);
      expect(c.nonControllingInterests, 40);
    });

    test('CapEx soma as grafias e recusa a ausência', () {
      final c = CvmChart.of([
        CvmAccountLine.approximate(
            code: '6.02',
            label: 'Caixa Líquido Atividades de Investimento',
            value: -100),
        CvmAccountLine.approximate(
            code: '6.02.01', label: 'Aquisição de imobilizado', value: -60),
        CvmAccountLine.approximate(
            code: '6.02.02', label: 'Aquisição de Intangível', value: -25),
        CvmAccountLine.approximate(
            code: '6.02.03',
            label: 'Aplicações financeiras',
            value: -15),
      ]);
      expect(c.capex, closeTo(-85, 1e-12),
          reason: 'aplicação financeira não é CapEx');

      final missingLine = CvmChart.of([
        CvmAccountLine.approximate(
            code: '6.02',
            label: 'Caixa Líquido Atividades de Investimento',
            value: -100),
      ]);
      expect(missingLine.capex, isNull,
          reason: 'ausência de linha não é investimento zero');
    });
  });

  group('Centavos vindos do texto', () {
    test('a escala entra ANTES do arredondamento', () {
      // R$ 1.000,50 em escala MIL sao 100.050 centavos. Arredondar para
      // centavos primeiro daria R$ 1,00, e a escala multiplicaria o residuo
      // descartado: R$ 1.000,00, cinquenta centavos a menos.
      expect(
        CvmAccountLine.fromText(
            code: 'x', label: 'y', value: '1.0005', scale: 1000)!.cents,
        100050,
      );
      expect(
        CvmAccountLine.fromText(
            code: 'x', label: 'y', value: '0.0001', scale: 1000)!.cents,
        10,
      );
    });

    test('o texto do CSV vira inteiro exato, com a escala', () {
      // Como a CVM publica: dez casas decimais, todas zero, e escala MIL.
      final l = CvmAccountLine.fromText(
        code: '3.01',
        label: 'Receita',
        value: '265438605.0000000000',
        scale: 1000,
      )!;
      expect(l.cents, 265438605 * 1000 * 100);
      expect(l.value, 265438605.0 * 1000);
    });

    test('sinal, ausência de decimais e escala 1', () {
      expect(
        CvmAccountLine.fromText(
            code: '3.06', label: 'Financeiro', value: '-1234')!.cents,
        -123400,
      );
      expect(
        CvmAccountLine.fromText(code: 'x', label: 'y', value: '0.5')!.cents,
        50,
      );
    });

    test('arredonda meio para cima além dos centavos', () {
      expect(CvmAccountLine.fromText(code: 'x', label: 'y', value: '1.005')!
          .cents, 101);
      expect(CvmAccountLine.fromText(code: 'x', label: 'y', value: '1.004')!
          .cents, 100);
    });

    test('texto ilegível devolve nulo, e não zero', () {
      for (final bad in ['', '  ', 'abc', '1.2.3', '1,5']) {
        expect(CvmAccountLine.fromText(code: 'x', label: 'y', value: bad),
            isNull, reason: bad);
      }
    });

    test('valor que não cabe em int é recusado, não estoura', () {
      expect(
        CvmAccountLine.fromText(
            code: 'x', label: 'y', value: '99999999999999999999', scale: 1000),
        isNull,
      );
    });

    test('a soma do CapEx é exata em centavos', () {
      // Tres linhas cujos reais nao somam exato em ponto flutuante.
      final c = CvmChart.of([
        CvmAccountLine.fromText(
            code: '6.02.01', label: 'Aquisição de imobilizado', value: '-0.10')!,
        CvmAccountLine.fromText(
            code: '6.02.02', label: 'Aquisição de intangível', value: '-0.20')!,
        CvmAccountLine.fromText(
            code: '6.02.03', label: 'Adições ao imobilizado', value: '-0.30')!,
      ]);
      expect(c.capex, -0.60);
    });
  });

  group('Normalização', () {
    test('acento e caixa não impedem o casamento', () {
      expect(CvmChart.normalize('Participação dos Acionistas Não '
          'Controladores'), 'participacao dos acionistas nao controladores');
      final c = CvmChart.of([
        CvmAccountLine.approximate(code: '3.01', label: 'RECEITA DE VENDA', value: 1),
        CvmAccountLine.approximate(code: '3.11', label: 'LUCRO DO PERIODO', value: 7),
      ]);
      expect(c.layout, CvmLayout.corporate);
      expect(c.netIncome, 7);
    });
  });
}
