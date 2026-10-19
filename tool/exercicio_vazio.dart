// O exercício que a fonte publica sem demonstração de resultado.
//
// **O caso que abriu a pergunta.** A TIMS3 é recusada por "os dados não
// sustentam nenhuma das duas vias". O exercício que o motor usou como base tem
// `ebit = 0`, `nopat = 0`, `lpa = 0` e `receita = 0` — com patrimônio líquido
// de R$ 24 bilhões no mesmo balanço. Ela teve EBIT de R$ 4,7 bi em 2023.
//
// Uma empresa com R$ 24 bi de patrimônio não tem receita zero. O exercício
// existe na fonte e a demonstração de resultado dele **não foi publicada** — e
// o motor lê o vazio como o número zero.
//
// **O que isto mede.** Quantos exercícios são assim, onde eles caem na série, e
// o que acontece com o ativo por causa disso.
//
// Uso:
//   dart run tool/exercicio_vazio.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

/// `true` quando o exercício não traz resultado algum.
///
/// Os quatro juntos: receita, resultado operacional, lucro líquido e lucro por
/// ação. Zerar **um** deles é possível — holding sem receita, empresa no
/// zero a zero. Zerar os quatro, não.
bool _withoutResult(FundamentalsSnapshot s) {
  bool isEmptyValue(double? v) => v == null || v == 0;
  return isEmptyValue(s.totalRevenue) &&
      isEmptyValue(s.ebit) &&
      isEmptyValue(s.netIncome) &&
      isEmptyValue(s.earningsPerShare);
}

/// `true` quando o balanço do mesmo exercício tem conteúdo.
///
/// É o que separa "a empresa não existia" de "a demonstração de resultado não
/// veio": o exercício está lá, com patrimônio e ativo, e só o resultado falta.
bool _withBalanceSheet(FundamentalsSnapshot s) {
  final pl = s.totalStockholderEquity;
  final fixedAssets = s.propertyPlantEquipment;
  final asset = s.totalCurrentAssets;
  return (pl != null && pl != 0) ||
      (fixedAssets != null && fixedAssets != 0) ||
      (asset != null && asset != 0);
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

    final output = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final series = await ctx.fundamentals.history(ticker);
      if (series.isErr) continue;
      final pub = PointInTimeView(_today).published(series.unwrap());
      if (pub.isEmpty) continue;

      final emptyCount = [
        for (final s in pub)
          if (_withoutResult(s)) s
      ];
      if (emptyCount.isEmpty) continue;

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
      String? refusal;
      double? fairValue;
      if (prep.isErr) {
        refusal = 'insumo: ${prep.failureOrNull?.message}';
      } else {
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (r.isErr) {
          refusal = r.failureOrNull!.message;
        } else {
          fairValue = r.unwrap().fairValue.reais;
        }
      }

      output.add({
        'ticker': ticker.value,
        'exercicios': pub.length,
        'vazios': emptyCount.length,
        'anosVazios': [for (final s in emptyCount) s.fiscalPeriodEnd.year],
        'ultimoVazio': _withoutResult(pub.last),
        'comBalanco': emptyCount.where(_withBalanceSheet).length,
        'justo': fairValue,
        'recusa': refusal,
      });
    }
    stderr.writeln('');

    File('docs/validacao/exercicio_vazio.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output, universe.length);
    stderr.writeln('\nescrito docs/validacao/exercicio_vazio.json '
        '(${output.length})');
  } finally {
    await ctx.dispose();
  }
}

void _printReport(List<Map<String, dynamic>> l, int universe) {
  stdout.writeln('\n=== EXERCÍCIO SEM DEMONSTRAÇÃO DE RESULTADO ===\n');
  stdout.writeln('  ativos com ao menos um: ${l.length} de $universe');
  final withBalanceSheet =
      l.where((e) => (e['comBalanco'] as int) > 0).length;
  stdout.writeln('  destes, com balanço preenchido no mesmo exercício: '
      '$withBalanceSheet');
  final inLast = l.where((e) => e['ultimoVazio'] == true).toList();
  stdout.writeln('  **com o exercício-base vazio: ${inLast.length}**');
  final refusedCount = l.where((e) => e['recusa'] != null).length;
  stdout.writeln('  recusados pelo motor: $refusedCount');

  final totalEmpty = l.fold<int>(0, (a, e) => a + (e['vazios'] as int));
  final totalFiscalYears = l.fold<int>(0, (a, e) => a + (e['exercicios'] as int));
  stdout.writeln('  exercícios vazios: $totalEmpty de $totalFiscalYears '
      'publicados nesses ativos');

  if (inLast.isNotEmpty) {
    stdout.writeln('\n-- os que têm o exercício-base vazio --');
    for (final e in inLast) {
      stdout.writeln('  ${(e['ticker'] as String).padRight(7)} '
          'vazios=${e['vazios']}/${e['exercicios']}  '
          'anos=${e['anosVazios']}  '
          '${e['recusa'] != null ? "RECUSADO" : "justo=${e['justo']}"}');
    }
  }

  final inMiddle = l.where((e) => e['ultimoVazio'] != true).toList();
  if (inMiddle.isNotEmpty) {
    stdout.writeln('\n-- vazio no meio da série (envenena crescimento e '
        'retorno, não a base) --');
    for (final e in inMiddle.take(20)) {
      stdout.writeln('  ${(e['ticker'] as String).padRight(7)} '
          'vazios=${e['vazios']}/${e['exercicios']}  anos=${e['anosVazios']}  '
          '${e['recusa'] != null ? "RECUSADO" : "justo=${e['justo']}"}');
    }
    if (inMiddle.length > 20) stdout.writeln('  … e mais ${inMiddle.length - 20}');
  }
}
