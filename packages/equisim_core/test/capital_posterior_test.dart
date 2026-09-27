// O capital emitido depois do balanço entra no patrimônio da ponte (item B28).
//
// O patrimônio vem do último balanço publicado, e o divisor é a contagem que
// forma a cotação de hoje. Uma emissão entre as duas datas estava na contagem e
// não no patrimônio: o preço justo por papel saía subavaliado na proporção do
// capital captado.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');

FundamentalsSnapshot _ano(int y, double escala) => FundamentalsSnapshot(
  ticker: _ticker,
  fiscalPeriodEnd: DateTime(y, 12, 31),
  totalRevenue: 10000 * escala,
  ebit: 1800 * escala,
  ebitda: 2400 * escala,
  netIncome: 900 * escala,
  incomeBeforeTax: 1300 * escala,
  incomeTaxExpense: -400 * escala,
  interestExpense: 400,
  earningsPerShare: 0.9 * escala,
  cash: 200,
  shortTermDebt: 1000,
  longTermDebt: 3000,
  totalStockholderEquity: 6000 * escala,
  bookValuePerShare: 6.0 * escala,
  operatingCashFlow: 2000 * escala,
  nopat: 1188 * escala,
  sharesOutstanding: 1000,
  sharesOutstandingAsOf: 1000,
  marketCap: 12000,
);

List<FundamentalsSnapshot> _serie() {
  final out = <FundamentalsSnapshot>[];
  var escala = 1.0;
  for (var i = 12; i >= 0; i--) {
    out.add(_ano(2025 - i, escala));
    escala *= 1.05;
  }
  return out;
}

ValuationInputs _insumos({
  List<ShareIssue> emissoes = const [],
  bool banco = false,
}) => ValuationInputs(
  ticker: _ticker,
  asOf: DateTime(2026, 9, 9),
  fundamentals: _serie(),
  marketPrice: 12.0,
  capm: const CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
  declaredTerminalRiskFreeRate: 0.094,
  sectorKey: banco ? 'financeiro' : null,
  industry: banco ? 'Intermediários Financeiros / Bancos' : null,
  shareIssues: emissoes,
);

ValuationResult _avaliar(ValuationInputs i) {
  final r = ValuationCascade.evaluate(i);
  expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
  return r.unwrap();
}

/// O papel da contagem que forma a cotação: `VM ÷ P` = 12.000 ÷ 12.
const _papeis = 1000.0;

void main() {
  final depois = ShareIssue(
    date: DateTime(2026, 4, 15),
    amount: Money.fromReais(1200),
    shares: 100,
  );

  group('a via da firma', () {
    test('sem emissão, nada muda', () {
      final a = _avaliar(_insumos());
      final b = _avaliar(_insumos(emissoes: const []));
      expect(b.fairValue.reais, closeTo(a.fairValue.reais, 1e-9));
      expect(a.diagnostics!.postStatementCapital, isNull);
    });

    test(
      'a emissão depois do balanço soma capital ÷ papéis ao preço justo',
      () {
        final sem = _avaliar(_insumos());
        final com = _avaliar(_insumos(emissoes: [depois]));
        expect(com.model, ValuationModel.dcfFcff);
        // O preço justo é arredondado ao centavo no resultado.
        expect(
          com.fairValue.reais,
          closeTo(sem.fairValue.reais + 1200 / _papeis, 0.011),
        );
        expect(com.diagnostics!.postStatementCapital, closeTo(1200, 1e-9));
        expect(
          com.warnings.any(
            (w) => w.contains('emitiu ações') && w.contains('31/12/2025'),
          ),
          isTrue,
        );
      },
    );

    test('a emissão antes do balanço já está nele, e a posterior à data não '
        'existia', () {
      final sem = _avaliar(_insumos());
      for (final fora in [
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
        final r = _avaliar(_insumos(emissoes: [fora]));
        expect(
          r.fairValue.reais,
          closeTo(sem.fairValue.reais, 1e-9),
          reason: '${fora.date}',
        );
        expect(r.diagnostics!.postStatementCapital, isNull);
      }
    });

    test('emissão sem valor ou sem ação não entra', () {
      final sem = _avaliar(_insumos());
      final r = _avaliar(
        _insumos(
          emissoes: [
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
      expect(r.fairValue.reais, closeTo(sem.fairValue.reais, 1e-9));
    });

    test('variação de capital sem declaração não entra, e é avisada', () {
      // Desde 2023 o FRE não declara emissão por emissão: a variação do
      // capital não separa emissão de bonificação ou de troca de ações numa
      // reorganização, e somá-la erraria por fatores inteiros.
      final sem = _avaliar(_insumos());
      final r = _avaliar(
        _insumos(
          emissoes: [
            ShareIssue(
              date: DateTime(2026, 5, 19),
              amount: Money.fromReais(1200),
              shares: 100,
              declared: false,
            ),
          ],
        ),
      );
      expect(r.fairValue.reais, closeTo(sem.fairValue.reais, 1e-9));
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
      final com = _avaliar(_insumos(emissoes: [depois]));
      final base = com.discreteScenarios?[ScenarioBand.base];
      expect(base, isNotNull);
      expect(base!.reais, closeTo(com.fairValue.reais, 0.011));
    });

    test(
      'o rastro mostra o capital do balanço e soma o novo num passo seu',
      () {
        final eventos = <AuditEvent>[];
        AuditRecorder.attach(eventos.add);
        try {
          _avaliar(_insumos(emissoes: [depois]));
        } finally {
          AuditRecorder.detach();
        }
        final ev = eventos.single;
        final passos = [
          for (final t in ev.calculations) ...t.intermediateSteps,
        ];
        expect(passos.any((p) => p.startsWith('Passo 4b')), isTrue);
        expect(ev.inputPayload['shareIssues'], isA<List<Object?>>());
        final diag = ev.outputPayload['diagnostics'] as Map;
        expect(diag['postStatementCapital'], closeTo(1200, 1e-6));
      },
    );
  });

  test('a via do acionista soma o mesmo por papel', () {
    // O banco do teste da Porta 1: lucro de 12% sobre o patrimônio, sem dívida.
    List<FundamentalsSnapshot> banco() {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        final lucro = 0.12 * pl;
        pl += lucro;
        pontos.add(
          FundamentalsSnapshot(
            ticker: _ticker,
            fiscalPeriodEnd: DateTime(ano, 12, 31),
            bookValuePerShare: pl / 1000,
            sharesOutstanding: 1000,
            sharesOutstandingAsOf: 1000,
            netIncome: ano == 2012 ? null : lucro,
            nopat: lucro,
            ebit: lucro * 1.4,
            longTermDebt: 0,
            marketCap: 20000,
          ),
        );
      }
      return pontos;
    }

    ValuationResult avaliar(List<ShareIssue> emissoes) => _avaliar(
      ValuationInputs(
        ticker: _ticker,
        asOf: DateTime(2026, 6, 30),
        fundamentals: banco(),
        marketPrice: 20.0,
        capm: const CapmInputs(
          riskFreeRate: 0.105,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        sectorKey: 'financeiro',
        industry: 'Intermediários Financeiros / Bancos',
        shareIssues: emissoes,
      ),
    );

    final sem = avaliar(const []);
    final com = avaliar([depois]);
    expect(com.model, ValuationModel.dcfEarnings);
    // `VM ÷ P` = 20.000 ÷ 20 = 1.000 papéis.
    expect(
      com.fairValue.reais,
      closeTo(sem.fairValue.reais + 1200 / 1000, 0.011),
    );
    expect(com.diagnostics!.postStatementCapital, closeTo(1200, 1e-9));
  });
}
