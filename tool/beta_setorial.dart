// Beta desalavancado, e quanto o setor explica.
//
// **Por que agora.** O teste A1 ([decisão 39](../docs/decisoes/039-as-duas-vias-sao-modelos-independentes.md))
// mostrou que as duas vias são modelos independentes, e que uma das duas
// razões é que `Ke` e `WACC` não estão ligados pela alavancagem: o beta é
// regressão crua contra o Ibovespa, sem versão desalavancada. Sem essa ligação
// a identidade `FCFF/WACC ≡ FCFE/Ke` não fecha por construção, e a conciliação
// das vias não tem como acontecer.
//
// **O que se mede aqui, antes de trocar nada:**
//
//   1. **O ruído do beta atual.** `SE(β) = |β|·√((1−ρ²)/(ρ²·(n−2)))` — a
//      identidade que liga erro-padrão a correlação e tamanho de amostra. Um
//      beta cujo intervalo cobre 1,0 não distingue o ativo do mercado, e
//      alimenta um `Ke` com precisão fingida.
//   2. **Se o setor explica.** Desalavancando por Hamada,
//      `β_U = β_L / (1 + (1−t)·D/E)`, o que sobra é risco do **negócio**. Se a
//      dispersão dentro do setor for muito menor que a do universo, a mediana
//      setorial é estimador melhor que a regressão individual. Se não for, o
//      agrupamento não compra nada.
//   3. **Quanto muda.** Realavancando a mediana setorial para a estrutura de
//      capital do próprio ativo, quanto o beta e o `Ke` se movem.
//
// **D/E é a preço de mercado e sobre dívida bruta**, para ficar consistente
// com o que `CostOfCapital` já usa no peso da dívida — misturar dívida líquida
// aqui e bruta lá produziria duas alavancagens no mesmo cálculo.
//
// Uso:
//   dart run tool/beta_setorial.dart
//   dart run tool/beta_setorial.dart --limit 40
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

