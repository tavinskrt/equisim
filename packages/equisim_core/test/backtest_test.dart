import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Constrói uma série diária sintética a partir de uma lista de fechamentos,
/// um pregão por dia útil a partir de [start].
PriceSeries seriesOf(String symbol, DateTime start, List<double> closes) {
  final points = <PricePoint>[];
  var date = start;
  for (final close in closes) {
    while (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      date = date.add(const Duration(days: 1));
    }
    points.add(PricePoint(date: date, close: close));
    date = date.add(const Duration(days: 1));
  }
  return PriceSeries(ticker: Ticker.parse(symbol), points: points);
}

Asset assetOf(String symbol, {String sectorKey = 'financeiro'}) => Asset(
      ticker: Ticker.parse(symbol),
      name: symbol,
      sector: Sector.fromKey(sectorKey, label: sectorKey),
    );

void main() {
  final start = DateTime(2024, 1, 1);

  group('Motor de retorno total', () {
    test('sem proventos, o índice acompanha o preço', () {
      final prices = seriesOf('PETR4', start, [10, 11, 12]);
      final series = TotalReturnEngine.build(
        prices: prices,
        dividends: const [],
        taxPolicy: TaxPolicy.brasil,
      );
      expect(series.totalReturn, closeTo(0.2, 1e-12));
    });

    test('dividendo isento é reinvestido integralmente', () {
      final prices = seriesOf('PETR4', start, [10, 10, 10]);
      final dividend = DividendEvent(
        ticker: Ticker.parse('PETR4'),
        exDate: prices.points[1].date,
        paymentDate: prices.points[1].date,
        amountPerShare: 1.0,
        kind: DividendKind.dividendo,
      );
      final series = TotalReturnEngine.build(
        prices: prices,
        dividends: [dividend],
        taxPolicy: TaxPolicy.brasil,
      );
      // R$ 1,00 de provento sobre ação de R$ 10 → +10% em cotas.
      expect(series.totalReturn, closeTo(0.10, 1e-12));
      expect(series.withheldTaxPerShare, 0.0);
    });

    test('JCP sofre 15% de IRRF e rende menos que dividendo equivalente', () {
      final prices = seriesOf('ITUB4', start, [10, 10, 10]);
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: prices.points[1].date,
        paymentDate: prices.points[1].date,
        amountPerShare: 1.0,
        kind: DividendKind.jcp,
      );
      final series = TotalReturnEngine.build(
        prices: prices,
        dividends: [jcp],
        taxPolicy: TaxPolicy.brasil,
      );
      // Líquido de R$ 0,85 sobre R$ 10 → +8,5%.
      expect(series.totalReturn, closeTo(0.085, 1e-12));
      expect(series.withheldTaxPerShare, closeTo(0.15, 1e-12));
      expect(series.grossDividendsPerShare, closeTo(1.0, 1e-12));
    });

    test('política sem tributação isola exatamente o efeito fiscal', () {
      final prices = seriesOf('ITUB4', start, [10, 10, 10]);
      final jcp = DividendEvent(
        ticker: Ticker.parse('ITUB4'),
        exDate: prices.points[1].date,
        paymentDate: prices.points[1].date,
        amountPerShare: 1.0,
        kind: DividendKind.jcp,
      );
      final bruto = TotalReturnEngine.build(
        prices: prices,
        dividends: [jcp],
        taxPolicy: TaxPolicy.zero,
      );
      final liquido = TotalReturnEngine.build(
        prices: prices,
        dividends: [jcp],
        taxPolicy: TaxPolicy.brasil,
      );
      expect(bruto.totalReturn - liquido.totalReturn, closeTo(0.015, 1e-12));
    });

    test('provento com data-ex anterior ao início não é creditado', () {
      final prices = seriesOf('PETR4', start, [10, 10, 10]);
      final dividend = DividendEvent(
        ticker: Ticker.parse('PETR4'),
        exDate: start.subtract(const Duration(days: 30)),
        paymentDate: prices.points[1].date,
        amountPerShare: 1.0,
        kind: DividendKind.dividendo,
      );
      final series = TotalReturnEngine.build(
        prices: prices,
        dividends: [dividend],
        taxPolicy: TaxPolicy.brasil,
      );
      expect(series.totalReturn, closeTo(0.0, 1e-12));
    });
  });

  group('PortfolioBacktest', () {
    test('ativo único que dobra: patrimônio dobra e TWR é 100%', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {Ticker.parse('PETR4'): seriesOf('PETR4', start, [10, 15, 20])},
        dividends: const {},
        plan: const ContributionPlan(
          initial: Money(100000), // R$ 1.000
          monthly: Money.zero,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      );

      expect(result.isOk, isTrue);
      final outcome = result.unwrap();
      expect(outcome.finalValue.reais, closeTo(2000.0, 0.01));
      expect(outcome.metrics.timeWeightedReturn, closeTo(1.0, 1e-9));
      expect(outcome.base100.last, closeTo(200.0, 1e-6));
    });

    test('sem rebalanceamento, os pesos derivam com o mercado', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          Ticker.parse('PETR4'): seriesOf('PETR4', start, [10, 15, 20]),
          Ticker.parse('VALE3'): seriesOf('VALE3', start, [10, 10, 10]),
        },
        dividends: const {},
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money.zero,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      // R$ 500 em cada; PETR4 dobra para R$ 1.000, VALE3 fica em R$ 500.
      final petr = result.perAsset[Ticker.parse('PETR4')]!;
      final vale = result.perAsset[Ticker.parse('VALE3')]!;

      expect(petr.targetWeight.value, closeTo(0.5, 1e-9));
      expect(petr.currentWeight, closeTo(2 / 3, 1e-6));
      expect(vale.currentWeight, closeTo(1 / 3, 1e-6));
      expect(petr.drift, greaterThan(0));
      expect(vale.drift, lessThan(0));
      expect(result.finalValue.reais, closeTo(1500.0, 0.01));
    });

    test('desempenho individual por ativo é reportado', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          Ticker.parse('PETR4'): seriesOf('PETR4', start, [10, 15, 20]),
          Ticker.parse('VALE3'): seriesOf('VALE3', start, [10, 9, 8]),
        },
        dividends: const {},
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money.zero,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      expect(result.perAsset[Ticker.parse('PETR4')]!.totalReturn,
          closeTo(1.0, 1e-6));
      expect(result.perAsset[Ticker.parse('VALE3')]!.totalReturn,
          closeTo(-0.2, 1e-6));
    });

    test('aportes mensais entram no fluxo de caixa e no capital aportado', () {
      final closes = List<double>.filled(120, 10.0);
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {Ticker.parse('PETR4'): seriesOf('PETR4', start, closes)},
        dividends: const {},
        plan: const ContributionPlan(
          initial: Money(100000), // R$ 1.000
          monthly: Money(50000), // R$ 500
          contributionDay: 5,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      // Preço constante: patrimônio deve igualar exatamente o aportado.
      expect(
        result.finalValue.reais,
        closeTo(result.totalContributed.reais, 0.01),
      );
      // E o retorno tem de ser zero, apesar dos aportes.
      expect(result.metrics.timeWeightedReturn, closeTo(0.0, 1e-9));
      expect(result.cashFlows.length, greaterThan(2));
    });

    test('JCP reduz o patrimônio final em relação a dividendo equivalente', () {
      final prices = seriesOf('ITUB4', start, [10, 10, 10, 10]);
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('ITUB4')],
      ).unwrap();

      BacktestOutcome runWith(DividendKind kind) => PortfolioBacktest.run(
            portfolio: portfolio,
            prices: {Ticker.parse('ITUB4'): prices},
            dividends: {
              Ticker.parse('ITUB4'): [
                DividendEvent(
                  ticker: Ticker.parse('ITUB4'),
                  exDate: prices.points[1].date,
                  paymentDate: prices.points[2].date,
                  amountPerShare: 1.0,
                  kind: kind,
                ),
              ],
            },
            plan: const ContributionPlan(
              initial: Money(100000),
              monthly: Money.zero,
            ),
            range: DateRange(start, DateTime(2024, 12, 31)),
          ).unwrap();

      final comJcp = runWith(DividendKind.jcp);
      final comDividendo = runWith(DividendKind.dividendo);

      expect(comJcp.finalValue.reais, lessThan(comDividendo.finalValue.reais));
      expect(comJcp.withheldTax.reais, closeTo(15.0, 0.01));
      expect(comDividendo.withheldTax.reais, closeTo(0.0, 0.01));
      // 100 ações × R$ 1,00 = R$ 100 brutos.
      expect(comJcp.grossDividends.reais, closeTo(100.0, 0.01));
    });

    test('encurta o período e avisa quando um ativo é mais novo', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          Ticker.parse('PETR4'): seriesOf('PETR4', start, [10, 10, 10, 10, 10]),
          Ticker.parse('VALE3'):
              seriesOf('VALE3', start.add(const Duration(days: 2)), [10, 10, 10]),
        },
        dividends: const {},
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money.zero,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('Período encurtado'));
    });

    test('rejeita carteira sem cotações', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: const {},
        dividends: const {},
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money.zero,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('rejeita plano sem aporte algum', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {Ticker.parse('PETR4'): seriesOf('PETR4', start, [10, 11])},
        dividends: const {},
        plan: ContributionPlan.none,
        range: DateRange(start, DateTime(2024, 12, 31)),
      );
      expect(result.isErr, isTrue);
    });
  });
}
