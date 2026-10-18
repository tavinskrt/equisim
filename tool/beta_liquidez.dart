// B14 — o beta do papel pouco negociado, e o que ele faz com o nível.
//
// **A pergunta.** A [decisão 95](../docs/decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)
// deixou a recusa por liquidez de pé por **uma** razão: soltos do corte, os
// recusados ordenam o retorno, mas o preço justo deles sai 27 p.p. acima do das
// avaliadas. A explicação proposta foi o beta: papel com pouco negócio responde
// ao mercado com atraso, a covariância contemporânea perde a parte atrasada, o
// beta sai baixo, o custo de capital sai baixo e o preço justo sai alto.
//
// **Se for isso, um beta corrigido tira a razão da recusa.** É o que este
// programa mede, e é o item B14.
//
// [`beta_sincronia.md`](../docs/validacao/beta_sincronia.md) já mediu a
// correção de Dimson **nos avaliados**, e lá ela não existe: a Porta 0 removeu
// quem sofreria. Aquele documento fecha dizendo que, se o corte de liquidez for
// afrouxado, o item volta com o tamanho que o universo cru mostra. Aqui ele
// volta.
//
// **O que se mede, sobre a entrada congelada do gabarito:**
//
//   1. o beta de Dimson contra o diário, nos recusados **só por liquidez** e
//      nos avaliados, com os pregões por ano de cada grupo;
//   2. o preço justo dos soltos com o beta diário e com o de Dimson, os dois
//      sem o corte de liquidez;
//   3. o nível do potencial dos três conjuntos, que é a grandeza da decisão 95.
//
// Uso:
//   dart run tool/gabarito_cascata.dart      # congela a entrada
//   dart run tool/beta_liquidez.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/beta_liquidez.json';

/// Mínimo de pares para a regressão de Dimson ter sentido.
const _minPeers = 40;

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantile(List<double> v, double p) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round()];
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

/// `β = Σ_{k=−K}^{K} β_k`, das inclinações de uma regressão múltipla — a
/// correção de Dimson para negociação não síncrona, com [lags]
/// defasagens e outras tantas antecipações.
///
/// **Uma defasagem é a forma clássica, e ela supõe que o atraso cabe num
/// pregão.** Papel que negocia sessenta vezes por ano não responde ao mercado
/// no dia seguinte: responde no próximo negócio, que pode estar a uma semana.
/// Por isso a medição do B14 roda também com cinco — se o beta corrigido subir
/// até o dos avaliados, o atraso era o problema; se não subir, o beta daquele
/// papel não é estimável com esta série, e isso é outra coisa.
({double beta, double error})? _dimson(
  List<double> ra,
  List<double> rm, {
  int lags = 1,
}) {
  // Cada termo consome dois graus de liberdade de amostra nas pontas e um
  // coeficiente; sem folga, a regressão devolve ruído com cara de número.
  if (ra.length < _minPeers + 4 * lags) return null;
  final y = <double>[];
  final columns = [
    for (var k = 0; k < 2 * lags + 1; k++) <double>[],
  ];
  for (var t = lags; t < ra.length - lags; t++) {
    y.add(ra[t]);
    for (var k = -lags; k <= lags; k++) {
      columns[k + lags].add(rm[t + k]);
    }
  }
  final ols = Regression.ols(columns, y);
  if (ols == null) return null;
  var beta = 0.0;
  // Erro-padrão da soma **ignorando a covariância entre os coeficientes**: é
  // cota inferior, e serve para ordem de grandeza — que é o uso aqui.
  var v = 0.0;
  for (var k = 1; k <= columns.length; k++) {
    beta += ols.coefficients[k];
    v += ols.stdErrors[k] * ols.stdErrors[k];
  }
  return (beta: beta, error: v <= 0 ? 0.0 : _root(v));
}

double _root(double x) {
  if (x <= 0) return 0;
  var r = x;
  for (var i = 0; i < 60; i++) {
    r = 0.5 * (r + x / r);
  }
  return r;
}

