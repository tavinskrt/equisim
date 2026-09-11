// O divisor da ponte: quanto custa a regra do maior, e o que o backtest vê.
//
// Duas perguntas, e a segunda foi descoberta ao tentar responder a primeira.
//
// **1.** `quotedShares` adota, na divergência, a **maior** das duas candidatas
// a divisor. Um grupamento societário reduz a contagem corrente sem tocar a do
// exercício, de modo que a candidata contábil fica maior sempre — e vence
// sempre. Quanto isso move o potencial dos afetados, e onde eles caem na
// ordenação que o usuário lê?
//
// **2.** A validação fora da amostra **não enxerga nada disso**.
// `tool/backtest_valuation.dart` reconstrói o valor de mercado de cada
// exercício como `contagem do exercício × preço da coorte` — o que é correto
// para não injetar a capitalização de hoje numa avaliação de 2018, mas faz as
// duas candidatas a divisor colapsarem na mesma, e a razão de unidade valer 1
// sempre. Esta ferramenta confere isso em vez de supor.
//
// Uso:
//   dart run tool/divisor_contrafactual.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

/// Réplica da reescala do backtest, para conferir o que ela faz ao divisor.
FundamentalsSnapshot _comoNoBacktest(FundamentalsSnapshot s, double preco) =>
    FundamentalsSnapshot(
      ticker: s.ticker,
      fiscalPeriodEnd: s.fiscalPeriodEnd,
      totalRevenue: s.totalRevenue,
      ebit: s.ebit,
      ebitda: s.ebitda,
      netIncome: s.netIncome,
      incomeBeforeTax: s.incomeBeforeTax,
      incomeTaxExpense: s.incomeTaxExpense,
      interestExpense: s.interestExpense,
      earningsPerShare: s.earningsPerShare,
      nopat: s.nopat,
      cash: s.cash,
      shortTermInvestments: s.shortTermInvestments,
      shortTermDebt: s.shortTermDebt,
      longTermDebt: s.longTermDebt,
      totalStockholderEquity: s.totalStockholderEquity,
      bookValuePerShare: s.bookValuePerShare,
      propertyPlantEquipment: s.propertyPlantEquipment,
      intangibleAssets: s.intangibleAssets,
      totalCurrentAssets: s.totalCurrentAssets,
      currentLiabilities: s.currentLiabilities,
      realizedShareCapital: s.realizedShareCapital,
      profitReserves: s.profitReserves,
      operatingCashFlow: s.operatingCashFlow,
      investmentCashFlow: s.investmentCashFlow,
      freeCashFlow: s.freeCashFlow,
      sharesOutstanding: s.sharesOutstandingAsOf,
      sharesOutstandingAsOf: s.sharesOutstandingAsOf,
      marketCap: (s.sharesOutstandingAsOf != null &&
              s.sharesOutstandingAsOf! > 0 &&
              preco > 0)
          ? s.sharesOutstandingAsOf! * preco
          : null,
      enterpriseToEbitda: null,
    );