/// Erro-padrão da inclinação, pela identidade com a correlação.
///
/// `SE(β) = |β| · √((1 − ρ²) / (ρ² · (n − 2)))`. Devolve `null` sem correlação
/// utilizável ou com amostra curta demais.
double? _erroPadrao(double beta, double rho, int n) {
  if (n <= 2) return null;
  final r2 = rho * rho;
  if (r2 <= 0 || r2 >= 1) return null;
  final v = beta.abs() * math.sqrt((1 - r2) / (r2 * (n - 2)));
  return v.isFinite ? v : null;
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Desvio absoluto mediano escalado — dispersão robusta.
double? _mad(List<double> v) => Inference.scaledMad(v);

Future<void> main(List<String> args) async {
  final limiteIdx = args.indexOf('--limit');
  final limite = limiteIdx >= 0 ? int.tryParse(args[limiteIdx + 1]) ?? 0 : 0;

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (limite > 0 && universe.length > limite) {
      universe = universe.sublist(0, limite);
    }

    final ibov = await ctx.benchmark.ibovespa(DateRange(
      DateTime(_hoje.year - PrepareValuationInputs.betaWindowYears,
          _hoje.month, _hoje.day),
      _hoje,
    ));
    if (ibov.isErr) {
      stderr.writeln('sem Ibovespa: ${ibov.failureOrNull?.message}');
      exit(2);
    }
    final indice = ibov.unwrap();

    final saida = <Map<String, dynamic>>[];
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');

      final precos = await ctx.prices.daily(
        ticker,
        DateRange(
          DateTime(_hoje.year - PrepareValuationInputs.betaWindowYears,
              _hoje.month, _hoje.day),
          _hoje,
        ),
      );
      if (precos.isErr) continue;

      final pontos = precos.unwrap().points;
      final alinhado = BetaCalculator.alignReturns(
        assetDates: [for (final p in pontos) p.date],
        assetIndex: [for (final p in pontos) p.close],
        marketDates: indice.dates,
        marketIndex: indice.points.map((p) => p.close).toList(),
      );
      final estRes = BetaCalculator.estimate(returns: alinhado);
      if (estRes.isErr) continue;
      final est = estRes.unwrap();

      final histRes = await ctx.fundamentals.history(ticker);
      if (histRes.isErr) continue;
      final pub = PointInTimeView(_hoje).published(histRes.unwrap());
      if (pub.isEmpty) continue;
      final latest = pub.last;

      final perfil = await ctx.fundamentals.profile(ticker);
      // A chave, não o rótulo: é ela que agrupa de forma estável. Chave vazia
      // é ausência de setor, não um setor chamado "".
      final chave = perfil.isOk ? perfil.unwrap().sector.key.trim() : '';
      final setor = chave.isEmpty ? null : chave;

      final dividaBruta = latest.totalDebt;
      final equityMercado = latest.marketCap;
      if (equityMercado == null || equityMercado <= 0) continue;
      final de = dividaBruta / equityMercado;

      final aliquota = CapitalSeries.structuralTaxRate(
            pub,
            statutoryRate: ValuationParameters.statutoryTaxRate,
          ) ??
          ValuationParameters.statutoryTaxRate;

      // Hamada: β_L = β_U · (1 + (1 − t)·D/E)
      final fatorHamada = 1 + (1 - aliquota) * de;
      final betaU = fatorHamada > 0 ? est.beta / fatorHamada : null;

      saida.add({
        'ticker': ticker.value,
        'setor': setor,
        'betaRegressao': est.beta,
        'correlacao': est.correlation,
        'observacoes': est.observations,
        'erroPadrao': _erroPadrao(est.beta, est.correlation, est.observations),
        'dividaSobreEquity': de,
        'aliquotaEstrutural': aliquota,
        'fatorHamada': fatorHamada,
        'betaDesalavancado': betaU,
        'rfCorrente': anchors.currentRiskFreeRate,
      });
    }
    stderr.writeln('');

    // --- Medianas setoriais do beta desalavancado ---
    final porSetor = <String, List<double>>{};
    for (final e in saida) {
      final s = e['setor'] as String?;
      final b = e['betaDesalavancado'] as double?;
      if (s == null || b == null || !b.isFinite) continue;
      (porSetor[s] ??= []).add(b);
    }
    final medianaSetor = <String, double>{
      for (final e in porSetor.entries)
        if (e.value.length >= 3) e.key: _mediana(e.value)!,
    };

    // Dispersão transversal dos betas de regressão — é a variância do
    // **prior** no encolhimento de Vasicek. Sem ela não há como pesar o
    // estimador individual contra o do grupo.
    final dispersaoPrior = _mad([
          for (final e in saida)
            if ((e['betaRegressao'] as double).isFinite)
              e['betaRegressao'] as double,
        ]) ??
        0.5;
    final medianaUniverso = _mediana([
          for (final e in saida)
            if ((e['betaDesalavancado'] as double?)?.isFinite ?? false)
              e['betaDesalavancado'] as double,
        ]) ??
        0.5;

    for (final e in saida) {
      final s = e['setor'] as String?;
      final mu = s == null ? null : medianaSetor[s];
      e['betaUSetor'] = mu;

      // --- Encolhimento de Vasicek ---
      //
      // `w = (1/SE²) / (1/SE² + 1/σ_prior²)`. O peso do estimador individual é
      // a **precisão** dele contra a do prior: um beta com erro-padrão de 0,07
      // fica com 98% de si mesmo, e um com 83.228 fica com nada. Nenhum limiar
      // decide — a precisão decide, e é contínua.
      final se = e['erroPadrao'] as double?;
      final fator = e['fatorHamada'] as double;
      final priorU = mu ?? medianaUniverso;
      final priorL = priorU * fator;
      final individual = e['betaRegressao'] as double;
      if (se != null && se > 0 && dispersaoPrior > 0) {
        final precisaoIndividual = 1 / (se * se);
        final precisaoPrior = 1 / (dispersaoPrior * dispersaoPrior);
        final w = precisaoIndividual / (precisaoIndividual + precisaoPrior);
        final encolhido = w * individual + (1 - w) * priorL;
        e['pesoVasicek'] = w;
        e['betaEncolhido'] = encolhido;
        e['variacaoVasicek'] = encolhido - individual;
        e['variacaoKeVasicek'] =
            (encolhido - individual) * CapmInputs.defaultMarketPremium;
      }
      e['ativosNoSetor'] = s == null ? 0 : (porSetor[s]?.length ?? 0);
      if (mu != null) {
        final novo = mu * (e['fatorHamada'] as double);
        e['betaRealavancado'] = novo;
        e['variacaoBeta'] = novo - (e['betaRegressao'] as double);
        // Efeito direto no Ke, ao prêmio parametrizado.
        e['variacaoKe'] =
            (novo - (e['betaRegressao'] as double)) * CapmInputs.defaultMarketPremium;
      }
    }

    // --- Efeito em produção: avaliar com e sem o prior ---
    //
    // O prior sai das mesmas observações que este utilitário já coletou, pelo
    // agregador do núcleo — não por uma segunda implementação aqui.
    final prior = ResolveBetaPrior.fromObservations([
      for (final e in saida)
        BetaObservation(
          leveredBeta: e['betaRegressao'] as double,
          sectorKey: e['setor'] as String?,
          debtToEquity: e['dividaSobreEquity'] as double,
          taxRate: e['aliquotaEstrutural'] as double,
        ),
    ]);
    if (prior != null) {
      stderr.writeln('prior: ${prior.unleveredBySector.length} setores, '
          'universo=${prior.unleveredUniverse.toStringAsFixed(3)}, '
          'dispersão=${prior.dispersion.toStringAsFixed(3)}');
      var j = 0;
      for (final e in saida) {
        j++;
        if (j % 25 == 0) {
          stderr.write('  produção $j/${saida.length}   \r');
        }
        final t = Ticker.parse(e['ticker'] as String);

        Future<double?> justo({BetaPrior? p}) async {
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
            projectionYears: 10,
            betaPrior: p,
          );
          if (prep.isErr) return null;
          final r = ValuationCascade.evaluate(prep.unwrap());
          return r.isOk ? r.unwrap().fairValue.reais : null;
        }

        final sem = await justo();
        final com = await justo(p: prior);
        e['justoSemPrior'] = sem;
        e['justoComPrior'] = com;
        if (sem != null && com != null && sem > 0) {
          e['variacaoJusto'] = com / sem - 1;
        }
      }
      stderr.writeln('');
    }

    File('docs/validacao/beta_setorial.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida, porSetor, medianaSetor);
    stderr.writeln('\nescrito docs/validacao/beta_setorial.json '
        '(${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(
  List<Map<String, dynamic>> l,
  Map<String, List<double>> porSetor,
  Map<String, double> medianaSetor,
) {
  List<double> col(String k) => [
        for (final e in l)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble(),
      ];
  String n2(double? x) => x == null ? '—' : x.toStringAsFixed(2);
  String pc(double? x) =>
      x == null ? '—' : '${(x * 100).toStringAsFixed(2)} p.p.';

  stdout.writeln('\n=== BETA DESALAVANCADO — ${l.length} ativos ===\n');

  // --- 1. O ruído do beta atual ---
  final se = col('erroPadrao');
  final betas = col('betaRegressao');
  stdout.writeln('-- ruído do beta de regressão --');
  stdout.writeln('  β: mediana=${n2(_mediana(betas))}  '
      'dispersão robusta=${n2(_mad(betas))}');
  if (se.isNotEmpty) {
    final s = [...se]..sort();
    stdout.writeln('  erro-padrão: mediana=${n2(_mediana(s))}  '
        'p75=${n2(s[3 * s.length ~/ 4])}  p90=${n2(s[9 * s.length ~/ 10])}');
    var cobreUm = 0, seMaiorQue03 = 0;
    for (final e in l) {
      final b = e['betaRegressao'] as double?;
      final err = e['erroPadrao'] as double?;
      if (b == null || err == null) continue;
      if ((b - 1).abs() < 1.96 * err) cobreUm++;
      if (err > 0.3) seMaiorQue03++;
    }
    stdout.writeln('  intervalo de 95% cobre 1,0 em $cobreUm de ${se.length}'
        '  (o beta não distingue o ativo do mercado)');
    stdout.writeln('  erro-padrão acima de 0,30: $seMaiorQue03 de ${se.length}');
  }

  // --- 2. O setor explica? ---
  final bu = col('betaDesalavancado');
  final dispersaoUniverso = _mad(bu);
  final dentro = <double>[];
  for (final e in porSetor.entries) {
    if (e.value.length < 3) continue;
    final m = _mad(e.value);
    if (m != null && m.isFinite) dentro.add(m);
  }
  stdout.writeln('\n-- o setor explica risco de negócio? --');
  stdout.writeln('  β desalavancado: mediana=${n2(_mediana(bu))}  '
      'dispersão robusta do universo=${n2(dispersaoUniverso)}');
  stdout.writeln('  dispersão robusta MEDIANA dentro do setor='
      '${n2(_mediana(dentro))}  (${dentro.length} setores com 3+ ativos)');
  if (dispersaoUniverso != null && _mediana(dentro) != null) {
    final reducao = 1 - _mediana(dentro)! / dispersaoUniverso;
    stdout.writeln('  redução de dispersão ao agrupar: '
        '${(reducao * 100).toStringAsFixed(1)}%');
  }
  stdout.writeln('  ativos sem setor com 3+ pares: '
      '${l.where((e) => e['betaUSetor'] == null).length} de ${l.length}');

  // --- 3. Quanto muda ---
  final dBeta = col('variacaoBeta');
  final dKe = col('variacaoKe');
  stdout.writeln('\n-- efeito de trocar regressão por setorial realavancado --');
  if (dBeta.isNotEmpty) {
    final s = [...dBeta.map((x) => x.abs())]..sort();
    stdout.writeln('  |Δβ|: mediana=${n2(_mediana(s))}  '
        'p90=${n2(s[9 * s.length ~/ 10])}  máx=${n2(s.last)}');
    stdout.writeln('  Δβ mediano com sinal: ${n2(_mediana(dBeta))}');
  }
  if (dKe.isNotEmpty) {
    final s = [...dKe.map((x) => x.abs())]..sort();
    stdout.writeln('  |ΔKe|: mediana=${pc(_mediana(s))}  '
        'p90=${pc(s[9 * s.length ~/ 10])}');
    stdout.writeln('  ΔKe mediano com sinal: ${pc(_mediana(dKe))}');
  }

  // --- 3b. Encolhimento de Vasicek ---
  final w = col('pesoVasicek');
  final dv = col('variacaoVasicek');
  final dkv = col('variacaoKeVasicek');
  stdout.writeln('\n-- encolhimento por precisão (Vasicek) --');
  if (w.isNotEmpty) {
    final s = [...w]..sort();
    stdout.writeln('  peso do estimador individual: '
        'mediana=${n2(_mediana(s))}  p10=${n2(s[s.length ~/ 10])}  '
        'mín=${n2(s.first)}');
    stdout.writeln('  abaixo de 0,90 (o prior pesa): '
        '${w.where((x) => x < 0.90).length} de ${w.length}');
  }
  if (dv.isNotEmpty) {
    final s = [...dv.map((x) => x.abs())]..sort();
    stdout.writeln('  |Δβ|: mediana=${n2(_mediana(s))}  '
        'p90=${n2(s[9 * s.length ~/ 10])}  máx=${n2(s.last)}');
    stdout.writeln('  |ΔKe|: mediana='
        '${pc(_mediana([...dkv.map((x) => x.abs())]))}');
  }

  // --- 3c. Efeito em produção ---
  final dj = col('variacaoJusto');
  stdout.writeln('\n-- efeito no preço justo, em produção --');
  if (dj.isEmpty) {
    stdout.writeln('  sem comparação disponível');
  } else {
    final s = [...dj.map((x) => x.abs())]..sort();
    stdout.writeln('  avaliados nos dois modos: ${dj.length}');
    stdout.writeln('  |Δ preço justo|: mediana=${pc(_mediana(s))}  '
        'p90=${pc(s[9 * s.length ~/ 10])}  máx=${pc(s.last)}');
    stdout.writeln('  alterados além de 0,5%: '
        '${dj.where((x) => x.abs() > 0.005).length} de ${dj.length}');
  }

  // --- 4. Os setores ---
  stdout.writeln('\n-- mediana desalavancada por setor (3+ ativos) --');
  final ordenado = medianaSetor.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  for (final e in ordenado) {
    stdout.writeln('  ${e.key.padRight(34)} β_U=${n2(e.value)}  '
        'n=${porSetor[e.key]!.length}  '
        'dispersão=${n2(_mad(porSetor[e.key]!))}');
  }
}
