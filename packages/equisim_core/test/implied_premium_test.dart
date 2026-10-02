// O prêmio de mercado é a média de dez anos do prêmio implícito (decisão 142).
//
// A série chega por pacote, e a média sai dela: os trimestres com fim em
// `(data − dez anos, data]`, com pelo menos vinte; o prêmio de cada trimestre é
// `r − Rf`, a forma que o CAPM do motor soma.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Trimestres de 2011 a 2026, com `r − Rf` igual a [premio] de cada um.
ImpliedPremiumPackage _pacote(double Function(DateTime) premio) {
  final q = <ImpliedPremiumQuarter>[];
  for (var ano = 2011; ano <= 2026; ano++) {
    for (final mes in const [3, 6, 9, 12]) {
      final d = DateTime.utc(ano, mes + 1, 0);
      if (d.isAfter(DateTime.utc(2026, 6, 30))) continue;
      q.add(
        ImpliedPremiumQuarter(
          date: d,
          impliedReturn: 0.13 + premio(d),
          riskFree: 0.13,
        ),
      );
    }
  }
  return ImpliedPremiumPackage(
    geradoEm: DateTime.utc(2026, 9, 14),
    quarters: q,
  );
}

void main() {
  test('o prêmio do trimestre é r − Rf, e não a razão de Fisher', () {
    final q = ImpliedPremiumQuarter(
      date: DateTime.utc(2026, 9, 14),
      impliedReturn: 0.1326,
      riskFree: 0.1438,
    );
    expect(q.premium, closeTo(-0.0112, 1e-12));
  });

  test('a média é a dos trimestres em (data − dez anos, data]', () {
    // Prêmio de 1% até 2016 e de 2% depois: em 14/09/2026 a janela começa no
    // trimestre de 30/09/2016, e tem 40 trimestres, 39 deles de 2%.
    final p = _pacote((d) => d.year <= 2016 && d.month <= 6 ? 0.01 : 0.02);
    final janela = p.window(DateTime(2026, 9, 14));
    expect(janela.length, 40);
    expect(janela.first.date, DateTime.utc(2016, 9, 30));
    expect(janela.last.date, DateTime.utc(2026, 6, 30));
    expect(p.normalizedAt(DateTime(2026, 9, 14)), closeTo(0.02, 1e-12));
  });

  test('a ponta final entra, e a inicial não', () {
    final p = _pacote((d) => d == DateTime.utc(2016, 6, 30) ? 1.0 : 0.0);
    // Em 30/06/2026 a janela é (30/06/2016, 30/06/2026]: o trimestre de
    // 30/06/2016 fica fora, e o de 30/06/2026 entra.
    expect(p.normalizedAt(DateTime(2026, 6, 30)), 0.0);
    expect(
      p.window(DateTime(2026, 6, 30)).last.date,
      DateTime.utc(2026, 6, 30),
    );
    expect(
      p.normalizedAt(DateTime(2026, 6, 29)),
      greaterThan(0),
      reason: 'um dia antes, a janela ainda alcança 30/06/2016',
    );
  });

  test('com menos de vinte trimestres não há média, e com vinte há', () {
    final p = _pacote((_) => 0.015);
    // A série começa em 31/03/2011: em 31/12/2015 há 20 trimestres.
    expect(p.window(DateTime(2015, 12, 31)).length, 20);
    expect(p.normalizedAt(DateTime(2015, 12, 31)), closeTo(0.015, 1e-12));
    expect(p.normalizedAt(DateTime(2015, 9, 30)), isNull);
    // As coortes de 2018 usam os trimestres que havia: 29 em 31/03/2018.
    expect(p.window(DateTime(2018, 3, 31)).length, 29);
  });

  test('o último trimestre medido até a data', () {
    final p = _pacote((_) => 0.0);
    expect(p.latestAt(DateTime(2026, 9, 14))!.date, DateTime.utc(2026, 6, 30));
    expect(p.latestAt(DateTime(2010, 1, 1)), isNull);
  });

  group('codec', () {
    test('ida e volta preservam a série', () {
      final p = _pacote((d) => d.year / 100000);
      final lido = ImpliedPremiumCodec.decode(ImpliedPremiumCodec.encode(p))!;
      expect(lido.geradoEm, p.geradoEm);
      expect(lido.quarters.length, p.quarters.length);
      expect(
        lido.normalizedAt(DateTime(2026, 9, 14)),
        closeTo(p.normalizedAt(DateTime(2026, 9, 14))!, 1e-15),
      );
    });

    test('recusa versão diferente, série vazia e número não finito', () {
      final bom = ImpliedPremiumCodec.encode(_pacote((_) => 0.01));
      expect(ImpliedPremiumCodec.decode({...bom, 'versao': 99}), isNull);
      expect(
        ImpliedPremiumCodec.decode({...bom, 'trimestres': <Object>[]}),
        isNull,
      );
      expect(ImpliedPremiumCodec.decode({...bom, 'geradoEm': 'ontem'}), isNull);
      expect(
        ImpliedPremiumCodec.decode({
          ...bom,
          'trimestres': [
            {
              'data': '2020-03-31',
              'retornoImplicito': double.nan,
              'prefixado10': 0.1,
            },
          ],
        }),
        isNull,
      );
      expect(
        ImpliedPremiumCodec.decode({
          ...bom,
          'trimestres': [
            {'data': '2020-03-31', 'prefixado10': 0.1},
          ],
        }),
        isNull,
      );
    });
  });

  test('o rastro do CAPM diz de onde veio o prêmio', () {
    final capturados = <AuditEvent>[];
    AuditRecorder.attach(capturados.add);
    addTearDown(AuditRecorder.detach);
    for (final (origem, trecho) in const [
      (
        MarketPremiumSource.impliedNormalized,
        'média de dez anos do prêmio implícito',
      ),
      (MarketPremiumSource.parameterized, 'o prêmio parametrizado'),
    ]) {
      capturados.clear();
      ValuationCascade.evaluate(
        ValuationInputs(
          ticker: Ticker.parse('PREM3'),
          asOf: DateTime(2026, 8, 20),
          fundamentals: [
            for (var year = 2016; year <= 2025; year++)
              FundamentalsSnapshot(
                ticker: Ticker.parse('PREM3'),
                fiscalPeriodEnd: DateTime(year, 12, 31),
                netIncome: 1000.0 * (year - 2015),
                ebit: 1400.0 * (year - 2015),
                ebitda: 1800.0 * (year - 2015),
                incomeBeforeTax: 1300.0 * (year - 2015),
                incomeTaxExpense: 300.0 * (year - 2015),
                interestExpense: 120.0,
                operatingCashFlow: 1600.0 * (year - 2015),
                freeCashFlow: 1200.0 * (year - 2015),
                shortTermDebt: 400.0,
                longTermDebt: 1600.0,
                cash: 300.0,
                nopat: 1000.0 * (year - 2015),
                sharesOutstanding: 1000.0,
                sharesOutstandingAsOf: 1000.0,
                marketCap: 20000.0,
                bookValuePerShare: 8.0 * (year - 2015),
                enterpriseToEbitda: 6.0,
              ),
          ],
          marketPrice: 20.0,
          capm: CapmInputs(
            riskFreeRate: 0.105,
            beta: 1.2,
            marketPremium: 0.0136,
            premiumSource: origem,
          ),
          projectionYears: 5,
        ),
      );
      final capm = capturados.single.calculations.firstWhere(
        (c) => c.formulaName.contains('CAPM'),
      );
      expect(capm.mappedVariables['origem do prêmio'], origem.name);
      expect(capm.intermediateSteps.first, contains(trecho));
    }
  });
}
