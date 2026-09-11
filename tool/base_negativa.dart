// O exercício-base no prejuízo, e o que o motor faz com ele.
//
// **O caso.** `tool/recusas.dart` mostra sete ativos saindo por "os dados não
// sustentam nenhuma das duas vias": USIM3, USIM5, PCAR3, CSAN3, LWSA3, AZEV4 e
// HBSA3. Em quase todos a causa é a mesma — o último exercício publicado veio
// no prejuízo, o fluxo-base sai não positivo, e a cascata recusa.
//
// **Por que isso é defeito e não prudência.** O motor já normaliza o
// exercício-base contra a mediana do ciclo quando ele destoa: é a Guarda 1, e
// ela existe justamente porque um exercício não descreve a empresa. Só que o
// fator é `ciclo ÷ atual`, e ele exige `atual > 0` — de modo que a correção
// funciona para o pico e desliga no vale. Numa siderúrgica, o vale é metade do
// ciclo.
//
// **O que isto mede.** Quantos são, qual o retorno do ciclo deles, e o que a
// normalização daria se soubesse operar no vale.
//
// Uso:
//   dart run tool/base_negativa.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

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
      if (prep.isErr) continue;
      final inputs = prep.unwrap();

      final divulgados = PointInTimeView(inputs.asOf)
          .published(inputs.fundamentals)
          .where((s) => s.hasIncomeStatement)
          .toList();
      if (divulgados.isEmpty) continue;

      final aliquota = CapitalSeries.structuralTaxRate(
        divulgados,
        statutoryRate: ValuationParameters.statutoryTaxRate,
      );

      for (final via in ValuationLane.values) {
        final serie = CapitalSeries.build(
          divulgados,
          via,
          firmTaxRate: via == ValuationLane.firm ? aliquota : null,
        );
        if (serie.isTooShort) continue;
        final atual = serie.latestReturn;
        if (atual == null || atual > 0) continue;

        final ciclo = serie.cycleReturn(window: ValuationParameters.cycleWindow);
        final queda = GrowthGuards.recentOperationalDecline(divulgados);
        final ciclico = CyclicalSectors.hasCyclePrecedence(
          sectorKey: inputs.sectorKey,
          industry: inputs.industry,
        );
        final r = ValuationCascade.evaluate(inputs);

        saida.add({
          'ticker': ticker.value,
          'via': via.name,
          'setor': inputs.sectorKey,
          'subsetor': inputs.industry,
          'ciclico': ciclico,
          'retornoAtual': atual,
          'retornoCiclo': ciclo,
          'quedaOperacional': queda,
          'exercicios': divulgados.length,
          // Quantos dos últimos oito exercícios vieram no prejuízo: um vale é
          // um; quatro seguidos é outra empresa.
          'fracaoPositiva':
              serie.positiveShare(window: ValuationParameters.cycleWindow),
          'capitalAtual': serie.latestBase,
          'anosNegativos': serie.returns
              .skip(serie.returns.length > 8 ? serie.returns.length - 8 : 0)
              .where((x) => x.value <= 0)
              .length,
          'avaliado': r.isOk,
          'recusa': r.isErr ? r.failureOrNull!.message : null,
        });
      }
    }
    stderr.writeln('');

    File('docs/validacao/base_negativa.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida);
    stderr.writeln('\nescrito docs/validacao/base_negativa.json '
        '(${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== EXERCÍCIO-BASE NO PREJUÍZO ===\n');
  final tickers = {for (final e in l) e['ticker'] as String};
  stdout.writeln('  ativos com retorno corrente não positivo: '
      '${tickers.length}');
  final recusados = {
    for (final e in l)
      if (e['avaliado'] != true) e['ticker'] as String
  };
  stdout.writeln('  destes, recusados pelo motor: ${recusados.length}');

  final comCicloPositivo = l
      .where((e) =>
          e['retornoCiclo'] != null && (e['retornoCiclo'] as num) > 0)
      .toList();
  stdout.writeln('  linhas com ciclo positivo medível: '
      '${comCicloPositivo.length} de ${l.length}');

  stdout.writeln('\n  ${"ativo".padRight(8)}${"via".padRight(13)}'
      '${"atual".padLeft(8)}${"ciclo".padLeft(9)}${"queda".padLeft(9)}'
      '${"neg/8".padLeft(7)}  cíclico  situação');
  final ord = [...l]..sort((a, b) =>
      (a['ticker'] as String).compareTo(b['ticker'] as String));
  for (final e in ord) {
    final atual = (e['retornoAtual'] as num?)?.toDouble();
    final ciclo = (e['retornoCiclo'] as num?)?.toDouble();
    final queda = (e['quedaOperacional'] as num?)?.toDouble();
    stdout.writeln('  ${(e['ticker'] as String).padRight(8)}'
        '${(e['via'] as String).padRight(13)}'
        '${_pc(atual).padLeft(8)}${_pc(ciclo).padLeft(9)}'
        '${_pc(queda).padLeft(9)}'
        '${(e['anosNegativos'] as int).toString().padLeft(7)}'
        '  ${(e['ciclico'] == true ? "sim" : "não").padRight(7)}'
        '  ${e['avaliado'] == true ? "avaliado" : "RECUSADO"}');
  }
}
