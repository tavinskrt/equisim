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
      // Apenas PETR4 tem valuation, com 20% de upside; o peso da outra metade
      // é reescalado, não zerado.
      expect(expected, closeTo(0.20, 1e-9));
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
