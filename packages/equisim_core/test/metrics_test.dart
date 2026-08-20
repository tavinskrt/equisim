import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('TWR — retorno ponderado pelo tempo', () {
    test('neutraliza o aporte: o salto de caixa não vira retorno', () {
      // Dia 0: R$ 100 aportados.
      // Dia 1: sobe para R$ 110 → +10%.
      // Dia 2: aporta R$ 100 e fecha em R$ 231 → (231−100)/110 − 1 = +19,0909%.
      // TWR = 1,10 × 1,190909… − 1 = 31% exatos.
      final twr = Returns.timeWeighted(
        values: [100, 110, 231],
        externalFlows: [100, 0, 100],
      );
      expect(twr, closeTo(0.31, 1e-12));
    });

    test('sem aportes, TWR coincide com a variação simples', () {
      final twr = Returns.timeWeighted(
        values: [100, 120, 150],
        externalFlows: [100, 0, 0],
      );
      expect(twr, closeTo(0.5, 1e-12));
    });

    test('índice base 100 acompanha o TWR', () {
      final index = Returns.timeWeightedIndex(
        values: [100, 110, 231],
        externalFlows: [100, 0, 100],
      );
      expect(index.first, 100.0);
      expect(index.last, closeTo(131.0, 1e-10));
    });

    test('um aporte gigante não distorce o retorno medido', () {
      // Carteira parada em R$ 100 recebe R$ 10.000 e continua parada:
      // o retorno tem de ser zero, não +9.900%.
      final twr = Returns.timeWeighted(
        values: [100, 10100, 10100],
        externalFlows: [100, 10000, 0],
      );
      expect(twr, closeTo(0.0, 1e-12));
    });
  });

  group('XIRR — retorno ponderado pelo dinheiro', () {
    test('caso de um ano exato devolve a taxa nominal', () {
      final result = Returns.extendedIrr([
        CashFlow(date: DateTime(2024, 1, 1), amount: Money.fromReais(-1000)),
        CashFlow(date: DateTime(2024, 12, 31), amount: Money.fromReais(1100)),
      ]);
      expect(result.isOk, isTrue);
      expect(result.unwrap(), closeTo(0.10, 1e-6));
    });

    test('distingue-se do TWR quando o aporte é bem cronometrado', () {
      // Aportes iguais, mas o segundo entra logo antes de uma alta.
      final result = Returns.extendedIrr([
        CashFlow(date: DateTime(2024, 1, 1), amount: Money.fromReais(-1000)),
        CashFlow(date: DateTime(2024, 7, 1), amount: Money.fromReais(-1000)),
        CashFlow(date: DateTime(2025, 1, 1), amount: Money.fromReais(2400)),
      ]);
      expect(result.isOk, isTrue);
      expect(result.unwrap(), greaterThan(0.0));
    });

    test('exige fluxos de sinais opostos', () {
      final result = Returns.extendedIrr([
        CashFlow(date: DateTime(2024, 1, 1), amount: Money.fromReais(-100)),
        CashFlow(date: DateTime(2024, 6, 1), amount: Money.fromReais(-100)),
      ]);
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InvalidInput>());
    });
  });

  group('RiskMetrics', () {
    test('curva estritamente crescente não tem drawdown', () {
      expect(RiskMetrics.maxDrawdownOf([100, 110, 120, 130]), 0.0);
    });

    test('drawdown mede pico a vale, não início a fim', () {
      // Sobe a 200, cai a 100 (−50%), recupera a 150.
      expect(
        RiskMetrics.maxDrawdownOf([100, 200, 100, 150]),
        closeTo(-0.5, 1e-12),
      );
    });

    test('volatilidade usa desvio amostral e anualiza por raiz de 252', () {
      final returns = [0.01, -0.01, 0.01, -0.01, 0.01, -0.01];
      final vol = RiskMetrics.annualizedVolatility(returns);
      // Desvio amostral de ±1% com média zero ≈ 0,010954; × √252 ≈ 0,1739.
      expect(vol, closeTo(0.1739, 1e-3));
    });

    test('série constante tem volatilidade e Sharpe nulos', () {
      final metrics = RiskMetrics.fromIndex(
        twrIndex: [100, 100, 100, 100],
        cagr: 0.0,
        riskFreeRate: 0.0,
      );
      expect(metrics.volatility, 0.0);
      expect(metrics.sharpe, 0.0);
      expect(metrics.maxDrawdown, 0.0);
    });

    test('Sortino ignora a volatilidade de alta', () {
      final onlyUp = [0.02, 0.03, 0.01, 0.04];
      final downside = RiskMetrics.annualizedDownsideDeviation(onlyUp);
      expect(downside, 0.0);
    });

    test('Sharpe desconta a taxa livre de risco observada', () {
      final metrics = RiskMetrics.fromIndex(
        twrIndex: [100, 101, 102, 103, 104, 105],
        cagr: 0.20,
        riskFreeRate: 0.094, // CDI observado, não constante arbitrária
      );
      expect(metrics.sharpe, greaterThan(0));
      final withoutRiskFree = RiskMetrics.fromIndex(
        twrIndex: [100, 101, 102, 103, 104, 105],
        cagr: 0.20,
        riskFreeRate: 0.0,
      );
      expect(withoutRiskFree.sharpe, greaterThan(metrics.sharpe));
    });
  });

  group('Beta', () {
    test('ativo idêntico ao mercado tem beta 1 e correlação 1', () {
      final market = List.generate(60, (i) => (i % 5 - 2) * 0.01);
      final result = BetaCalculator.estimate(
        assetReturns: market,
        marketReturns: market,
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().beta, closeTo(1.0, 1e-12));
      expect(result.unwrap().correlation, closeTo(1.0, 1e-12));
    });

    test('ativo com o dobro da amplitude tem beta 2', () {
      final market = List.generate(60, (i) => (i % 5 - 2) * 0.01);
      final asset = market.map((r) => r * 2).toList();
      final result = BetaCalculator.estimate(
        assetReturns: asset,
        marketReturns: market,
      );
      expect(result.unwrap().beta, closeTo(2.0, 1e-12));
    });

    test('exige observações suficientes', () {
      final result = BetaCalculator.estimate(
        assetReturns: [0.01, 0.02],
        marketReturns: [0.01, 0.02],
      );
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('pareia séries com pregões desencontrados', () {
      final assetDates = [
        DateTime(2024, 1, 2),
        DateTime(2024, 1, 3),
        DateTime(2024, 1, 4),
      ];
      final marketDates = [
        DateTime(2024, 1, 2),
        DateTime(2024, 1, 4), // mercado não negociou dia 3
      ];
      final aligned = BetaCalculator.alignReturns(
        assetDates: assetDates,
        assetIndex: [100, 110, 121],
        marketDates: marketDates,
        marketIndex: [100, 121],
      );
      expect(aligned.asset.length, 1);
      expect(aligned.market.length, 1);
      expect(aligned.asset.first, closeTo(0.21, 1e-12));
    });
  });
}
