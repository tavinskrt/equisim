// Por que o lucro de partida foi normalizado, e em que direção (pedido do
// orientador, 14/10/2026).
//
// O registro `BaseNormalization` explica a Saída 1 da Porta 2 com os valores
// que a cascata usou. Estes testes travam duas coisas: que ele concorda com o
// fator que entrou no preço justo, e que a direção dita é a que aconteceu.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ticker = Ticker.parse('ABCD3');

/// Companhia operacional de retorno estável, com o último exercício
/// multiplicado por [choque] no resultado operacional.
List<FundamentalsSnapshot> _serie({double choque = 1.0}) {
  final out = <FundamentalsSnapshot>[];
  var e = 1.0;
  for (var i = 12; i >= 0; i--) {
    final y = 2025 - i;
    // Os anos do ciclo oscilam 6% para cada lado, como resultado operacional
    // de verdade: sem dispersão, qualquer desvio do último ano seria raro, e o
    // teste mediria a guarda da tendência no lugar da normalização.
    final k = i == 0 ? choque : (i.isEven ? 1.06 : 0.94);
    out.add(FundamentalsSnapshot(
      ticker: _ticker,
      fiscalPeriodEnd: DateTime(y, 12, 31),
      totalRevenue: 10000 * e,
      ebit: 1800 * e * k,
      // EBITDA e lucro líquido estáveis: a trava de saúde mede a queda deles,
      // e o teste é da normalização, e não da trava.
      ebitda: 2400 * e,
      netIncome: 900 * e,
      incomeBeforeTax: 1300 * e,
      incomeTaxExpense: -400 * e,
      interestExpense: 400,
      earningsPerShare: 0.9 * e,
      cash: 200,
      shortTermDebt: 1000,
      longTermDebt: 3000,
      totalStockholderEquity: 6000 * e,
      bookValuePerShare: 6.0 * e,
      operatingCashFlow: 2000 * e,
      nopat: 1188 * e * k,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    ));
    e *= i.isEven ? 1.04 : 1.06;
  }
  return out;
}

