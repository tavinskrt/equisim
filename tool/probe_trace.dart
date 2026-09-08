// Inspeciona o rastro de auditoria de uma avaliação sintética, para conferir
// quantas etapas carregam amostra e por qual via passaram.
import 'package:equisim_core/equisim_core.dart';

void main() {
  final ticker = Ticker.parse('SAPR11');
  const lucro = {
    2016: 700.0,
    2017: 750.0,
    2018: 820.0,
    2019: 900.0,
    2020: 1000.0,
    2021: 1100.0,
    2022: 1150.0,
    2023: 1200.0,
    2024: 1250.0,
    2025: 400.0,
  };

  AuditRecorder.attach((e) {
    // ignore: avoid_print
    print('evento ${e.endpoint} · etapas=${e.calculations.length}');
    for (final c in e.calculations) {
      // ignore: avoid_print
      print('   - ${c.formulaName}'
          '${c.sample == null ? '' : '  [amostra: ${c.sample!.title}]'}');
    }
  });

  final r = ValuationCascade.evaluate(ValuationInputs(
    ticker: ticker,
    asOf: DateTime(2026, 8, 20),
    fundamentals: [
      for (final entry in lucro.entries)
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(entry.key, 12, 31),
          netIncome: entry.value,
          nopat: entry.value,
          ebit: entry.value * 1.4,
          ebitda: entry.value * 1.8,
          incomeBeforeTax: entry.value * 1.3,
          incomeTaxExpense: entry.value * 0.3,
          interestExpense: 120.0,
          operatingCashFlow: entry.value,
          freeCashFlow: entry.value,
          shortTermDebt: 400.0,
          longTermDebt: 1600.0,
          cash: 300.0,
          sharesOutstanding: 1000.0,
          sharesOutstandingAsOf: 1000.0,
          marketCap: 20000.0,
          bookValuePerShare: 8.0 + (entry.key - 2016) * 0.5,
          enterpriseToEbitda: 6.0,
        ),
    ],
    marketPrice: 20.0,
    capm: const CapmInputs(
      riskFreeRate: 0.105,
      beta: 1.2,
      marketPremium: 0.055,
    ),
  ));

  // ignore: avoid_print
  print('resultado: ${r.isOk ? r.unwrap().model.name : r.failureOrNull?.message}');
  if (r.isOk) {
    // ignore: avoid_print
    print('preço justo ${r.unwrap().fairValue.reais}');
    for (final w in r.unwrap().warnings) {
      // ignore: avoid_print
      print('   aviso: $w');
    }
  }
  AuditRecorder.detach();
}
