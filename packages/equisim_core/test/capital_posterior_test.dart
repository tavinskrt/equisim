// O capital emitido depois do balanço entra no patrimônio da ponte (item B28).
//
// O patrimônio vem do último balanço publicado, e o divisor é a contagem que
// forma a cotação de hoje. Uma emissão entre as duas datas estava na contagem e
// não no patrimônio: o preço justo por papel saía subavaliado na proporção do
// capital captado.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');

FundamentalsSnapshot _year(int y, double scale) => FundamentalsSnapshot(
  ticker: _ticker,
  fiscalPeriodEnd: DateTime(y, 12, 31),
  totalRevenue: 10000 * scale,
  ebit: 1800 * scale,
  ebitda: 2400 * scale,
  netIncome: 900 * scale,
  incomeBeforeTax: 1300 * scale,
  incomeTaxExpense: -400 * scale,
  interestExpense: 400,
  earningsPerShare: 0.9 * scale,
  cash: 200,
  shortTermDebt: 1000,
  longTermDebt: 3000,
  totalStockholderEquity: 6000 * scale,
  bookValuePerShare: 6.0 * scale,
  operatingCashFlow: 2000 * scale,
  nopat: 1188 * scale,
  sharesOutstanding: 1000,
  sharesOutstandingAsOf: 1000,
  marketCap: 12000,
);

List<FundamentalsSnapshot> _series() {
  final out = <FundamentalsSnapshot>[];
  var scale = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(_year(2025 - i, scale));
    scale *= 1.05;
  }
  return out;
}

ValuationInputs _inputs({
  List<ShareIssue> issuances = const [],
  bool bank = false,
}) => ValuationInputs(
  ticker: _ticker,
  asOf: DateTime(2026, 9, 9),
  fundamentals: _series(),
  marketPrice: 12.0,
  capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
  declaredTerminalRiskFreeRate: 0.094,
  sectorKey: bank ? 'financeiro' : null,
  industry: bank ? 'Intermediários Financeiros / Bancos' : null,
  shareIssues: issuances,
);