/// Os mesmos insumos **sem a série de preços**, que é o que desliga o corte de
/// liquidez da Porta 0 — e só ele: o beta já foi estimado e viaja no CAPM.
///
/// Com [beta] e [unleveredBeta], o CAPM é remontado sobre o beta informado.
ValuationInputs _unconstrained(
  ValuationInputs b, {
  double? beta,
  double? unleveredBeta,
}) =>
    ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: beta == null
          ? b.capm
          : CapmInputs(
              riskFreeRate: b.capm.riskFreeRate,
              beta: beta,
              marketPremium: b.capm.marketPremium,
              betaSource: b.capm.betaSource,
              premiumSource: b.capm.premiumSource,
            ),
      marginOfSafety: b.marginOfSafety,
      projectionYears: b.projectionYears,
      perpetualGrowthCap: b.perpetualGrowthCap,
      sectorKey: b.sectorKey,
      industry: b.industry,
      inflation: b.inflation,
      declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
      riskFreeCurve: b.riskFreeCurve,
      officialShares: b.officialShares,
      isDistressed: b.isDistressed,
      unleveredBeta: unleveredBeta ?? b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
      creditReferenceRiskFree: b.creditReferenceRiskFree,
      declaredSharesPerUnit: b.declaredSharesPerUnit,
    );

Future<void> main() async {
  final c = await Frozen.build();
  try {
    final indexResult = await c.ctx.benchmark.ibovespa(c.betaWindow);
    if (indexResult.isErr) {
      stderr.writeln('sem índice: ${indexResult.failureOrNull?.message}');
      exitCode = 2;
      return;
    }
    final index = indexResult.unwrap();
    final indexDates = index.dates;
    final indexCloses = [for (final p in index.points) p.close];

    final rows = <Map<String, dynamic>>[];
    final evaluated = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final base = ValuationCascade.evaluate(inputs);
      evaluated[t] = base.valueOrNull;

      final refusal = base.isErr ? base.failureOrNull!.message : null;
      final liquidityOnly = refusal != null && refusal.contains('liquidez');
      if (!liquidityOnly && refusal != null) continue;

      // --- O beta diário de produção e o de Dimson, na mesma janela --------
      final series = inputs.prices;
      if (series == null) continue;
      final points =
          series.points.where((p) => c.betaWindow.contains(p.date)).toList();
      if (points.length < 60) continue;
      final pair = BetaCalculator.alignReturns(
        assetDates: [for (final p in points) p.date],
        assetIndex: [for (final p in points) p.close],
        marketDates: indexDates,
        marketIndex: indexCloses,
      );
      final daily = BetaCalculator.estimate(returns: pair);
      if (daily.isErr) continue;
      final d = daily.unwrap();
      final dim = _dimson(pair.asset, pair.market);
      final dim5 = _dimson(pair.asset, pair.market, lags: 5);

      // **O contrafactual tem de ser justo.** O beta de produção já é
      // encolhido em direção ao prior setorial (decisão 40), e Dimson tem
      // erro-padrão muito maior: comparar o encolhido com um Dimson cru
      // premiaria o ruído. Aqui o mesmo encolhimento é aplicado aos dois, com
      // o erro-padrão de cada um — que é o que a produção faria se adotasse a
      // correção.
      final published = PointInTimeView(frozenToday)
          .published(inputs.fundamentals);
      final last = published.isEmpty ? null : published.last;
      final market = last?.marketCap;
      final debtToEquity = (last == null || market == null || market <= 0)
          ? null
          : MarketLeverage.overWindow(
                snapshots: published,
                prices: points,
                window: c.betaWindow,
              ) ??
              last.debtToMarketEquity(market) ??
              0.0;
      final prior = c.prior;
      double? shrink(double? raw, double? error) {
        if (raw == null || prior == null || debtToEquity == null) return null;
        return BetaShrinkage.shrink(
          leveredBeta: raw,
          standardError: error,
          prior: prior,
          sectorKey: inputs.sectorKey,
          debtToEquity: debtToEquity,
          taxRate: ValuationParameters.statutoryTaxRate,
        ).beta;
      }

      final shrunkDaily = shrink(d.beta, d.standardError);
      final shrunkDimson = shrink(dim?.beta, dim?.error);
      final shrunkDimson5 = shrink(dim5?.beta, dim5?.error);

      // --- O preço justo solto do corte, com um beta e com o outro ---------
      double? upside(ValuationInputs x) {
        final r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().upside : null;
      }

      final withDaily = liquidityOnly ? upside(_unconstrained(inputs)) : null;
      // O beta desalavancado escala com o alavancado: Hamada é linear em `β_L`
      // e o fator de alavancagem não muda entre os dois estimadores.
      double? withBeta(double? shrunk) {
        if (!liquidityOnly || shrunk == null) return null;
        final reference = inputs.capm.beta;
        if (reference.abs() < 1e-9) return null;
        final factor = shrunk / reference;
        return upside(_unconstrained(
          inputs,
          beta: shrunk,
          unleveredBeta: inputs.unleveredBeta == null
              ? null
              : inputs.unleveredBeta! * factor,
        ));
      }

      final withDimson = withBeta(shrunkDimson);
      final withDimson5 = withBeta(shrunkDimson5);

      rows.add({
        'ticker': t.value,
        'grupo': liquidityOnly ? 'solto' : 'avaliado',
        'pregoes': points.length,
        'pregoesPorAno': points.length / PrepareValuationInputs.betaWindowYears,
        'liquidez': EligibilityGate.medianTradedValue(series),
        'betaDiario': d.beta,
        'seDiario': d.standardError,
        'betaDimson': dim?.beta,
        'seDimson': dim?.error,
        'betaDimson5': dim5?.beta,
        'seDimson5': dim5?.error,
        'betaDeProducao': inputs.capm.beta,
        'betaDiarioEncolhido': shrunkDaily,
        'betaDimsonEncolhido': shrunkDimson,
        'betaDimson5Encolhido': shrunkDimson5,
        'potencial': liquidityOnly ? withDaily : base.valueOrNull?.upside,
        'potencialComDimson': withDimson,
        'potencialComDimson5': withDimson5,
      });
    }
    stderr.writeln('');

    final divergent = await c.checkAgainstAnswerKey(evaluated);
    File(_output).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'medidoEm': frozenToday.toIso8601String().substring(0, 10),
        'conferidoContraOGabarito': divergent?.length,
        'ativos': rows,
      }),
    );
    _printReport(rows, divergent);
    stderr.writeln('\nescrito $_output (${rows.length})');
  } finally {
    await c.ctx.dispose();
  }
}

