import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main() async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final a = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: DateTime(2026, 9, 4),
    )).getOrElse(MarketAnchors.fallback2026);
    stdout.writeln('CDI decenal      ${(a.riskFreeCagr * 100).toStringAsFixed(2)}%');
    stdout.writeln('CDI corrente     ${(a.currentRiskFreeRate * 100).toStringAsFixed(2)}%');
    stdout.writeln('Ibovespa decenal ${(a.marketCagr * 100).toStringAsFixed(2)}%');
    stdout.writeln('premio medido    ${((a.marketCagr - a.riskFreeCagr) * 100).toStringAsFixed(2)} p.p.');
    stdout.writeln('premio usado     ${(CapmInputs.defaultMarketPremium * 100).toStringAsFixed(2)} p.p.');
    stdout.writeln('IPCA             ${(a.inflationCagr * 100).toStringAsFixed(2)}%');
    stdout.writeln('janela           ${a.observedYears} anos');
  } finally {
    await ctx.dispose();
  }
}
