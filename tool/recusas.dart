// Por que o motor recusa o que recusa.
//
// A cobertura não é critério — a decisão 45 diz isso —, mas a **composição**
// das recusas é diagnóstico: um motivo que domina a lista é ou uma guarda
// necessária ou um defeito escondido atrás dela.
//
// Uso:
//   dart run tool/recusas.dart
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

/// Agrupa a mensagem de recusa numa família estável.
String _family(String m) {
  if (m.contains('Lucro operacional base não positivo')) {
    return 'lucro operacional base não positivo';
  }
  if (m.contains('Lucro base não positivo')) return 'lucro base não positivo';
  if (m.contains('não sustenta a via da firma')) {
    return 'estrutura de capital recusada';
  }
  if (m.contains('capital próprio responde por apenas')) {
    return 'ponte frágil e via do acionista inaplicável';
  }
  if (m.contains('Preço de mercado')) return 'sem preço de mercado';
  if (m.contains('não sustentam nenhuma das duas vias')) {
    return 'nenhuma via aplicável';
  }
  if (m.contains('exercício')) return 'exercícios insuficientes';
  return m.length > 60 ? '${m.substring(0, 60)}…' : m;
}

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final prior = await ResolveBetaPrior.call(
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: _today,
    );

    final byFamily = <String, List<String>>{};
    var evaluated = 0;
    var withoutInput = 0;
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final prep = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
        betaPrior: prior,
      );
      if (prep.isErr) {
        withoutInput++;
        continue;
      }
      final r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isOk) {
        evaluated++;
        continue;
      }
      final f = _family(r.failureOrNull!.message);
      (byFamily[f] ??= []).add(ticker.value);
    }
    stderr.writeln('');

    stdout.writeln('\n=== POR QUE O MOTOR RECUSA — ${universe.length} do '
        'universo ===\n');
    stdout.writeln('  avaliados:            $evaluated');
    stdout.writeln('  sem insumo suficiente: $withoutInput');
    final total = byFamily.values.fold(0, (a, b) => a + b.length);
    stdout.writeln('  recusados na cascata:  $total\n');
    final keys = byFamily.keys.toList()
      ..sort((a, b) => byFamily[b]!.length.compareTo(byFamily[a]!.length));
    for (final k in keys) {
      final xs = byFamily[k]!;
      stdout.writeln('  ${xs.length.toString().padLeft(4)}  $k');
      stdout.writeln('        ${xs.take(10).join(', ')}'
          '${xs.length > 10 ? ', …' : ''}');
    }
  } finally {
    await ctx.dispose();
  }
}
