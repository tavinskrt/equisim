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

const _saida = 'docs/validacao/beta_liquidez.json';

/// Mínimo de pares para a regressão de Dimson ter sentido.
const _minimoDePares = 40;

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantil(List<double> v, double p) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round()];
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

/// `β = Σ_{k=−K}^{K} β_k`, das inclinações de uma regressão múltipla — a
/// correção de Dimson para negociação não síncrona, com [defasagens]
/// defasagens e outras tantas antecipações.
///
/// **Uma defasagem é a forma clássica, e ela supõe que o atraso cabe num
/// pregão.** Papel que negocia sessenta vezes por ano não responde ao mercado
/// no dia seguinte: responde no próximo negócio, que pode estar a uma semana.
/// Por isso a medição do B14 roda também com cinco — se o beta corrigido subir
/// até o dos avaliados, o atraso era o problema; se não subir, o beta daquele
/// papel não é estimável com esta série, e isso é outra coisa.
({double beta, double erro})? _dimson(
  List<double> ra,
  List<double> rm, {
  int defasagens = 1,
}) {
  // Cada termo consome dois graus de liberdade de amostra nas pontas e um
  // coeficiente; sem folga, a regressão devolve ruído com cara de número.
  if (ra.length < _minimoDePares + 4 * defasagens) return null;
  final y = <double>[];
  final colunas = [
    for (var k = 0; k < 2 * defasagens + 1; k++) <double>[],
  ];
  for (var t = defasagens; t < ra.length - defasagens; t++) {
    y.add(ra[t]);
    for (var k = -defasagens; k <= defasagens; k++) {
      colunas[k + defasagens].add(rm[t + k]);
    }
  }
  final ols = Regression.ols(colunas, y);
  if (ols == null) return null;
  var beta = 0.0;
  // Erro-padrão da soma **ignorando a covariância entre os coeficientes**: é
  // cota inferior, e serve para ordem de grandeza — que é o uso aqui.
  var v = 0.0;
  for (var k = 1; k <= colunas.length; k++) {
    beta += ols.coefficients[k];
    v += ols.stdErrors[k] * ols.stdErrors[k];
  }
  return (beta: beta, erro: v <= 0 ? 0.0 : _raiz(v));
}