String _pc(double? v) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

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

    final linhas = <Map<String, Object?>>[];
    var colapsados = 0, conferidos = 0;

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
      );
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final pub = PointInTimeView(_hoje).published(inputs.fundamentals);
      if (pub.isEmpty) continue;
      final latest = pub.last;
      final preco = inputs.marketPrice;

      // -- Pergunta 2: a reescala do backtest colapsa as candidatas? --------
      final reescalado = _comoNoBacktest(latest, preco);
      final uBack = ValuationCascade.quotedUnitRatio(
        sharesOutstanding: reescalado.sharesOutstanding,
        marketCap: reescalado.marketCap,
        marketPrice: preco,
      );
      final qBack = ValuationCascade.quotedShares(
        latest: reescalado,
        marketPrice: preco,
        sharesPerQuote: uBack,
        published: [for (final s in pub) _comoNoBacktest(s, preco)],
      );
      if (qBack != null) {
        conferidos++;
        // Tolerância, e não `== 1.0`: este contador é o número que a
        // ferramenta existe para produzir, e uma razão que voltasse
        // 1,0000000000000002 o omitiria em silêncio.
        if (!qBack.diverge && (uBack - 1.0).abs() < 1e-9) colapsados++;
      }

      // -- Pergunta 1: o custo da regra do maior, hoje ----------------------
      final u = ValuationCascade.quotedUnitRatio(
        sharesOutstanding: latest.sharesOutstanding,
        marketCap: latest.marketCap,
        marketPrice: preco,
      );
      final q = ValuationCascade.quotedShares(
        latest: latest,
        marketPrice: preco,
        sharesPerQuote: u,
        published: pub,
      );
      if (q == null) continue;

      final r = ValuationCascade.evaluate(inputs);
      if (r.isErr) continue;
      final res = r.unwrap();

      // O potencial é `E ÷ (P × N) − 1`. Trocar o divisor por N' reescala o
      // preço justo por N/N', e o potencial acompanha por identidade.
      final adotado = q.count;
      final mercado = q.fromMarketCap;
      final justo = res.fairValue.reais;
      final justoPeloMercado =
          (mercado != null && mercado > 0) ? justo * adotado / mercado : null;

      linhas.add({
        'ticker': ticker.value,
        'preco': preco,
        'fonte': q.source.name,
        'diverge': q.diverge,
        'divisorAdotado': adotado,
        'divisorDeMercado': mercado,
        'razao': (mercado != null && mercado > 0) ? adotado / mercado : null,
        'justoAdotado': justo,
        'justoPeloMercado': justoPeloMercado,
        'potencialAdotado': res.upside,
        'potencialPeloMercado':
            justoPeloMercado == null ? null : justoPeloMercado / preco - 1,
      });
    }
    stderr.writeln('');

    stdout.writeln('== 2. O que a validação fora da amostra enxerga ==');
    stdout.writeln('');
    stdout.writeln('  Sob a reescala do backtest, em $conferidos ativos:');
    stdout.writeln('    candidatas colapsadas (u = 1 e sem divergência): '
        '$colapsados de $conferidos');
    stdout.writeln('  Ou seja: a razão de unidade e a regra do maior não são');
    stdout.writeln('  exercitadas por coorte nenhuma. O potencial medido fora');
    stdout.writeln('  da amostra não é o potencial que a tela mostra, para os');
    stdout.writeln('  ativos em que essas duas peças decidem algo.');

    final afetados =
        linhas.where((l) => l['fonte'] == 'reconciled' && l['diverge'] == true)
            .toList()
      ..sort((a, b) =>
          (b['razao']! as double).compareTo(a['razao']! as double));

    stdout.writeln('');
    stdout.writeln('');
    stdout.writeln('== 1. O custo da regra do maior, hoje ==');
    stdout.writeln('');
    stdout.writeln('  ${linhas.length} avaliados; '
        '${afetados.length} com a contábil vencendo a divergência.');
    stdout.writeln('');
    stdout.writeln('  ticker    divisor/merc   justo adotado   justo p/ merc'
        '    pot. adotado   pot. p/ merc');
    for (final l in afetados) {
      stdout.writeln('  ${(l['ticker']! as String).padRight(8)} '
          '${(l['razao']! as double).toStringAsFixed(2).padLeft(11)}x   '
          '${(l['justoAdotado']! as double).toStringAsFixed(2).padLeft(13)}   '
          '${(l['justoPeloMercado'] as double?)?.toStringAsFixed(2).padLeft(13) ?? "            —"}'
          '   ${_pc(l['potencialAdotado'] as double?).padLeft(13)}'
          '   ${_pc(l['potencialPeloMercado'] as double?).padLeft(13)}');
    }

    // Onde os afetados caem na ordenação que o usuário lê.
    final comPot = linhas
        .where((l) => l['potencialAdotado'] != null)
        .toList()
      ..sort((a, b) => (b['potencialAdotado']! as double)
          .compareTo(a['potencialAdotado']! as double));
    stdout.writeln('');
    stdout.writeln('  posição dos afetados na ordenação por potencial '
        '(${comPot.length} avaliados):');
    for (var k = 0; k < comPot.length; k++) {
      final l = comPot[k];
      if (l['fonte'] != 'reconciled' || l['diverge'] != true) continue;
      stdout.writeln('    ${(k + 1).toString().padLeft(3)}º  '
          '${(l['ticker']! as String).padRight(8)} '
          '${_pc(l['potencialAdotado'] as double?)}  →  pelo divisor de '
          'mercado seria ${_pc(l['potencialPeloMercado'] as double?)}');
    }

    File('docs/validacao/divisor_contrafactual.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(linhas),
    );
    stdout.writeln('');
    stdout.writeln('  gravado em docs/validacao/divisor_contrafactual.json');
  } finally {
    await ctx.dispose();
  }
}
