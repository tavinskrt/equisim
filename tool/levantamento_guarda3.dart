// Levantamento: quantos ativos sofrem normalização PARA BAIXO da Guarda 3
// enquanto o lucro cai — a assinatura contaminada em que o retorno sobe porque
// a base encolheu, e não porque o exercício foi bom.
//
// Uso: dart run tool/levantamento_guarda3.dart <arquivo_de_saida.json>
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

Future<void> main(List<String> args) async {
  final saida = args.isNotEmpty ? args.first : 'docs/validacao/guarda3_baseline.json';
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final today = DateTime(2026, 9, 9);

  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro, benchmark: ctx.benchmark, asOf: today,
    )).getOrElse(MarketAnchors.fallback2026);

    final universe = (await ctx.fundamentals.universe()).unwrap();
    stdout.writeln('Universo: ${universe.length} tickers.');

    final linhas = <Map<String, dynamic>>[];
    var n = 0;

    for (final ticker in universe) {
      if (++n % 25 == 0) stdout.write('  $n / ${universe.length}\r');

      final prep = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      );
      if (prep.isErr) {
        linhas.add({'ticker': ticker.value, 'estado': 'sem insumos'});
        continue;
      }
      final inputs = prep.unwrap();

      final r = ValuationCascade.evaluate(inputs);
      if (r.isErr) {
        linhas.add({
          'ticker': ticker.value,
          'estado': 'recusado',
          'motivo': r.failureOrNull?.message,
        });
        continue;
      }
      final res = r.unwrap();
      final via = res.model == ValuationModel.dcfFcff
          ? ValuationLane.firm
          : ValuationLane.shareholder;

      // Série da via efetivamente usada.
      final pub = PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      final s = CapitalSeries.build(pub, via);
      final p = s.points;

      // Direção do lucro e da base que forma o retorno corrente.
      //   retorno_t = lucro_t / base_{t-1}
      double? lucroAtual, lucroAnterior, baseDenom, baseDenomAnterior;
      if (p.length >= 2) {
        lucroAtual = p[p.length - 1].profit;
        lucroAnterior = p[p.length - 2].profit;
        baseDenom = p[p.length - 2].base;
      }
      if (p.length >= 3) baseDenomAnterior = p[p.length - 3].base;

      final fator = res.diagnostics?.baseFactor;

      linhas.add({
        'ticker': ticker.value,
        'estado': 'ok',
        'setor': inputs.sectorKey,
        'industria': inputs.industry,
        'via': via.name,
        'preco': inputs.marketPrice,
        'precoJusto': res.fairValue.reais,
        'potencial': res.upside,
        'fatorBase': fator,
        'retornoAtual': s.latestReturn,
        'retornoCiclo': s.cycleReturn(window: ValuationParameters.cycleWindow),
        'quedaTrienio': GrowthGuards.recentOperationalDecline(pub),
        'lucroAtual': lucroAtual,
        'lucroAnterior': lucroAnterior,
        'baseDenominador': baseDenom,
        'baseDenominadorAnterior': baseDenomAnterior,
        'exercicios': p.length,
      });
    }

    stdout.writeln('');
    File(saida).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(linhas));
    stdout.writeln('Gravado: $saida (${linhas.length} linhas)');
  } finally {
    await ctx.dispose();
  }
}
