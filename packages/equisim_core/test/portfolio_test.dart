import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

Asset assetOf(String symbol, String sectorKey) => Asset(
      ticker: Ticker.parse(symbol),
      name: symbol,
      sector: sectorKey.isEmpty
          ? Sector.unknown
          : Sector.fromKey(sectorKey, label: sectorKey),
    );

void main() {
  group('Portfolio', () {
    test('equiponderada distribui 100% sem sobra', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [
          assetOf('PETR4', 'energia'),
          assetOf('VALE3', 'materiais'),
          assetOf('ITUB4', 'financeiro'),
        ],
      ).unwrap();

      expect(portfolio.hasValidWeights, isTrue);
      expect(Weights.sum(portfolio.weights), closeTo(1.0, 1e-15));
    });

    test('respeita o teto de 15 ativos', () {
      final assets =
          List.generate(16, (i) => assetOf('AAAA$i', 'financeiro'));
      final result = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: assets,
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InvalidInput>());
      expect(result.failureOrNull!.message, contains('15'));
    });

    test('aceita exatamente 15 ativos', () {
      final assets =
          List.generate(15, (i) => assetOf('AAAA$i', 'financeiro'));
      expect(
        Portfolio.equalWeighted(
          id: 'p',
          name: 'Principal',
          kind: PortfolioKind.principal,
          assets: assets,
        ).isOk,
        isTrue,
      );
    });

    test('rejeita ativos duplicados', () {
      final result = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4', 'energia'), assetOf('PETR4', 'energia')],
      );
      expect(result.isErr, isTrue);
    });

    test('pesos customizados exigem soma de 100%', () {
      final invalid = Portfolio.weighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        allocation: {
          assetOf('PETR4', 'energia'): 0.5,
          assetOf('VALE3', 'materiais'): 0.4,
        },
      );
      expect(invalid.isErr, isTrue);
      expect(invalid.failureOrNull!.message, contains('90.00%'));

      final valid = Portfolio.weighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        allocation: {
          assetOf('PETR4', 'energia'): 0.6,
          assetOf('VALE3', 'materiais'): 0.4,
        },
      );
      expect(valid.isOk, isTrue);
    });

    test('adicionar e remover reequipondera mantendo 100%', () {
      var portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4', 'energia'), assetOf('VALE3', 'materiais')],
      ).unwrap();

      portfolio = portfolio.add(assetOf('ITUB4', 'financeiro')).unwrap();
      expect(portfolio.length, 3);
      expect(Weights.sumsToOne(portfolio.weights), isTrue);

      portfolio = portfolio.remove(Ticker.parse('PETR4')).unwrap();
      expect(portfolio.length, 2);
      expect(Weights.sumsToOne(portfolio.weights), isTrue);
    });

    test('não adiciona ativo já presente', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4', 'energia')],
      ).unwrap();
      expect(portfolio.add(assetOf('PETR4', 'energia')).isErr, isTrue);
    });
  });

  group('A falha carrega o número, e não só o texto', () {
    test('soma dos pesos fora de 100% viaja como valor medido', () {
      // Pela mesma razão de `DataQualityFailure.deviation`: a interface que
      // quiser arredondar de outro jeito, exibir num campo próprio ou comparar
      // com o limite não precisa reextrair o número do texto. Decisão 59.
      final r = Portfolio.weighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        allocation: {
          assetOf('PETR4', 'energia'): 0.60,
          assetOf('VALE3', 'materiais'): 0.30,
        },
      );
      expect(r.isErr, isTrue);
      final f = r.failureOrNull;
      expect(f, isA<InvalidInput>());
      expect((f as InvalidInput).field, 'weights');
      expect(f.actual, closeTo(0.90, 1e-12));
      // E o texto continua completo, para quem só o exibe.
      expect(f.message, contains('90.00%'));
    });
  });

  group('Concentração setorial', () {
    test('alerta a partir de dois ativos no mesmo setor', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [
          assetOf('ITUB4', 'financeiro'),
          assetOf('BBAS3', 'financeiro'),
          assetOf('PETR4', 'energia'),
        ],
      ).unwrap();

      final report = SectorConcentration.analyze(portfolio);
      expect(report.hasAlert, isTrue);
      expect(report.concentrated.length, 1);
      expect(report.concentrated.first.sector.key, 'financeiro');
      expect(report.concentrated.first.count, 2);
      expect(report.concentrated.first.weight, closeTo(2 / 3, 1e-9));
    });

    test('sem concentração não há alerta', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [
          assetOf('ITUB4', 'financeiro'),
          assetOf('PETR4', 'energia'),
          assetOf('VALE3', 'materiais'),
        ],
      ).unwrap();
      expect(SectorConcentration.analyze(portfolio).hasAlert, isFalse);
    });

    test('contabiliza peso sem classificação setorial', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('ITUB4', 'financeiro'), assetOf('XXXX3', '')],
      ).unwrap();
      final report = SectorConcentration.analyze(portfolio);
      expect(report.unclassifiedWeight, closeTo(0.5, 1e-9));
    });
  });

  group('Retorno esperado — unidade comparável com a meta', () {
    test('anualiza upside pelo horizonte de convergência', () {
      // +21% de upside em 24 meses ⇒ 10% ao ano.
      final annual =
          ExpectedReturn.annualizedFromUpside(0.21, horizonMonths: 24);
      expect(annual, closeTo(0.10, 1e-9));
    });

    test('horizonte de 12 meses preserva o upside', () {
      final annual =
          ExpectedReturn.annualizedFromUpside(0.40, horizonMonths: 12);
      expect(annual, closeTo(0.40, 1e-12));
    });

    test('retorno esperado é a convergência de preço, e nada além dela', () {
      // Sem provento no modelo, o anual não pode divergir da convergência: um
      // segundo termo aqui seria retorno que nenhuma outra tela apura.
      final expected = ExpectedReturn.forAsset(
        ticker: Ticker.parse('ITUB4'),
        upside: 0.20,
        horizonMonths: 12,
      );
      expect(expected.priceConvergence, closeTo(0.20, 1e-12));
      expect(expected.annual, closeTo(0.20, 1e-12));
    });

    test('carteira pondera pelos pesos e reporta cobertura parcial', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4', 'energia'), assetOf('VALE3', 'materiais')],
      ).unwrap();

      final valuations = {
        Ticker.parse('PETR4'): ValuationResult(
          ticker: Ticker.parse('PETR4'),
          asOf: DateTime(2026, 8, 19),
          model: ValuationModel.dcfFcff,
          fairValue: Money.fromReais(60),
          marketPrice: Money.fromReais(50),
          discountRate: 0.12,
        ),
      };

      final coverage = ExpectedReturn.coverage(
        portfolio: portfolio,
        valuations: valuations,
      );
      expect(coverage, closeTo(0.5, 1e-9));

      final expected = ExpectedReturn.forPortfolio(
        portfolio: portfolio,
        valuations: valuations,
      );
      // Apenas PETR4 tem valuation, com 20% de potencial; o peso da outra
      // metade é reescalado, não zerado. Convergindo em 36 meses,
      // (1,20)^(1/3) − 1 = 6,27% ao ano — e não os 20% que o horizonte de doze
      // meses devolvia por identidade.
      expect(expected, closeTo(0.0627, 1e-4));
    });
  });

  group('Retorno esperado transversal — projeção para otimização', () {
    Map<Ticker, double> upsidesOf(Map<String, double> m) =>
        {for (final e in m.entries) Ticker.parse(e.key): e.value};

    const cdi = 0.1415;
    const premio = 0.055;

    test('o ativo mediano da seção recebe a âncora, e nada além dela', () {
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.0}),
        spotRiskFree: cdi,
        reference: const [-0.6, -0.3, 0.0, 0.3, 0.6],
      );
      expect(r[Ticker.parse('AAAA3')]!.z, closeTo(0.0, 1e-12));
      expect(r[Ticker.parse('AAAA3')]!.expected, closeTo(cdi, 1e-12));
      expect(r[Ticker.parse('AAAA3')]!.anchoredOnCostOfEquity, isFalse);
    });

    test('seção colapsada num ponto não produz NaN', () {
      // `z = (u − mediana) / escala` divide por zero se a escala for zero, e
      // `0/0` é NaN — que atravessa `clamp` e chega à tela. Não acontece
      // porque `Inference.scaledMad` devolve **nulo**, e não zero, quando a
      // dispersão some. O teste existe para que isso continue verdade.
      const ke = 0.1956;
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.20}),
        spotRiskFree: cdi,
        costOfEquity: {Ticker.parse('AAAA3'): ke},
        reference: const [0.20, 0.20, 0.20, 0.20, 0.20],
      );
      final x = r[Ticker.parse('AAAA3')]!;
      expect(x.z, 0.0);
      expect(x.z.isNaN, isFalse);
      expect(x.expected.isFinite, isTrue);
      expect(x.expected, closeTo(ke, 1e-12));
    });

    test('seção de um ponto só também não produz NaN', () {
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.20}),
        spotRiskFree: cdi,
      );
      expect(r[Ticker.parse('AAAA3')]!.expected.isFinite, isTrue);
    });

    test('A ÂNCORA É O CUSTO DO CAPITAL PRÓPRIO, e não o CDI', () {
      // Ancorar no CDI dava ao ativo mediano da seção um retorno esperado
      // **sem prêmio de risco algum**: uma carteira de ações centrada na seção
      // esperava exatamente a renda fixa. Medido em 11/09/2026 sobre os 127
      // avaliados: o mediano ia de 14,09% — o próprio CDI — para 20,45%, e a
      // carteira igualmente ponderada subia 5,97 p.p. Decisão 58.
      const ke = 0.1956;
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.0}),
        spotRiskFree: cdi,
        costOfEquity: {Ticker.parse('AAAA3'): ke},
        reference: const [-0.6, -0.3, 0.0, 0.3, 0.6],
      );
      final x = r[Ticker.parse('AAAA3')]!;
      expect(x.z, closeTo(0.0, 1e-12));
      expect(x.expected, closeTo(ke, 1e-12));
      expect(x.anchoredOnCostOfEquity, isTrue);
      expect(x.expected - cdi, closeTo(ke - cdi, 1e-12),
          reason: 'a diferença entre as duas âncoras é o prêmio de risco '
              'inteiro');
    });

    test('Ke igual ao CDI ainda é âncora de Ke, e não recuo', () {
      // A bandeira sai de **haver** `Ke`, e não de comparar as duas âncoras:
      // beta zero produz `Ke == CDI`, e compará-los declararia recuo onde não
      // houve. Comparação de `double` por igualdade, ainda por cima.
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.0}),
        spotRiskFree: cdi,
        costOfEquity: {Ticker.parse('AAAA3'): cdi},
        reference: const [-0.6, -0.3, 0.0, 0.3, 0.6],
      );
      expect(r[Ticker.parse('AAAA3')]!.anchoredOnCostOfEquity, isTrue);
    });

    test('cada ativo é ancorado no próprio Ke', () {
      // Dois ativos no mesmo ponto da seção e com betas diferentes não têm o
      // mesmo retorno esperado — é o que a âncora única apagava.
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.0, 'BBBB3': 0.0}),
        spotRiskFree: cdi,
        costOfEquity: {
          Ticker.parse('AAAA3'): 0.17,
          Ticker.parse('BBBB3'): 0.25,
        },
        reference: const [-0.6, -0.3, 0.0, 0.3, 0.6],
      );
      expect(r[Ticker.parse('AAAA3')]!.expected, closeTo(0.17, 1e-12));
      expect(r[Ticker.parse('BBBB3')]!.expected, closeTo(0.25, 1e-12));
    });

    test('sem Ke utilizável, recua para o CDI e declara', () {
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.0, 'BBBB3': 0.0, 'CCCC3': 0.0}),
        spotRiskFree: cdi,
        costOfEquity: {
          Ticker.parse('AAAA3'): double.nan,
          Ticker.parse('BBBB3'): -0.05,
          // CCCC3 não aparece no mapa.
        },
        reference: const [-0.6, -0.3, 0.0, 0.3, 0.6],
      );
      for (final t in ['AAAA3', 'BBBB3', 'CCCC3']) {
        final x = r[Ticker.parse(t)]!;
        expect(x.expected, closeTo(cdi, 1e-12), reason: t);
        expect(x.anchoredOnCostOfEquity, isFalse, reason: t);
      }
    });

    test('preserva a ordenação do potencial', () {
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': -0.8, 'BBBB3': -0.4, 'CCCC3': 0.0, 'DDDD3': 0.5}),
        spotRiskFree: cdi,
      );
      final ordenado = [
        r[Ticker.parse('AAAA3')]!.expected,
        r[Ticker.parse('BBBB3')]!.expected,
        r[Ticker.parse('CCCC3')]!.expected,
        r[Ticker.parse('DDDD3')]!.expected,
      ];
      for (var i = 1; i < ordenado.length; i++) {
        expect(ordenado[i], greaterThan(ordenado[i - 1]));
      }
    });

    test('não propaga retorno negativo, que é o ponto do estimador', () {
      // Pela anualização, −95% de potencial em 36 meses dá −63,2% ao ano — e um
      // otimizador de média-variância alimentado com isso não aloca no ativo,
      // ele foge dele. A ordenação é o que a avaliação sustenta; o nível, não.
      expect(ExpectedReturn.annualizedFromUpside(-0.95), lessThan(-0.6));

      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'RUIM3': -0.95}),
        spotRiskFree: cdi,
        reference: const [-0.95, -0.8, -0.65, -0.4, -0.15, 0.4, 4.8],
      );
      final ruim = r[Ticker.parse('RUIM3')]!;
      expect(ruim.expected, greaterThan(0));
      expect(ruim.floored, isFalse);
      expect(ruim.expected, lessThan(cdi));
    });

    test('a cauda é confinada, e o teto é o do escore', () {
      // Distribuição dos 120 avaliados: a cauda direita vai a +477,3%. Sem
      // teto, um ativo sozinho definiria o retorno esperado da carteira.
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'CAUD3': 4.773}),
        spotRiskFree: cdi,
        reference: const [-0.95, -0.8, -0.65, -0.4, -0.15, 0.4, 4.773],
      );
      final cauda = r[Ticker.parse('CAUD3')]!;
      expect(cauda.z, closeTo(ExpectedReturn.defaultZCap, 1e-12));
      expect(cauda.expected,
          closeTo(cdi + ExpectedReturn.defaultZCap * premio, 1e-12));
    });

    test('seção sem escala estimável devolve a âncora a todos', () {
      // Dois ativos, ou uma seção colapsada num ponto: não há distância a
      // medir, e inventar prêmio onde a seção não o sustenta seria pior que
      // devolver o CDI.
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': -0.5, 'BBBB3': 0.9}),
        spotRiskFree: cdi,
      );
      for (final v in r.values) {
        expect(v.z, 0.0);
        expect(v.expected, closeTo(cdi, 1e-12));
        expect(v.referenceSize, 2);
      }
    });

    test('o tamanho da seção viaja junto do resultado', () {
      final r = ExpectedReturn.crossSection(
        upsides: upsidesOf({'AAAA3': 0.1}),
        spotRiskFree: cdi,
        reference: List<double>.filled(120, 0.0),
      );
      expect(r[Ticker.parse('AAAA3')]!.referenceSize, 120);
    });
  });

  group('ValuationResult', () {
    test('upside e margem de segurança', () {
      final valuation = ValuationResult(
        ticker: Ticker.parse('PETR4'),
        asOf: DateTime(2026, 8, 19),
        model: ValuationModel.dcfFcff,
        fairValue: Money.fromReais(100),
        marketPrice: Money.fromReais(80),
        discountRate: 0.12,
        marginOfSafety: 0.20,
      );
      expect(valuation.upside, closeTo(0.25, 1e-9));
      expect(valuation.safetyPrice.reais, closeTo(80.0, 1e-9));
      expect(valuation.isUndervalued, isTrue);
    });
  });
}
