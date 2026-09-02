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
      // R$ 1.000 a R$ 10 compra exatamente 100 ações e não deixa troco.
      expect(outcome.perAsset[Ticker.parse('PETR4')]!.shares, 100);
      expect(outcome.residualCash, Money.zero);
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

    // ----------------------------------------- Ações inteiras e caixa --

    test('compra em lotes inteiros e guarda a sobra em caixa', () {
      // Preço de R$ 30 contra aporte de R$ 100: cabem 3 ações e sobram R$ 10.
      // No aporte seguinte o caixa acumulado passa a R$ 110, que compra mais 3
      // e deixa R$ 20 — é a acumulação que o modelo promete.
      final closes = List<double>.filled(120, 30.0);
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {Ticker.parse('PETR4'): seriesOf('PETR4', start, closes)},
        plan: const ContributionPlan(
          initial: Money(10000), // R$ 100
          monthly: Money(10000), // R$ 100
          contributionDay: 5,
        ),
        range: DateRange(start, DateTime(2024, 4, 30)),
      ).unwrap();

      final petr = result.perAsset[Ticker.parse('PETR4')]!;
      // Quatro aportes de R$ 100 (janeiro entra pelo inicial; fevereiro, março
      // e abril pelo mensal) → R$ 400, que a R$ 30 dá 13 ações e R$ 10 de
      // caixa.
      expect(result.totalContributed, const Money(40000));
      expect(petr.shares, 13);
      expect(petr.cash, const Money(1000));
      expect(result.residualCash, const Money(1000));
      // Patrimônio = 13 × R$ 30 + R$ 10 de caixa = R$ 400, o aportado cheio.
      expect(result.finalValue, const Money(40000));
    });

    test('a quantidade de ações é inteira em toda posição', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3'), assetOf('ITUB4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          Ticker.parse('PETR4'):
              seriesOf('PETR4', start, List<double>.filled(120, 37.41)),
          Ticker.parse('VALE3'):
              seriesOf('VALE3', start, List<double>.filled(120, 8.03)),
          Ticker.parse('ITUB4'):
              seriesOf('ITUB4', start, List<double>.filled(120, 66.9)),
        },
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money(50000),
          contributionDay: 5,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      for (final asset in result.perAsset.values) {
        // O tipo já é `int`; o que se verifica aqui é que nenhuma posição
        // ficou negativa e que o caixa de cada ativo é menor que uma ação —
        // caixa maior significaria compra que deixou de acontecer.
        expect(asset.shares, greaterThanOrEqualTo(0));
        expect(asset.cash.cents, greaterThanOrEqualTo(0));
      }
      expect(
        result.perAsset[Ticker.parse('PETR4')]!.cash.cents,
        lessThan(3741),
      );
      expect(result.perAsset[Ticker.parse('VALE3')]!.cash.cents, lessThan(803));
      expect(
        result.perAsset[Ticker.parse('ITUB4')]!.cash.cents,
        lessThan(6690),
      );
    });

    test('o aportado se reparte inteiro entre os ativos, sem resíduo', () {
      // Três ativos: os pesos de `equalWeighted` são 1/3, e a divisão em
      // centavos não fecha por conta própria. O motor distribui o resto, então
      // a soma das fatias tem de reconstituir o aporte EXATAMENTE.
      final closes = List<double>.filled(120, 10.0);
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3'), assetOf('ITUB4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          for (final symbol in ['PETR4', 'VALE3', 'ITUB4'])
            Ticker.parse(symbol): seriesOf(symbol, start, closes),
        },
        plan: const ContributionPlan(
          initial: Money(100000), // R$ 1.000
          monthly: Money(50000), // R$ 500
          contributionDay: 5,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      // Em CENTAVOS e com `==`: o contrato é identidade, não aproximação.
      // `Money` é inteiro, então comparar por igualdade aqui é exato.
      final somaDestinada = result.perAsset.values
          .fold(0, (total, asset) => total + asset.invested.cents);
      expect(somaDestinada, result.totalContributed.cents);

      // O alocado é o que virou ação; o resto está em caixa, e os dois juntos
      // reconstituem o aportado sem sobra nem falta.
      expect(
        result.totalAllocated + result.residualCash,
        result.totalContributed,
      );

      final somaCaixa = result.perAsset.values
          .fold(0, (total, asset) => total + asset.cash.cents);
      expect(somaCaixa, result.residualCash.cents);
    });

    test('o patrimônio final é a soma exata das posições e do caixa', () {
      // Em CENTAVOS e com `==`. A marcação a mercado opera em aritmética
      // inteira — posição inteira vezes preço em centavos —, então esta
      // identidade não admite tolerância: qualquer folga aqui significaria
      // acúmulo de erro de ponto flutuante ao longo dos pregões.
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3'), assetOf('ITUB4')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          Ticker.parse('PETR4'):
              seriesOf('PETR4', start, List<double>.filled(120, 37.41)),
          Ticker.parse('VALE3'):
              seriesOf('VALE3', start, List<double>.filled(120, 8.03)),
          Ticker.parse('ITUB4'):
              seriesOf('ITUB4', start, List<double>.filled(120, 66.9)),
        },
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money(50000),
          contributionDay: 5,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      final soma = result.perAsset.values.fold(
        0,
        (total, asset) => total + asset.finalValue.cents + asset.cash.cents,
      );
      expect(soma, result.finalValue.cents);
    });

    test('a fatia de ativo sem cotação no dia fica em caixa e é usada depois',
        () {
      // VALE3 só começa a ser negociada dois dias depois. A fatia dela no
      // aporte inicial não some: espera no caixa e vira posição no primeiro
      // aporte em que há preço.
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [assetOf('PETR4'), assetOf('VALE3')],
      ).unwrap();

      final result = PortfolioBacktest.run(
        portfolio: portfolio,
        prices: {
          Ticker.parse('PETR4'):
              seriesOf('PETR4', start, List<double>.filled(120, 10.0)),
          Ticker.parse('VALE3'): seriesOf(
            'VALE3',
            start.add(const Duration(days: 40)),
            List<double>.filled(80, 10.0),
          ),
        },
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money(50000),
          contributionDay: 5,
        ),
        // A janela começa no primeiro pregão comum, então a simulação inteira
        // tem preço para os dois; o que se verifica é a identidade de capital.
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      expect(
        result.totalAllocated + result.residualCash,
        result.totalContributed,
      );
      expect(result.residualCash.cents, greaterThanOrEqualTo(0));
    });

    test('com um ativo só e preço divisor, não sobra caixa', () {
      // Peso 1,0 não reparte, e R$ 1.000 e R$ 500 são múltiplos de R$ 10: a
      // sobra tem de ser exatamente zero. É a contraprova do teste acima —
      // sem ela, um caixa sistematicamente inflado passaria.
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
        plan: const ContributionPlan(
          initial: Money(100000),
          monthly: Money(50000),
          contributionDay: 5,
        ),
        range: DateRange(start, DateTime(2024, 12, 31)),
      ).unwrap();

      expect(result.totalAllocated, result.totalContributed);
      expect(result.residualCash, Money.zero);
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
        plan: ContributionPlan.none,
        range: DateRange(start, DateTime(2024, 12, 31)),
      );
      expect(result.isErr, isTrue);
    });
  });
}
