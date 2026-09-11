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

final _hoje = DateTime(2026, 9, 4);

/// `true` quando o exercício não traz resultado algum.
///
/// Os quatro juntos: receita, resultado operacional, lucro líquido e lucro por
/// ação. Zerar **um** deles é possível — holding sem receita, empresa no
/// zero a zero. Zerar os quatro, não.
bool _semResultado(FundamentalsSnapshot s) {
  bool vazio(double? v) => v == null || v == 0;
  return vazio(s.totalRevenue) &&
      vazio(s.ebit) &&
      vazio(s.netIncome) &&
      vazio(s.earningsPerShare);
}

/// `true` quando o balanço do mesmo exercício tem conteúdo.
///
/// É o que separa "a empresa não existia" de "a demonstração de resultado não
/// veio": o exercício está lá, com patrimônio e ativo, e só o resultado falta.
bool _comBalanco(FundamentalsSnapshot s) {
  final pl = s.totalStockholderEquity;
  final imob = s.propertyPlantEquipment;
  final ativo = s.totalCurrentAssets;
  return (pl != null && pl != 0) ||
      (imob != null && imob != 0) ||
      (ativo != null && ativo != 0);
}

Future<void> main(List<String> args) async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final prior = await ResolveBetaPrior.call(
      tickers: universe,
      prices: ctx.prices,
      fundamentals: ctx.fundamentals,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    );

    final saida = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final serie = await ctx.fundamentals.history(ticker);
      if (serie.isErr) continue;
      final pub = PointInTimeView(_hoje).published(serie.unwrap());
      if (pub.isEmpty) continue;

      final vazios = [
        for (final s in pub)
          if (_semResultado(s)) s
      ];
      if (vazios.isEmpty) continue;

      final prep = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _hoje,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
        betaPrior: prior,
      );
      String? recusa;
      double? justo;
      if (prep.isErr) {
        recusa = 'insumo: ${prep.failureOrNull?.message}';
      } else {
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (r.isErr) {
          recusa = r.failureOrNull!.message;
        } else {
          justo = r.unwrap().fairValue.reais;
        }
      }

      saida.add({
        'ticker': ticker.value,
        'exercicios': pub.length,
        'vazios': vazios.length,
        'anosVazios': [for (final s in vazios) s.fiscalPeriodEnd.year],
        'ultimoVazio': _semResultado(pub.last),
        'comBalanco': vazios.where(_comBalanco).length,
        'justo': justo,
        'recusa': recusa,
      });
    }
    stderr.writeln('');

    File('docs/validacao/exercicio_vazio.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida, universe.length);
    stderr.writeln('\nescrito docs/validacao/exercicio_vazio.json '
        '(${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l, int universo) {
  stdout.writeln('\n=== EXERCÍCIO SEM DEMONSTRAÇÃO DE RESULTADO ===\n');
  stdout.writeln('  ativos com ao menos um: ${l.length} de $universo');
  final comBalanco =
      l.where((e) => (e['comBalanco'] as int) > 0).length;
  stdout.writeln('  destes, com balanço preenchido no mesmo exercício: '
      '$comBalanco');
  final noUltimo = l.where((e) => e['ultimoVazio'] == true).toList();
  stdout.writeln('  **com o exercício-base vazio: ${noUltimo.length}**');
  final recusados = l.where((e) => e['recusa'] != null).length;
  stdout.writeln('  recusados pelo motor: $recusados');

  final totalVazios = l.fold<int>(0, (a, e) => a + (e['vazios'] as int));
  final totalExercicios = l.fold<int>(0, (a, e) => a + (e['exercicios'] as int));
  stdout.writeln('  exercícios vazios: $totalVazios de $totalExercicios '
      'publicados nesses ativos');

  if (noUltimo.isNotEmpty) {
    stdout.writeln('\n-- os que têm o exercício-base vazio --');
    for (final e in noUltimo) {
      stdout.writeln('  ${(e['ticker'] as String).padRight(7)} '
          'vazios=${e['vazios']}/${e['exercicios']}  '
          'anos=${e['anosVazios']}  '
          '${e['recusa'] != null ? "RECUSADO" : "justo=${e['justo']}"}');
    }
  }

  final noMeio = l.where((e) => e['ultimoVazio'] != true).toList();
  if (noMeio.isNotEmpty) {
    stdout.writeln('\n-- vazio no meio da série (envenena crescimento e '
        'retorno, não a base) --');
    for (final e in noMeio.take(20)) {
      stdout.writeln('  ${(e['ticker'] as String).padRight(7)} '
          'vazios=${e['vazios']}/${e['exercicios']}  anos=${e['anosVazios']}  '
          '${e['recusa'] != null ? "RECUSADO" : "justo=${e['justo']}"}');
    }
    if (noMeio.length > 20) stdout.writeln('  … e mais ${noMeio.length - 20}');
  }
}