double _raiz(double x) {
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
/// Com [beta] e [betaDesalavancado], o CAPM é remontado sobre o beta informado.
ValuationInputs _solto(
  ValuationInputs b, {
  double? beta,
  double? betaDesalavancado,
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
      unleveredBeta: betaDesalavancado ?? b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
      creditReferenceRiskFree: b.creditReferenceRiskFree,
      declaredSharesPerUnit: b.declaredSharesPerUnit,
    );

Future<void> main() async {
  final c = await Congelado.montar();
  try {
    final indiceRes = await c.ctx.benchmark.ibovespa(c.janelaDoBeta);
    if (indiceRes.isErr) {
      stderr.writeln('sem índice: ${indiceRes.failureOrNull?.message}');
      exitCode = 2;
      return;
    }
    final indice = indiceRes.unwrap();
    final datasDoIndice = indice.dates;
    final indiceFechamentos = [for (final p in indice.points) p.close];

    final linhas = <Map<String, dynamic>>[];
    final avaliadas = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final insumos = prep.unwrap();
      final base = ValuationCascade.evaluate(insumos);
      avaliadas[t] = base.valueOrNull;

      final recusa = base.isErr ? base.failureOrNull!.message : null;
      final soLiquidez = recusa != null && recusa.contains('liquidez');
      if (!soLiquidez && recusa != null) continue;

      // --- O beta diário de produção e o de Dimson, na mesma janela --------
      final serie = insumos.prices;
      if (serie == null) continue;
      final pontos =
          serie.points.where((p) => c.janelaDoBeta.contains(p.date)).toList();
      if (pontos.length < 60) continue;
      final par = BetaCalculator.alignReturns(
        assetDates: [for (final p in pontos) p.date],
        assetIndex: [for (final p in pontos) p.close],
        marketDates: datasDoIndice,
        marketIndex: indiceFechamentos,
      );
      final diario = BetaCalculator.estimate(returns: par);
      if (diario.isErr) continue;
      final d = diario.unwrap();
      final dim = _dimson(par.asset, par.market);
      final dim5 = _dimson(par.asset, par.market, defasagens: 5);

      // **O contrafactual tem de ser justo.** O beta de produção já é
      // encolhido em direção ao prior setorial (decisão 40), e Dimson tem
      // erro-padrão muito maior: comparar o encolhido com um Dimson cru
      // premiaria o ruído. Aqui o mesmo encolhimento é aplicado aos dois, com
      // o erro-padrão de cada um — que é o que a produção faria se adotasse a
      // correção.
      final publicados = PointInTimeView(hojeCongelado)
          .published(insumos.fundamentals);
      final ultimo = publicados.isEmpty ? null : publicados.last;
      final mercado = ultimo?.marketCap;
      final de = (ultimo == null || mercado == null || mercado <= 0)
          ? null
          : MarketLeverage.overWindow(
                snapshots: publicados,
                prices: pontos,
                window: c.janelaDoBeta,
              ) ??
              ultimo.debtToMarketEquity(mercado) ??
              0.0;
      final prior = c.prior;
      double? encolher(double? bruto, double? erro) {
        if (bruto == null || prior == null || de == null) return null;
        return BetaShrinkage.shrink(
          leveredBeta: bruto,
          standardError: erro,
          prior: prior,
          sectorKey: insumos.sectorKey,
          debtToEquity: de,
          taxRate: ValuationParameters.statutoryTaxRate,
        ).beta;
      }

      final diarioEncolhido = encolher(d.beta, d.standardError);
      final dimsonEncolhido = encolher(dim?.beta, dim?.erro);
      final dimson5Encolhido = encolher(dim5?.beta, dim5?.erro);

      // --- O preço justo solto do corte, com um beta e com o outro ---------
      double? potencial(ValuationInputs x) {
        final r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().upside : null;
      }

      final comDiario = soLiquidez ? potencial(_solto(insumos)) : null;
      // O beta desalavancado escala com o alavancado: Hamada é linear em `β_L`
      // e o fator de alavancagem não muda entre os dois estimadores.
      double? comBeta(double? encolhido) {
        if (!soLiquidez || encolhido == null) return null;
        final referencia = insumos.capm.beta;
        if (referencia.abs() < 1e-9) return null;
        final fator = encolhido / referencia;
        return potencial(_solto(
          insumos,
          beta: encolhido,
          betaDesalavancado: insumos.unleveredBeta == null
              ? null
              : insumos.unleveredBeta! * fator,
        ));
      }

      final comDimson = comBeta(dimsonEncolhido);
      final comDimson5 = comBeta(dimson5Encolhido);

      linhas.add({
        'ticker': t.value,
        'grupo': soLiquidez ? 'solto' : 'avaliado',
        'pregoes': pontos.length,
        'pregoesPorAno': pontos.length / PrepareValuationInputs.betaWindowYears,
        'liquidez': EligibilityGate.medianTradedValue(serie),
        'betaDiario': d.beta,
        'seDiario': d.standardError,
        'betaDimson': dim?.beta,
        'seDimson': dim?.erro,
        'betaDimson5': dim5?.beta,
        'seDimson5': dim5?.erro,
        'betaDeProducao': insumos.capm.beta,
        'betaDiarioEncolhido': diarioEncolhido,
        'betaDimsonEncolhido': dimsonEncolhido,
        'betaDimson5Encolhido': dimson5Encolhido,
        'potencial': soLiquidez ? comDiario : base.valueOrNull?.upside,
        'potencialComDimson': comDimson,
        'potencialComDimson5': comDimson5,
      });
    }
    stderr.writeln('');

    final divergentes = await c.conferirContraGabarito(avaliadas);
    File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'medidoEm': hojeCongelado.toIso8601String().substring(0, 10),
        'conferidoContraOGabarito': divergentes?.length,
        'ativos': linhas,
      }),
    );
    _imprimir(linhas, divergentes);
    stderr.writeln('\nescrito $_saida (${linhas.length})');
  } finally {
    await c.ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l, List<String>? divergentes) {
  if (divergentes == null) {
    stdout.writeln('\n!! sem gabarito para conferir: a montagem não foi '
        'verificada contra a do aplicativo');
  } else if (divergentes.isNotEmpty) {
    stdout.writeln('\n!! a montagem DIVERGE do gabarito em '
        '${divergentes.length} ativo(s): ${divergentes.take(8).join(', ')}');
    stdout.writeln('!! os números abaixo não valem');
  } else {
    stdout.writeln('\nmontagem idêntica à do gabarito na montagem do '
        'aplicativo.');
  }

  List<Map<String, dynamic>> grupo(String g) =>
      [for (final e in l) if (e['grupo'] == g) e];
  List<double> col(List<Map<String, dynamic>> xs, String k) => [
        for (final e in xs)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble(),
      ];

  final soltos = grupo('solto');
  final avaliados = grupo('avaliado');
  stdout.writeln('\n=== B14 — O BETA DO PAPEL POUCO NEGOCIADO ===');
  stdout.writeln('soltos do corte: ${soltos.length}   '
      'avaliados: ${avaliados.length}');

  stdout.writeln('\n-- quanto cada grupo negocia --');
  for (final (nome, xs) in [('soltos', soltos), ('avaliados', avaliados)]) {
    final pa = col(xs, 'pregoesPorAno');
    final liq = col(xs, 'liquidez');
    stdout.writeln('  ${nome.padRight(10)} pregões/ano mediana '
        '${_mediana(pa)?.toStringAsFixed(0)}  p10 '
        '${_quantil(pa, 0.1)?.toStringAsFixed(0)}   '
        'giro diário mediano R\$ '
        '${((_mediana(liq) ?? 0) / 1000).toStringAsFixed(0)} mil');
  }

  for (final k in ['betaDimson', 'betaDimson5']) {
    stdout.writeln('\n-- ${k == 'betaDimson' ? 'Dimson, uma defasagem' : 'Dimson, cinco defasagens'} ÷ diário --');
    for (final (nome, xs) in [('soltos', soltos), ('avaliados', avaliados)]) {
      final razoes = <double>[];
      for (final e in xs) {
        final a = (e['betaDiario'] as num?)?.toDouble();
        final b = (e[k] as num?)?.toDouble();
        if (a == null || b == null || a.abs() < 1e-9) continue;
        razoes.add(b / a);
      }
      if (razoes.isEmpty) continue;
      stdout.writeln('  ${nome.padRight(10)} p10 '
          '${_quantil(razoes, 0.1)!.toStringAsFixed(3)}  mediana '
          '${_mediana(razoes)!.toStringAsFixed(3)}  p90 '
          '${_quantil(razoes, 0.9)!.toStringAsFixed(3)}   '
          'acima do diário em ${razoes.where((x) => x > 1).length} de '
          '${razoes.length}');
    }
  }

  stdout.writeln('\n-- beta em nível, cru --');
  for (final (nome, xs) in [('soltos', soltos), ('avaliados', avaliados)]) {
    stdout.writeln('  ${nome.padRight(10)} diário '
        '${_mediana(col(xs, 'betaDiario'))?.toStringAsFixed(3)}   '
        'Dimson(1) ${_mediana(col(xs, 'betaDimson'))?.toStringAsFixed(3)}   '
        'Dimson(5) ${_mediana(col(xs, 'betaDimson5'))?.toStringAsFixed(3)}   '
        'SE diário ${_mediana(col(xs, 'seDiario'))?.toStringAsFixed(4)}'
        '  SE Dimson(1) ${_mediana(col(xs, 'seDimson'))?.toStringAsFixed(4)}'
        '  SE Dimson(5) ${_mediana(col(xs, 'seDimson5'))?.toStringAsFixed(4)}');
  }

  // O que chega ao preço é o beta **encolhido** (decisão 40), e o erro-padrão
  // maior de Dimson desloca peso para o prior setorial. Sem esta linha, a
  // comparação premiaria o estimador mais ruidoso.
  stdout.writeln('\n-- beta em nível, encolhido (é o que chega ao preço) --');
  for (final (nome, xs) in [('soltos', soltos), ('avaliados', avaliados)]) {
    stdout.writeln('  ${nome.padRight(10)} produção '
        '${_mediana(col(xs, 'betaDeProducao'))?.toStringAsFixed(3)}   '
        'diário ${_mediana(col(xs, 'betaDiarioEncolhido'))?.toStringAsFixed(3)}'
        '   Dimson(1) '
        '${_mediana(col(xs, 'betaDimsonEncolhido'))?.toStringAsFixed(3)}'
        '   Dimson(5) '
        '${_mediana(col(xs, 'betaDimson5Encolhido'))?.toStringAsFixed(3)}');
  }

  // **Os soltos não são um grupo só.** Metade deles negocia todo pregão, e ali
  // a não sincronia não tem o que explicar; o beta baixo é outra coisa.
  stdout.writeln('\n-- os soltos, por frequência de negócio --');
  for (final (nome, teste) in <(String, bool Function(double))>[
    ('negocia todo dia (>=240/ano)', (x) => x >= 240),
    ('intermitente (120 a 240)', (x) => x >= 120 && x < 240),
    ('raro (< 120/ano)', (x) => x < 120),
  ]) {
    final xs = [
      for (final e in soltos)
        if (e['pregoesPorAno'] != null &&
            teste((e['pregoesPorAno'] as num).toDouble()))
          e,
    ];
    if (xs.isEmpty) continue;
    stdout.writeln('  ${nome.padRight(28)} n=${xs.length.toString().padLeft(3)}'
        '  beta diário ${_mediana(col(xs, 'betaDiario'))?.toStringAsFixed(3)}'
        '  Dimson(1) ${_mediana(col(xs, 'betaDimson'))?.toStringAsFixed(3)}'
        '  Dimson(5) ${_mediana(col(xs, 'betaDimson5'))?.toStringAsFixed(3)}'
        '  potencial ${_pc(_mediana(col(xs, 'potencial')))}');
  }

  stdout.writeln('\n-- o nível do potencial, que é a razão da recusa --');
  stdout.writeln('  avaliados                   '
      '${_pc(_mediana(col(avaliados, 'potencial')))}');
  stdout.writeln('  soltos, beta diário         '
      '${_pc(_mediana(col(soltos, 'potencial')))}');
  stdout.writeln('  soltos, Dimson(1) encolhido '
      '${_pc(_mediana(col(soltos, 'potencialComDimson')))}');
  stdout.writeln('  soltos, Dimson(5) encolhido '
      '${_pc(_mediana(col(soltos, 'potencialComDimson5')))}');
  final comAmbos = [
    for (final e in soltos)
      if (e['potencial'] != null && e['potencialComDimson'] != null)
        ((e['potencialComDimson'] as num).toDouble() -
            (e['potencial'] as num).toDouble()),
  ];
  stdout.writeln('  nos ${comAmbos.length} soltos com os dois: Dimson move o '
      'potencial em ${_pc(_mediana(comAmbos))} na mediana');
}
