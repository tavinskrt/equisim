// A cópia de `ValuationInputs` preserva todo campo (item B27).
//
// Cada cópia repetia a lista de campos à mão, e três campos novos se perderam
// em todas: `withProjectionYears` — que a concessão que acaba dentro da
// projeção usa em produção — deixava a concessionária sem a segunda leitura por
// múltiplos. **Ao acrescentar um campo a `ValuationInputs`, acrescente-o aqui**:
// o teste preenche todos com valores fora do padrão e confere cada um.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('ABCD3');

final _snap = FundamentalsSnapshot(
  ticker: _t,
  fiscalPeriodEnd: DateTime(2025, 12, 31),
  netIncome: 100,
);
final _curva = YieldCurve.of(DateTime(2026, 9, 1), const [
  CurveVertex(1, 0.14),
  CurveVertex(5, 0.135),
  CurveVertex(10, 0.13),
])!;
final _precos = PriceSeries(ticker: _t, points: [
  PricePoint(date: DateTime(2026, 9, 1), close: 10, volume: 100),
]);
final _pares = PeerMultipleSet(byKind: const {
  MultipleKind.precoLucro: PeerMultiple(median: 9, peers: 5, group: 'g'),
}, asOf: DateTime(2026, 9, 1));
final _oficial = OfficialShareCount(total: 1000, asOf: DateTime(2026, 9, 1));
const _capm = CapmInputs(riskFreeRate: 0.14, beta: 1.2, marketPremium: 0.06);

/// Todo campo preenchido, e nenhum com o valor padrão.
final _completo = ValuationInputs(
  ticker: _t,
  asOf: DateTime(2026, 9, 9),
  fundamentals: [_snap],
  marketPrice: 12,
  capm: _capm,
  marginOfSafety: 0.2,
  projectionYears: 12,
  perpetualGrowthCap: 0.07,
  sectorKey: 'energia',
  industry: 'transmissão',
  inflation: 0.045,
  declaredTerminalRiskFreeRate: 0.095,
  riskFreeCurve: _curva,
  officialShares: _oficial,
  prices: _precos,
  isDistressed: true,
  terminalReturnOverride: 0.13,
  laneOverride: ValuationLane.shareholder,
  growthOverride: 0.06,
  baseFactorOverride: 1.1,
  unleveredBeta: 0.8,
  reinvestmentOverride: ReinvestmentPolicy.crescimentoReal,
  cashTimingOverride: CashTiming.fimDeAno,
  concessionEnd: DateTime(2030, 1, 1),
  dividendsInBeta: 7,
  creditReferenceRiskFree: 0.15,
  declaredSharesPerUnit: 5,
  terminalBetaWeightOverride: 0.5,
  terminalLeverageOverride: 0.4,
  betaWindowYears: 3.5,
  peerMultiples: _pares,
  minorityEquityValue: 321,
  scenarioTranslation: ScenarioTranslation.estruturaFixa,
  contextNotes: const ['nota'],
);

/// Os campos, por nome — para comparar e para dizer qual se perdeu.
Map<String, Object?> _campos(ValuationInputs i) => {
      'ticker': i.ticker,
      'asOf': i.asOf,
      'fundamentals': i.fundamentals,
      'marketPrice': i.marketPrice,
      'capm': i.capm,
      'marginOfSafety': i.marginOfSafety,
      'projectionYears': i.projectionYears,
      'perpetualGrowthCap': i.perpetualGrowthCap,
      'sectorKey': i.sectorKey,
      'industry': i.industry,
      'inflation': i.inflation,
      'declaredTerminalRiskFreeRate': i.declaredTerminalRiskFreeRate,
      'riskFreeCurve': i.riskFreeCurve,
      'officialShares': i.officialShares,
      'prices': i.prices,
      'isDistressed': i.isDistressed,
      'terminalReturnOverride': i.terminalReturnOverride,
      'laneOverride': i.laneOverride,
      'growthOverride': i.growthOverride,
      'baseFactorOverride': i.baseFactorOverride,
      'unleveredBeta': i.unleveredBeta,
      'reinvestmentOverride': i.reinvestmentOverride,
      'cashTimingOverride': i.cashTimingOverride,
      'concessionEnd': i.concessionEnd,
      'dividendsInBeta': i.dividendsInBeta,
      'creditReferenceRiskFree': i.creditReferenceRiskFree,
      'declaredSharesPerUnit': i.declaredSharesPerUnit,
      'terminalBetaWeightOverride': i.terminalBetaWeightOverride,
      'terminalLeverageOverride': i.terminalLeverageOverride,
      'betaWindowYears': i.betaWindowYears,
      'peerMultiples': i.peerMultiples,
      'minorityEquityValue': i.minorityEquityValue,
      'scenarioTranslation': i.scenarioTranslation,
      'contextNotes': i.contextNotes,
    };

