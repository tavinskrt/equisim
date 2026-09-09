// Varre a taxa livre de risco e observa se o preço justo é monótono nela.
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main(List<String> args) async {
  final alvo = args.isNotEmpty ? args.first : 'KLBN11';
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime.utc(2026, 9, 9);
  try {
    final a = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: today,
    )).getOrElse(MarketAnchors.fallback2026);
    final i = (await PrepareValuationInputs.call(
      ticker: Ticker.parse(alvo), prices: ctx.prices,
      fundamentals: ctx.fundamentals, benchmark: ctx.benchmark,
      riskFreeRate: a.currentRiskFreeRate, asOf: today,
      perpetualGrowthCap: a.nominalEconomyGrowth, inflation: a.inflationCagr,
      terminalRiskFreeRate: a.riskFreeCagr, projectionYears: 10)).unwrap();

    print('$alvo — varredura da taxa livre de risco corrente '
        '(beta ${i.capm.beta.toStringAsFixed(3)}, premio ${(i.capm.marketPremium*100).toStringAsFixed(2)}%)');
    print('  Rf      Ke        justo    potencial   via         quebra');
    double? ant;
    for (var rf = 0.1600; rf >= 0.0849; rf -= 0.0025) {
      final capm = CapmInputs(
          riskFreeRate: rf, beta: i.capm.beta,
          marketPremium: i.capm.marketPremium);
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: i.ticker, asOf: i.asOf, fundamentals: i.fundamentals,
        marketPrice: i.marketPrice, capm: capm, projectionYears: 10,
        perpetualGrowthCap: i.perpetualGrowthCap, sectorKey: i.sectorKey,
        industry: i.industry, inflation: i.inflation,
        declaredTerminalRiskFreeRate: i.declaredTerminalRiskFreeRate,
        prices: i.prices, isDistressed: i.isDistressed));
      if (r.isErr) { print('${(rf*100).toStringAsFixed(2).padLeft(6)}%  RECUSADO'); continue; }
      final v = r.unwrap();
      final jv = v.fairValue.reais;
      // Descer a taxa deve SUBIR o preço justo. Cair é quebra de monotonia.
      final quebra = (ant != null && jv < ant - 0.005) ? '  <<< CAI ao baratear o capital' : '';
      print('${(rf*100).toStringAsFixed(2).padLeft(6)}%  '
          '${(capm.costOfEquity*100).toStringAsFixed(2).padLeft(6)}%  '
          'R\$ ${jv.toStringAsFixed(2).padLeft(6)}  '
          '${(v.upside*100).toStringAsFixed(1).padLeft(7)}%   '
          '${v.model == ValuationModel.dcfFcff ? 'firma    ' : 'acionista'}$quebra');
      ant = jv;
    }
  } finally { await ctx.dispose(); }
}
