import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// A ordenação transversal que decide o prêmio do retorno esperado (item B1).
void main() {
  group('Escore robusto', () {
    test('(x − mediana) ÷ MAD escalado, confinado a ±2', () {
      // Mediana 3; desvios 2, 1, 0, 1, 97 → MAD 1 → escala 1,4826.
      final z = TransversalScore.robustZ({'a': 1.0, 'b': 2.0, 'c': 3.0, 'd': 4.0, 'e': 100.0});
      expect(z['a'], closeTo(-2 / 1.4826, 1e-12));
      expect(z['c'], 0.0);
      expect(z['d'], closeTo(1 / 1.4826, 1e-12));
      expect(z['e'], 2.0, reason: 'a cauda é confinada, e não decide sozinha');
    });

    test('seção sem escala dá zero a todos, e valor não finito sai', () {
      expect(TransversalScore.robustZ({'a': 1.0, 'b': 2.0}), {'a': 0.0, 'b': 0.0});
      expect(TransversalScore.robustZ({'a': 5.0, 'b': 5.0, 'c': 5.0, 'd': 5.0}),
          {'a': 0.0, 'b': 0.0, 'c': 0.0, 'd': 0.0});
      expect(TransversalScore.robustZ({'a': double.nan, 'b': 1.0}).containsKey('a'),
          isFalse);
    });
  });

  group('Ordenações', () {
    final sinais = {
      'A': const TransversalSignals(potential: -0.5, bookToMarket: 0.2, earningsYield: 0.02),
      'B': const TransversalSignals(potential: 0.1, bookToMarket: 0.6, earningsYield: 0.08),
      'C': const TransversalSignals(potential: 0.4, bookToMarket: 1.4, earningsYield: 0.15),
      'D': const TransversalSignals(potential: 0.0, bookToMarket: null, earningsYield: 0.05),
    };

    test('a de um sinal só é o escore dele, e quem não tem o sinal fica fora', () {
      final bm = TransversalScore.scores(sinais, TransversalOrdering.bookToMarket);
      expect(bm.keys, unorderedEquals(['A', 'B', 'C']));
      expect(bm, TransversalScore.robustZ({'A': 0.2, 'B': 0.6, 'C': 1.4}));
      final pot = TransversalScore.scores(sinais, TransversalOrdering.potential);
      expect(pot.keys, unorderedEquals(['A', 'B', 'C', 'D']));
    });

    test('o composto é a média dos escores que o ativo tem, com pesos iguais', () {
      final comp = TransversalScore.scores(sinais, TransversalOrdering.composite);
      final zP = TransversalScore.robustZ({for (final e in sinais.entries) e.key: e.value.potential!});
      final zB = TransversalScore.robustZ({'A': 0.2, 'B': 0.6, 'C': 1.4});
      final zE = TransversalScore.robustZ({for (final e in sinais.entries) e.key: e.value.earningsYield!});
      expect(comp['B'], closeTo((zP['B']! + zB['B']! + zE['B']!) / 3, 1e-12));
      // Sem book-to-market, a média é dos dois que ele tem.
      expect(comp['D'], closeTo((zP['D']! + zE['D']!) / 2, 1e-12));
    });

    test('os sinais saem do último exercício, pela conta das coortes', () {
      final s = TransversalSignals.of(
        FundamentalsSnapshot(
          ticker: Ticker.parse('PETR4'),
          fiscalPeriodEnd: DateTime(2025, 12, 31),
          marketCap: 1000,
          bookValuePerShare: 4,
          sharesOutstandingAsOf: 100,
          netIncome: 80,
        ),
        potential: -0.2,
      );
      expect(s.potential, -0.2);
      expect(s.bookToMarket, closeTo(0.4, 1e-12));
      expect(s.earningsYield, closeTo(0.08, 1e-12));
      final semVm = TransversalSignals.of(FundamentalsSnapshot(
        ticker: Ticker.parse('PETR4'),
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        bookValuePerShare: 4,
        sharesOutstandingAsOf: 100,
        netIncome: 80,
      ));
      expect(semVm.bookToMarket, isNull);
      expect(semVm.earningsYield, isNull);
      expect(TransversalSignals.of(null).bookToMarket, isNull);
    });

    test('da série, vale o último exercício publicado na data, e não o último', () {
      FundamentalsSnapshot exercicio(int ano, double lucro) => FundamentalsSnapshot(
            ticker: Ticker.parse('PETR4'),
            fiscalPeriodEnd: DateTime(ano, 12, 31),
            marketCap: 1000,
            bookValuePerShare: 4,
            sharesOutstandingAsOf: 100,
            netIncome: lucro,
          );
      final serie = [exercicio(2024, 50), exercicio(2025, 80)];
      // Em 30/01/2026 o exercício de 2025 ainda não foi publicado.
      final antes = TransversalSignals.fromHistory(serie, asOf: DateTime(2026, 1, 30));
      final depois = TransversalSignals.fromHistory(serie, asOf: DateTime(2026, 9, 16));
      expect(antes.earningsYield, closeTo(0.05, 1e-12));
      expect(depois.earningsYield, closeTo(0.08, 1e-12));
    });
  });

  group('Retorno esperado com a ordenação medida', () {
    final a = Ticker.parse('AAAA3');
    final b = Ticker.parse('BBBB3');
    final c = Ticker.parse('CCCC3');
    ValuationResult avaliacao(Ticker t, {required double ke, double upside = 0}) =>
        ValuationResult(
          ticker: t,
          asOf: DateTime(2026, 9, 16),
          model: ValuationModel.dcfFcff,
          fairValue: Money.fromReais(10 * (1 + upside)),
          marketPrice: Money.fromReais(10),
          discountRate: 0.13,
          diagnostics: ValuationDiagnostics(
            terminalShare: 0.5,
            equityShare: 0.8,
            baseFactor: 1,
            growthIdentified: true,
            moatApplied: false,
            costOfEquity: ke,
            terminalDiscountRate: 0.12,
            terminalRetainedSpread: 0,
            growthRate: 0.05,
            returnOnCapital: 0.15,
          ),
        );
    Portfolio carteiraDe(List<Ticker> ts) => Portfolio.equalWeighted(
          id: 'p',
          name: 'Principal',
          kind: PortfolioKind.principal,
          assets: [
            for (final t in ts)
              Asset(ticker: t, name: t.value, sector: Sector.fromKey('energia', label: 'energia')),
          ],
        ).unwrap();
    final carteira = carteiraDe([a, b, c]);
    final avaliacoes = {
      a: avaliacao(a, ke: 0.14, upside: -0.3),
      b: avaliacao(b, ke: 0.15, upside: 0.0),
      c: avaliacao(c, ke: 0.16, upside: 0.3),
    };

    test('sem ordenação não há prêmio: é a média dos Ke', () {
      final r = ExpectedReturn.forPortfolioOrdered(
        portfolio: carteira,
        valuations: avaliacoes,
        signals: const {},
        ordering: null,
        spotRiskFree: 0.14,
      );
      expect(r, closeTo((0.14 + 0.15 + 0.16) / 3, 1e-12));
    });

    test('com o book-to-market, quem é mais barato por ele espera mais', () {
      double esperado(double bmA) => ExpectedReturn.forPortfolioOrdered(
            portfolio: carteiraDe([a]),
            valuations: avaliacoes,
            signals: {
              a: TransversalSignals(bookToMarket: bmA),
              b: const TransversalSignals(bookToMarket: 0.5),
              c: const TransversalSignals(bookToMarket: 0.8),
            },
            ordering: TransversalOrdering.bookToMarket,
            spotRiskFree: 0.14,
          );
      // A seção é a da carteira; com um ativo só não há escala, e o prêmio é
      // zero — a leitura neutra.
      expect(esperado(2.0), closeTo(0.14, 1e-12));

      final comTres = ExpectedReturn.forPortfolioOrdered(
        portfolio: carteira,
        valuations: avaliacoes,
        signals: {
          a: const TransversalSignals(bookToMarket: 2.0),
          b: const TransversalSignals(bookToMarket: 0.5),
          c: const TransversalSignals(bookToMarket: 0.8),
        },
        ordering: TransversalOrdering.bookToMarket,
        spotRiskFree: 0.14,
      );
      final z = TransversalScore.robustZ({a: 2.0, b: 0.5, c: 0.8});
      const premio = CapmInputs.defaultMarketPremium;
      expect(
          comTres,
          closeTo(
              ((0.14 + z[a]! * premio) + (0.15 + z[b]! * premio) + (0.16 + z[c]! * premio)) / 3,
              1e-12));
    });

    test('ativo avaliado sem o sinal recebe a âncora, e não sai da conta', () {
      final r = ExpectedReturn.forPortfolioOrdered(
        portfolio: carteira,
        valuations: avaliacoes,
        signals: {
          a: const TransversalSignals(bookToMarket: 2.0),
          b: const TransversalSignals(bookToMarket: 0.5),
        },
        ordering: TransversalOrdering.bookToMarket,
        spotRiskFree: 0.14,
      );
      // Dois com sinal: seção curta demais para escala, prêmio zero nos dois;
      // o terceiro, sem sinal, fica no Ke dele. A média é a dos três Ke.
      expect(r, closeTo((0.14 + 0.15 + 0.16) / 3, 1e-12));
    });
  });
}