ValuationResult _evaluate(ValuationInputs i) {
  final r = ValuationCascade.evaluate(i);
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

/// O papel da contagem que forma a cotação: `VM ÷ P` = 12.000 ÷ 12.
const _shares = 1000.0;

void main() {
  final after = ShareIssue(
    date: DateTime(2026, 4, 15),
    amount: Money.fromReais(1200),
    shares: 100,
  );

  group('a via da firma', () {
    test('sem emissão, nada muda', () {
      final a = _evaluate(_inputs());
      final b = _evaluate(_inputs(issuances: const []));
      expect(b.fairValue.reais, closeTo(a.fairValue.reais, 1e-9));
      expect(a.diagnostics!.postStatementCapital, isNull);
    });

    test(
      'a emissão depois do balanço soma capital ÷ papéis ao preço justo',
      () {
        final without = _evaluate(_inputs());
        final withInput = _evaluate(_inputs(issuances: [after]));
        expect(withInput.model, ValuationModel.dcfFcff);
        // O preço justo é arredondado ao centavo no resultado.
        expect(
          withInput.fairValue.reais,
          closeTo(without.fairValue.reais + 1200 / _shares, 0.011),
        );
        expect(withInput.diagnostics!.postStatementCapital, closeTo(1200, 1e-9));
        expect(
          withInput.warnings.any(
            (w) => w.contains('emitiu ações') && w.contains('31/12/2025'),
          ),
          isTrue,
        );
      },
    );

    test('a emissão antes do balanço já está nele, e a posterior à data não '
        'existia', () {
      final without = _evaluate(_inputs());
      for (final outside in [
        ShareIssue(
          date: DateTime(2025, 12, 31),
          amount: Money.fromReais(1200),
          shares: 100,
        ),
        ShareIssue(
          date: DateTime(2025, 6, 1),
          amount: Money.fromReais(1200),
          shares: 100,
        ),
        ShareIssue(
          date: DateTime(2026, 9, 10),
          amount: Money.fromReais(1200),
          shares: 100,
        ),
      ]) {
        final r = _evaluate(_inputs(issuances: [outside]));
        expect(
          r.fairValue.reais,
          closeTo(without.fairValue.reais, 1e-9),
          reason: '${outside.date}',
        );
        expect(r.diagnostics!.postStatementCapital, isNull);
      }
    });

    test('emissão sem valor ou sem ação não entra', () {
      final without = _evaluate(_inputs());
      final r = _evaluate(
        _inputs(
          issuances: [
            ShareIssue(
              date: DateTime(2026, 3, 1),
              amount: Money.fromReais(0),
              shares: 100,
            ),
            ShareIssue(
              date: DateTime(2026, 3, 1),
              amount: Money.fromReais(500),
              shares: 0,
            ),
            ShareIssue(
              date: DateTime(2026, 3, 1),
              amount: Money.fromReais(-5),
              shares: 1,
            ),
          ],
        ),
      );
      expect(r.fairValue.reais, closeTo(without.fairValue.reais, 1e-9));
    });

    test('variação de capital sem declaração não entra, e é avisada', () {
      // Desde 2023 o FRE não declara emissão por emissão: a variação do
      // capital não separa emissão de bonificação ou de troca de ações numa
      // reorganização, e somá-la erraria por fatores inteiros.
      final without = _evaluate(_inputs());
      final r = _evaluate(
        _inputs(
          issuances: [
            ShareIssue(
              date: DateTime(2026, 5, 19),
              amount: Money.fromReais(1200),
              shares: 100,
              declared: false,
            ),
          ],
        ),
      );
      expect(r.fairValue.reais, closeTo(without.fairValue.reais, 1e-9));
      expect(r.diagnostics!.postStatementCapital, isNull);
      expect(
        r.warnings.any(
          (w) =>
              w.contains('não foi somada') && w.contains('subavaliado em até'),
        ),
        isTrue,
      );
    });

    test('o cenário base continua sendo o preço justo', () {
      final withInput = _evaluate(_inputs(issuances: [after]));
      final base = withInput.discreteScenarios?[ScenarioBand.base];
      expect(base, isNotNull);
      expect(base!.reais, closeTo(withInput.fairValue.reais, 0.011));
    });

    test(
      'o rastro mostra o capital do balanço e soma o novo num passo seu',
      () {
        final events = <AuditEvent>[];
        AuditRecorder.attach(events.add);
        try {
          _evaluate(_inputs(issuances: [after]));
        } finally {
          AuditRecorder.detach();
        }
        final ev = events.single;
        final stepCount = [
          for (final t in ev.calculations) ...t.intermediateSteps,
        ];
        expect(stepCount.any((p) => p.startsWith('Passo 4b')), isTrue);
        expect(ev.inputPayload['shareIssues'], isA<List<Object?>>());
        final diag = ev.outputPayload['diagnostics'] as Map;
        expect(diag['postStatementCapital'], closeTo(1200, 1e-6));
      },
    );
  });

  test('a via do acionista soma o mesmo por papel', () {
    // O banco do teste da Porta 1: lucro de 12% sobre o patrimônio, sem dívida.
    List<FundamentalsSnapshot> bank() {
      final points = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var year = 2012; year <= 2025; year++) {
        final profit = 0.12 * pl;
        pl += profit;
        points.add(
          FundamentalsSnapshot(
            ticker: _ticker,
            fiscalPeriodEnd: DateTime(year, 12, 31),
            bookValuePerShare: pl / 1000,
            sharesOutstanding: 1000,
            sharesOutstandingAsOf: 1000,
            netIncome: year == 2012 ? null : profit,
            nopat: profit,
            ebit: profit * 1.4,
            longTermDebt: 0,
            marketCap: 20000,
          ),
        );
      }
      return points;
    }

    ValuationResult evaluate(List<ShareIssue> issuances) => _evaluate(
      ValuationInputs(
        ticker: _ticker,
        asOf: DateTime(2026, 6, 30),
        fundamentals: bank(),
        marketPrice: 20.0,
        capm: const CapmInputs(
          riskFreeRate: 0.105,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        sectorKey: 'financeiro',
        industry: 'Intermediários Financeiros / Bancos',
        shareIssues: issuances,
      ),
    );

    final without = evaluate(const []);
    final withInput = evaluate([after]);
    expect(withInput.model, ValuationModel.dcfEarnings);
    // `VM ÷ P` = 20.000 ÷ 20 = 1.000 papéis.
    expect(
      withInput.fairValue.reais,
      closeTo(without.fairValue.reais + 1200 / 1000, 0.011),
    );
    expect(withInput.diagnostics!.postStatementCapital, closeTo(1200, 1e-9));
  });
}