({ValuationResult r, CalculationTrace passo}) _avaliar({double choque = 1.0}) {
  CalculationTrace? passo;
  AuditRecorder.attach((evento) {
    passo = evento.calculations.firstWhere(
      (c) => c.formulaName.startsWith('Base do fluxo'),
    );
  });
  try {
    final r = ValuationCascade.evaluate(ValuationInputs(
      ticker: _ticker,
      asOf: DateTime(2026, 9, 9),
      fundamentals: _serie(choque: choque),
      marketPrice: 12.0,
      capm: const CapmInputs(
        riskFreeRate: 0.14,
        beta: 1.0,
        marketPremium: 0.055,
      ),
      declaredTerminalRiskFreeRate: 0.10,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
    return (r: r.unwrap(), passo: passo!);
  } finally {
    AuditRecorder.detach();
  }
}

double _mediana(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

void main() {
  group('o resultado, pela ordem em que a cascata decide', () {
    BaseNormalization n({
      double? atual = 0.10,
      double? ciclo = 0.14,
      bool destoa = true,
      bool tendencia = false,
      bool ciclico = false,
      bool saude = false,
      double fator = 1.4,
      bool reconstruida = false,
      bool imposta = false,
    }) =>
        BaseNormalization(
          lane: ValuationLane.firm,
          latestReturn: atual,
          cycleReturn: ciclo,
          deviates: destoa,
          trendDominates: tendencia,
          cyclicalPrecedence: ciclico,
          healthCapped: saude,
          factor: fator,
          rebuilt: reconstruida,
          imposed: imposta,
        );

    test('abaixo do típico e destoando, sobe', () {
      expect(n().outcome, BaseNormalizationOutcome.paraCima);
    });

    test('acima do típico e destoando, desce', () {
      expect(n(atual: 0.20, fator: 0.7).outcome,
          BaseNormalizationOutcome.paraBaixo);
    });

    test('sem destoar, fica no publicado — mesmo com tendência', () {
      expect(n(destoa: false, fator: 1, tendencia: true).outcome,
          BaseNormalizationOutcome.dentroDoNormal);
    });

    test('destoando com tendência, fica no publicado; em commodity, não', () {
      expect(n(tendencia: true, fator: 1).outcome,
          BaseNormalizationOutcome.tendencia);
      expect(n(tendencia: true, ciclico: true).outcome,
          BaseNormalizationOutcome.paraCima);
    });

    test('a trava de saúde segura a subida', () {
      expect(n(saude: true, fator: 1).outcome,
          BaseNormalizationOutcome.travadaPelaSaude);
    });

    test('prejuízo reconstruído, e sem ciclo positivo', () {
      expect(n(atual: -0.05, reconstruida: true, fator: 1).outcome,
          BaseNormalizationOutcome.reconstruida);
      expect(n(ciclo: null, fator: 1).outcome,
          BaseNormalizationOutcome.semCiclo);
      expect(n(ciclo: -0.02, fator: 1).outcome,
          BaseNormalizationOutcome.semCiclo);
    });

    test('o fator imposto vem antes de tudo', () {
      expect(n(imposta: true).outcome, BaseNormalizationOutcome.imposta);
    });
  });

  group('pela cascata: o registro concorda com o preço justo', () {
    for (final (nome, choque, esperado) in [
      ('último ano deprimido', 0.6, BaseNormalizationOutcome.paraCima),
      ('último ano de pico', 1.6, BaseNormalizationOutcome.paraBaixo),
      ('último ano normal', 1.0, BaseNormalizationOutcome.dentroDoNormal),
    ]) {
      test(nome, () {
        final (:r, :passo) = _avaliar(choque: choque);
        final n = r.diagnostics!.baseNormalization!;
        expect(n.outcome, esperado);
        // O fator explicado é o fator que entrou no preço.
        expect(n.factor, r.diagnostics!.baseFactor);
        // O típico é a mediana dos oito anteriores ao último.
        expect(n.cycleWindow, hasLength(8));
        expect(n.latestYear, 2025);
        expect(n.cycleWindow.last.year, 2024);
        expect(
          n.cycleReturn,
          closeTo(_mediana([for (final p in n.cycleWindow) p.value]), 1e-12),
        );
        expect(n.ratio, closeTo(n.latestReturn! / n.cycleReturn!, 1e-12));
        // O lucro de partida é o publicado vezes o fator.
        expect(
          n.baseProfit,
          closeTo(n.publishedProfit! * n.factor, 1e-6),
        );
        // A direção dita é a que aconteceu.
        switch (esperado) {
          case BaseNormalizationOutcome.paraCima:
            expect(n.factor, greaterThan(1));
            expect(n.latestReturn, lessThan(n.cycleReturn!));
          case BaseNormalizationOutcome.paraBaixo:
            expect(n.factor, lessThan(1));
            expect(n.latestReturn, greaterThan(n.cycleReturn!));
          default:
            expect(n.factor, 1.0);
        }
        // O rastro explica com os mesmos números.
        expect(passo.explanation, isNotEmpty);
        expect(passo.explanation.first, startsWith('Por que normalizar'));
        expect(
          passo.mappedVariables['resultado da normalização'],
          esperado.name,
        );
      });
    }

    test('o rastro diz a direção e a conta', () {
      final cima = _avaliar(choque: 0.6).passo.explanation;
      expect(cima[1], startsWith('Para cima: em 2025'));
      expect(cima.any((l) => l.startsWith('O teste de destoar')), isTrue);
      expect(cima.any((l) => l.startsWith('A conta:')), isTrue);
      final baixo = _avaliar(choque: 1.6).passo.explanation;
      expect(baixo[1], startsWith('Para baixo: em 2025'));
      final normal = _avaliar().passo.explanation;
      expect(normal[1], startsWith('Sem normalização'));
      expect(normal.last, endsWith('Não destoou.'));
    });

    test('o aviso diz a direção', () {
      final r = _avaliar(choque: 0.6).r;
      expect(
        r.warnings.any((w) => w.contains('normalizada para cima')),
        isTrue,
      );
      expect(
        r.warnings.any((w) => w.contains('ao longo da projeção')),
        isFalse,
        reason: 'o fator vale já no ano zero; o que converge é o retorno',
      );
    });

    test('prejuízo no último ano: a base é reconstruída do ciclo', () {
      final (:r, :passo) = _avaliar(choque: -0.2);
      final n = r.diagnostics!.baseNormalization!;
      expect(n.outcome, BaseNormalizationOutcome.reconstruida);
      expect(r.caveats, contains(ValuationCaveat.baseReconstruida));
      expect(n.rebuiltPositiveShare, greaterThanOrEqualTo(0.6));
      expect(passo.explanation[1], startsWith('Base reconstruída'));
    });
  });
}
