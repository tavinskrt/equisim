// Confere se as âncoras macro podem ser resolvidas *point-in-time* para cada
// data de coorte do backtest — e com que janela efetiva.
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main() async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    for (final ano in [2018, 2019, 2020, 2021, 2022, 2023, 2026]) {
      final t = DateTime(ano, 9, 30);
      final cdi = await ctx.macro.riskFreeDaily(
        DateRange(DateTime(ano - 10, 9, 30), t),
      );
      final ipca = await ctx.macro.inflationMonthly(
        DateRange(DateTime(ano - 10, 9, 30), t),
      );
      final a = (await ResolveMarketAnchors.call(
        macro: ctx.macro,
        benchmark: ctx.benchmark,
        asOf: t,
      ))
          .getOrElse(MarketAnchors.fallback2026);
      final n = cdi.isOk ? cdi.unwrap().rates.length : 0;
      final nIpca = ipca.isOk ? ipca.unwrap().rates.length : 0;
      stdout.writeln('$ano  cdi=${n.toString().padLeft(5)} obs  '
          'ipca=${nIpca.toString().padLeft(4)} obs  '
          'rfDecenal=${(a.riskFreeCagr * 100).toStringAsFixed(2)}%  '
          'rfCorrente=${(a.currentRiskFreeRate * 100).toStringAsFixed(2)}%  '
          'ibov=${(a.marketCagr * 100).toStringAsFixed(2)}%  '
          'ipca=${(a.inflationCagr * 100).toStringAsFixed(2)}%');
    }
  } finally {
    await ctx.dispose();
  }
}