void _preserva(ValuationInputs copia, {Set<String> exceto = const {}}) {
  final a = _campos(_completo), b = _campos(copia);
  for (final k in a.keys) {
    if (exceto.contains(k)) continue;
    expect(b[k], equals(a[k]), reason: 'a cópia perdeu `$k`');
  }
}

void main() {
  test('nenhum campo do teste está no valor padrão', () {
    // Se um campo ficasse no padrão, a cópia que o perdesse passaria igual.
    final padrao = ValuationInputs(
      ticker: _t,
      asOf: DateTime(2026, 9, 9),
      fundamentals: const [],
      marketPrice: 12,
      capm: _capm,
    );
    final a = _campos(_completo), p = _campos(padrao);
    for (final k in a.keys) {
      if (const {'ticker', 'asOf', 'marketPrice', 'capm'}.contains(k)) continue;
      expect(a[k], isNot(equals(p[k])), reason: '`$k` está no padrão');
    }
  });

  test('withProjectionYears preserva todo campo — a concessão em produção', () {
    final c = _completo.withProjectionYears(4);
    expect(c.projectionYears, 4);
    _preserva(c, exceto: {'projectionYears'});
  });

  test('withFundamentals troca só a série', () {
    final nova = [_snap, _snap];
    final c = _completo.withFundamentals(nova);
    expect(c.fundamentals, same(nova));
    _preserva(c, exceto: {'fundamentals'});
  });

  test('withoutPrices tira só a série de cotações', () {
    final c = _completo.withoutPrices();
    expect(c.prices, isNull);
    _preserva(c, exceto: {'prices'});
  });

  test('withPeerMultiples troca só os pares', () {
    final c = _completo.withPeerMultiples(null);
    expect(c.peerMultiples, isNull);
    _preserva(c, exceto: {'peerMultiples'});
  });

  test('withContextNotes troca só as ressalvas', () {
    final c = _completo.withContextNotes(const ['a', 'b']);
    expect(c.contextNotes, ['a', 'b']);
    _preserva(c, exceto: {'contextNotes'});
  });

  test('withOverrides troca só as seis imposições', () {
    final c = _completo.withOverrides(lane: ValuationLane.firm);
    expect(c.laneOverride, ValuationLane.firm);
    expect(c.terminalReturnOverride, isNull);
    expect(c.cashTimingOverride, isNull);
    _preserva(c, exceto: {
      'laneOverride',
      'terminalReturnOverride',
      'growthOverride',
      'baseFactorOverride',
      'reinvestmentOverride',
      'cashTimingOverride',
    });
  });

  test('withRiskFreeShift desloca as taxas e preserva o resto', () {
    final c = _completo.withRiskFreeShift(0.01);
    expect(c.capm.riskFreeRate, closeTo(0.15, 1e-12));
    expect(c.declaredTerminalRiskFreeRate, closeTo(0.105, 1e-12));
    expect(c.riskFreeCurve!.vertices.first.rate, closeTo(0.15, 1e-12));
    _preserva(c, exceto: {
      'capm',
      'declaredTerminalRiskFreeRate',
      'riskFreeCurve',
    });
  });
}
