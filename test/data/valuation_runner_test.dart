import 'package:equisim/data/isolate/valuation_runner.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// O rastro atravessa a isolate (item D4).
///
/// O coletor de auditoria é estático e local à isolate: a avaliação que migra
/// para outra — Monte Carlo com 20 mil sorteios ou mais, fora do web — saía sem
/// evento no painel de logs. Aqui ela roda de fato em outra isolate, e o
/// evento precisa chegar a esta com os passos inteiros.
void main() {
  final ticker = Ticker.parse('PETR4');
  final inputs = ValuationInputs(
    ticker: ticker,
    asOf: DateTime(2026, 8, 20),
    fundamentals: [
      for (var year = 2016; year <= 2025; year++)
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(year, 12, 31),
          netIncome: 1000.0 * (year - 2015),
          ebit: 1400.0 * (year - 2015),
          ebitda: 1800.0 * (year - 2015),
          incomeBeforeTax: 1300.0 * (year - 2015),
          incomeTaxExpense: -300.0 * (year - 2015),
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
        ),
    ],
    marketPrice: 20.0,
    capm: const CapmInputs(riskFreeRate: 0.105, beta: 1.2, marketPremium: 0.055),
  );

  test('a avaliação que migra de isolate chega ao painel com o rastro', () async {
    final eventos = <AuditEvent>[];
    AuditRecorder.attach(eventos.add);
    addTearDown(AuditRecorder.detach);

    final r = await ValuationRunner.run(ValuationRequest(
      inputs: inputs,
      monteCarlo: true,
      samples: ValuationRunner.isolateThresholdSamples,
    ));

    expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
    expect(eventos, hasLength(1));
    expect(eventos.single.endpoint, '/core/valuation/PETR4');
    expect(eventos.single.calculations, isNotEmpty);
    expect(eventos.single.outputPayload['fairValue'],
        r.unwrap().fairValue.reais);
    expect(AuditRecorder.isActive, isTrue,
        reason: 'o coletor desta isolate continua ligado');
  });

  test('a recusa dentro da isolate volta como falha, com o evento, e sem '
      'travar', () async {
    // Lente `risco`, 25/09/2026: o teste cobria só o caminho feliz. Sem
    // exercícios não há via, e a cascata recusa — dentro da outra isolate. A
    // falha tem de voltar como `Err`, com o evento de recusa no painel.
    final eventos = <AuditEvent>[];
    AuditRecorder.attach(eventos.add);
    addTearDown(AuditRecorder.detach);

    final r = await ValuationRunner.run(ValuationRequest(
      inputs: inputs.withFundamentals(const []),
      monteCarlo: true,
      samples: ValuationRunner.isolateThresholdSamples,
    )).timeout(const Duration(seconds: 30));

    expect(r.isErr, isTrue);
    expect(eventos, hasLength(1));
    expect(eventos.single.endpoint, '/core/valuation/PETR4');
  });

  test('sem ninguém ouvindo, a isolate não monta rastro', () async {
    expect(AuditRecorder.isActive, isFalse);
    final r = await ValuationRunner.run(ValuationRequest(
      inputs: inputs,
      monteCarlo: true,
      samples: ValuationRunner.isolateThresholdSamples,
    ));
    expect(r.isOk, isTrue);
  });
}
