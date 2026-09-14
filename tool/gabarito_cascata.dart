// D1 — gabarito da cascata: a condição para quebrar `_evaluateLane`.
//
// `_evaluateLane` tem 1.087 linhas e nove estágios. Quebrá-lo em pedaços é
// refatoração pura: **nenhum número pode mudar**. A cascata é determinística —
// é regra do núcleo —, então isso é verificável ao bit: este gabarito grava a
// saída completa do universo, e o modo `--conferir` refaz e compara.
//
// Duas montagens por ativo, para cobrir os dois caminhos da taxa livre de
// risco: a interpolação de dois pontos e a curva observada (decisão 74).
//
// **O gabarito congela a saída, e não a entrada.** O cache da validação expira
// e o Ibovespa vem da rede sem cache, então a comparação só vale na mesma
// sessão de dados: grave imediatamente antes da refatoração, confira primeiro
// o código intacto — divergência ali é dado, não refatoração — e grave de novo
// se a série de passos atravessar dias.
//
// Uso:
//   dart run tool/gabarito_cascata.dart             # grava o gabarito
//   dart run tool/gabarito_cascata.dart --conferir  # compara com o gravado
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'curva_ligar.dart' show lerTesouro;
import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);
const _arquivo = 'docs/validacao/gabarito_cascata.json';

/// Tudo o que o resultado expõe. `double.toString()` é a representação mais
/// curta que volta ao mesmo bit — é o que torna a comparação exata.
Map<String, Object?> _serializar(Result<ValuationResult> r) {
  if (r.isErr) return {'recusa': r.failureOrNull!.message};
  final v = r.unwrap();
  final d = v.diagnostics;
  return {
    'modelo': v.model.name,
    'justoCentavos': v.fairValue.cents,
    'precoCentavos': v.marketPrice.cents,
    'potencial': v.upside.toString(),
    'desconto': v.discountRate.toString(),
    'modo': v.mode.name,
    'cenarios': v.discreteScenarios == null
        ? null
        : {for (final e in v.discreteScenarios!.entries) e.key.name: e.value.cents},
    'avisos': v.warnings,
    if (d != null)
      'diagnostico': {
        'pesoTerminal': d.terminalShare.toString(),
        'pesoEquity': d.equityShare.toString(),
        'fatorBase': d.baseFactor.toString(),
        'crescimentoIdentificado': d.growthIdentified,
        'moat': d.moatApplied,
        'spreadRetido': d.terminalRetainedSpread.toString(),
        'crescimento': d.growthRate.toString(),
        'retornoTerminal': d.terminalReturnOnCapital?.toString(),
        'aliquota': d.firmTaxRate?.toString(),
        'retorno': d.returnOnCapital.toString(),
        'descontoTerminal': d.terminalDiscountRate.toString(),
        'keTerminal': d.terminalCostOfEquity?.toString(),
        'ke': d.costOfEquity.toString(),
        'caminhoCrescimento': [for (final x in d.growthPath) x.toString()],
        'caminhoRetencao': [for (final x in d.retentionPath) x.toString()],
        'ressalvas': [for (final c in d.caveats) c.name],
      },
  };
}

Future<void> main(List<String> args) async {
  final conferir = args.contains('--conferir');
  final curva = TreasuryCurve.at(
      lerTesouro('data/tesouro/precotaxatesourodireto.csv'), _hoje);

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();

    final saida = <String, Object?>{};
    var i = 0;
    for (final t in universe) {
      if (++i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      Future<Object?> montagem(YieldCurve? c) async {
        final prep = await PrepareValuationInputs.call(
          ticker: t,
          prices: ctx.prices,
          fundamentals: ctx.fundamentals,
          benchmark: ctx.benchmark,
          riskFreeRate: anchors.currentRiskFreeRate,
          asOf: _hoje,
          perpetualGrowthCap: anchors.nominalEconomyGrowth,
          inflation: anchors.inflationCagr,
          terminalRiskFreeRate: anchors.riskFreeCagr,
          riskFreeCurve: c,
          projectionYears: 10,
        );
        if (prep.isErr) return {'preparo': prep.failureOrNull!.message};
        return _serializar(ValuationCascade.evaluate(prep.unwrap()));
      }

      saida[t.value] = {
        'doisPontos': await montagem(null),
        'curva': curva == null ? null : await montagem(curva),
      };
    }
    stderr.writeln('');
    final texto = const JsonEncoder.withIndent(' ').convert(saida);

    if (!conferir) {
      File(_arquivo).writeAsStringSync(texto);
      stdout.writeln('gabarito gravado: ${saida.length} ativos em $_arquivo');
      return;
    }

    final gravado = jsonDecode(File(_arquivo).readAsStringSync())
        as Map<String, dynamic>;
    final agora = jsonDecode(texto) as Map<String, dynamic>;
    final divergentes = <String>[
      for (final k in {...gravado.keys, ...agora.keys})
        if (jsonEncode(gravado[k]) != jsonEncode(agora[k])) k,
    ]..sort();
    if (divergentes.isEmpty) {
      stdout.writeln('GABARITO IDÊNTICO: ${agora.length} ativos, '
          'duas montagens cada, saída completa bit a bit.');
    } else {
      stdout.writeln('GABARITO DIVERGE em ${divergentes.length} ativo(s):');
      for (final k in divergentes.take(20)) {
        stdout.writeln('  $k');
      }
      exitCode = 1;
    }
  } finally {
    await ctx.dispose();
  }
}