void _printReport(List<Map<String, dynamic>> l, List<String>? divergent) {
  if (divergent == null) {
    stdout.writeln('\n!! sem gabarito para conferir: a montagem não foi '
        'verificada contra a do aplicativo');
  } else if (divergent.isNotEmpty) {
    stdout.writeln('\n!! a montagem DIVERGE do gabarito em '
        '${divergent.length} ativo(s): ${divergent.take(8).join(', ')}');
    stdout.writeln('!! os números abaixo não valem');
  } else {
    stdout.writeln('\nmontagem idêntica à do gabarito na montagem do '
        'aplicativo.');
  }

  List<Map<String, dynamic>> group(String g) =>
      [for (final e in l) if (e['grupo'] == g) e];
  List<double> col(List<Map<String, dynamic>> xs, String k) => [
        for (final e in xs)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble(),
      ];

  final unconstrainedOnes = group('solto');
  final evaluated = group('avaliado');
  stdout.writeln('\n=== B14 — O BETA DO PAPEL POUCO NEGOCIADO ===');
  stdout.writeln('soltos do corte: ${unconstrainedOnes.length}   '
      'avaliados: ${evaluated.length}');

  stdout.writeln('\n-- quanto cada grupo negocia --');
  for (final (name, xs) in [('soltos', unconstrainedOnes), ('avaliados', evaluated)]) {
    final sessionsPerYear = col(xs, 'pregoesPorAno');
    final liq = col(xs, 'liquidez');
    stdout.writeln('  ${name.padRight(10)} pregões/ano mediana '
        '${_median(sessionsPerYear)?.toStringAsFixed(0)}  p10 '
        '${_quantile(sessionsPerYear, 0.1)?.toStringAsFixed(0)}   '
        'giro diário mediano R\$ '
        '${((_median(liq) ?? 0) / 1000).toStringAsFixed(0)} mil');
  }

  for (final k in ['betaDimson', 'betaDimson5']) {
    stdout.writeln('\n-- ${k == 'betaDimson' ? 'Dimson, uma defasagem' : 'Dimson, cinco defasagens'} ÷ diário --');
    for (final (name, xs) in [('soltos', unconstrainedOnes), ('avaliados', evaluated)]) {
      final ratios = <double>[];
      for (final e in xs) {
        final a = (e['betaDiario'] as num?)?.toDouble();
        final b = (e[k] as num?)?.toDouble();
        if (a == null || b == null || a.abs() < 1e-9) continue;
        ratios.add(b / a);
      }
      if (ratios.isEmpty) continue;
      stdout.writeln('  ${name.padRight(10)} p10 '
          '${_quantile(ratios, 0.1)!.toStringAsFixed(3)}  mediana '
          '${_median(ratios)!.toStringAsFixed(3)}  p90 '
          '${_quantile(ratios, 0.9)!.toStringAsFixed(3)}   '
          'acima do diário em ${ratios.where((x) => x > 1).length} de '
          '${ratios.length}');
    }
  }

  stdout.writeln('\n-- beta em nível, cru --');
  for (final (name, xs) in [('soltos', unconstrainedOnes), ('avaliados', evaluated)]) {
    stdout.writeln('  ${name.padRight(10)} diário '
        '${_median(col(xs, 'betaDiario'))?.toStringAsFixed(3)}   '
        'Dimson(1) ${_median(col(xs, 'betaDimson'))?.toStringAsFixed(3)}   '
        'Dimson(5) ${_median(col(xs, 'betaDimson5'))?.toStringAsFixed(3)}   '
        'SE diário ${_median(col(xs, 'seDiario'))?.toStringAsFixed(4)}'
        '  SE Dimson(1) ${_median(col(xs, 'seDimson'))?.toStringAsFixed(4)}'
        '  SE Dimson(5) ${_median(col(xs, 'seDimson5'))?.toStringAsFixed(4)}');
  }

  // O que chega ao preço é o beta **encolhido** (decisão 40), e o erro-padrão
  // maior de Dimson desloca peso para o prior setorial. Sem esta linha, a
  // comparação premiaria o estimador mais ruidoso.
  stdout.writeln('\n-- beta em nível, encolhido (é o que chega ao preço) --');
  for (final (name, xs) in [('soltos', unconstrainedOnes), ('avaliados', evaluated)]) {
    stdout.writeln('  ${name.padRight(10)} produção '
        '${_median(col(xs, 'betaDeProducao'))?.toStringAsFixed(3)}   '
        'diário ${_median(col(xs, 'betaDiarioEncolhido'))?.toStringAsFixed(3)}'
        '   Dimson(1) '
        '${_median(col(xs, 'betaDimsonEncolhido'))?.toStringAsFixed(3)}'
        '   Dimson(5) '
        '${_median(col(xs, 'betaDimson5Encolhido'))?.toStringAsFixed(3)}');
  }

  // **Os soltos não são um grupo só.** Metade deles negocia todo pregão, e ali
  // a não sincronia não tem o que explicar; o beta baixo é outra coisa.
  stdout.writeln('\n-- os soltos, por frequência de negócio --');
  for (final (name, test) in <(String, bool Function(double))>[
    ('negocia todo dia (>=240/ano)', (x) => x >= 240),
    ('intermitente (120 a 240)', (x) => x >= 120 && x < 240),
    ('raro (< 120/ano)', (x) => x < 120),
  ]) {
    final xs = [
      for (final e in unconstrainedOnes)
        if (e['pregoesPorAno'] != null &&
            test((e['pregoesPorAno'] as num).toDouble()))
          e,
    ];
    if (xs.isEmpty) continue;
    stdout.writeln('  ${name.padRight(28)} n=${xs.length.toString().padLeft(3)}'
        '  beta diário ${_median(col(xs, 'betaDiario'))?.toStringAsFixed(3)}'
        '  Dimson(1) ${_median(col(xs, 'betaDimson'))?.toStringAsFixed(3)}'
        '  Dimson(5) ${_median(col(xs, 'betaDimson5'))?.toStringAsFixed(3)}'
        '  potencial ${_pc(_median(col(xs, 'potencial')))}');
  }

  stdout.writeln('\n-- o nível do potencial, que é a razão da recusa --');
  stdout.writeln('  avaliados                   '
      '${_pc(_median(col(evaluated, 'potencial')))}');
  stdout.writeln('  soltos, beta diário         '
      '${_pc(_median(col(unconstrainedOnes, 'potencial')))}');
  stdout.writeln('  soltos, Dimson(1) encolhido '
      '${_pc(_median(col(unconstrainedOnes, 'potencialComDimson')))}');
  stdout.writeln('  soltos, Dimson(5) encolhido '
      '${_pc(_median(col(unconstrainedOnes, 'potencialComDimson5')))}');
  final withBoth = [
    for (final e in unconstrainedOnes)
      if (e['potencial'] != null && e['potencialComDimson'] != null)
        ((e['potencialComDimson'] as num).toDouble() -
            (e['potencial'] as num).toDouble()),
  ];
  stdout.writeln('  nos ${withBoth.length} soltos com os dois: Dimson move o '
      'potencial em ${_pc(_median(withBoth))} na mediana');
}
