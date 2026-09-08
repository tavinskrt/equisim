import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main() async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final a = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: DateTime(2026, 9, 4),
    )).getOrElse(MarketAnchors.fallback2026);
    // ignore: avoid_print
    print('CDI decenal      ${(a.riskFreeCagr * 100).toStringAsFixed(2)}%');
    // ignore: avoid_print
    print('CDI corrente     ${(a.currentRiskFreeRate * 100).toStringAsFixed(2)}%');
    // ignore: avoid_print
    print('Ibovespa decenal ${(a.marketCagr * 100).toStringAsFixed(2)}%');
    // ignore: avoid_print
    print('premio medido    ${((a.marketCagr - a.riskFreeCagr) * 100).toStringAsFixed(2)} p.p.');
    // ignore: avoid_print
    print('premio usado     ${(CapmInputs.defaultMarketPremium * 100).toStringAsFixed(2)} p.p.');
    // ignore: avoid_print
    print('IPCA             ${(a.inflationCagr * 100).toStringAsFixed(2)}%');
    // ignore: avoid_print
    print('janela           ${a.observedYears} anos');
  } finally {
    await ctx.dispose();
  }
}
