// D4 — de onde vem o resíduo entre o preço justo e o de mercado.
//
// **A pergunta.** O preço justo mediano fica 36% abaixo do de mercado. Isso não
// é defeito por si: o motor não existe para reproduzir o mercado, e a
// [decisão 35](../docs/decisoes/035-dcf-reverso-e-regressao-condicional.md)
// veda ajustá-lo até que reproduza. O que é defeito é a parte do resíduo que
// vem de o motor usar um número que não é o da empresa, ou uma convenção que
// não é a correta.
//
// **O desenho.** Para cada ativo mede-se quanto o preço justo teria de subir
// para bater no de mercado — `m_necessário = preço ÷ justo` —, e quanto cada
// contrafactual entrega:
//
//   fração fechada = (justo_contrafactual ÷ justo − 1) / (m_necessário − 1)
//
// **Os contrafactuais rodam PELA CASCATA**, por `ValuationInputs.reinvestmentOverride`,
// e não por uma reimplementação da projeção. A versão anterior deste utilitário
// reimplementava, e media outro motor: usava o teto da economia como
// crescimento perpétuo em 78 dos 120 ativos e reinterpolava a taxa de desconto
// em vez de usar o caminho resolvido pelo ponto fixo. A conferência não pegava
// porque comparava o laço contra si mesmo.
//
// Uso:
//   dart run tool/fluxo_explicito.dart
//   dart run tool/fluxo_explicito.dart --limit 30
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

/// Quantos passes o veredito da perpetuidade consumiu, lido do aviso.
int? _passes(List<String> avisos) {
  for (final a in avisos) {
    final m = RegExp(r'fechou em (\d+) passe').firstMatch(a);
    if (m != null) return int.tryParse(m.group(1)!);
    final i = RegExp(r'estabilizaram em (\d+) passes').firstMatch(a);
    if (i != null) return int.tryParse(i.group(1)!);
  }
  return null;
}

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1)}%';
String _mx(double v) => '${v.toStringAsFixed(2)}x';

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

      final res = ValuationCascade.evaluate(inputs);
      if (res.isErr) continue;
      final v = res.unwrap();
      final d = v.diagnostics!;
      final justo = v.fairValue.reais;
      final preco = inputs.marketPrice;
      if (justo <= 0 || preco <= 0) continue;

      /// O mesmo ativo, pela mesma cascata, com o freio trocado.
      double? sob(ReinvestmentPolicy politica) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: inputs.ticker,
          asOf: inputs.asOf,
          fundamentals: inputs.fundamentals,
          marketPrice: inputs.marketPrice,
          capm: inputs.capm,
          marginOfSafety: inputs.marginOfSafety,
          projectionYears: inputs.projectionYears,
          perpetualGrowthCap: inputs.perpetualGrowthCap,
          sectorKey: inputs.sectorKey,
          industry: inputs.industry,
          inflation: inputs.inflation,
          declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
          prices: inputs.prices,
          isDistressed: inputs.isDistressed,
          unleveredBeta: inputs.unleveredBeta,
          reinvestmentOverride: politica,
        ));
        if (r.isErr) return null;
        final x = r.unwrap().fairValue.reais;
        return x > 0 ? x / justo : null;
      }

      final mNecessario = preco / justo;
      double? fracaoFechada(double? m) {
        if (m == null || !m.isFinite) return null;
        if ((mNecessario - 1).abs() < 1e-9) return null;
        return (m - 1) / (mNecessario - 1);
      }

      /// O mesmo ativo com a convenção de caixa de antes da decisão 48.
      double? sobFimDeAno() {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: inputs.ticker,
          asOf: inputs.asOf,
          fundamentals: inputs.fundamentals,
          marketPrice: inputs.marketPrice,
          capm: inputs.capm,
          marginOfSafety: inputs.marginOfSafety,
          projectionYears: inputs.projectionYears,
          perpetualGrowthCap: inputs.perpetualGrowthCap,
          sectorKey: inputs.sectorKey,
          industry: inputs.industry,
          inflation: inputs.inflation,
          declaredTerminalRiskFreeRate: inputs.declaredTerminalRiskFreeRate,
          prices: inputs.prices,
          isDistressed: inputs.isDistressed,
          unleveredBeta: inputs.unleveredBeta,
          cashTimingOverride: CashTiming.fimDeAno,
        ));
        if (r.isErr) return null;
        final x = r.unwrap().fairValue.reais;
        return x > 0 ? x / justo : null;
      }

      final mFimDeAno = sobFimDeAno();
      final mSemFreio = sob(ReinvestmentPolicy.nenhum);
      final mReal = sob(ReinvestmentPolicy.crescimentoReal);
      final mSemConv = sob(ReinvestmentPolicy.semConvergencia);
      final mSemTeto = sob(ReinvestmentPolicy.semTeto);

      final retencao = d.retentionPath;

      saida.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'via': v.model.name,
        'preco': preco,
        'justo': justo,
        'potencial': v.upside,
        'participacaoEquity': d.equityShare,
        'pesoTerminal': d.terminalShare,
        'crescimento': d.growthRate,
        'retornoDaBase': d.returnOnCapital,
        'desconto': v.discountRate,
        'descontoTerminal': d.terminalDiscountRate,
        'aliquotaEstrutural': d.firmTaxRate,
        // Quantos passes o veredito da perpetuidade consumiu até parar de
        // mudar (decisão 51). Sai do aviso porque é propriedade da conta, e
        // não do resultado.
        'passesDoVeredito': _passes(v.warnings),
        'vereditoInstavel':
            v.warnings.any((w) => w.contains('não se estabilizaram em')),
        // O freio, ano a ano, como a cascata o aplicou — inclusive com o
        // caminho de taxas resolvido dentro do `ROIC_t`.
        'retencaoAno1': retencao.isNotEmpty ? retencao.first : null,
        'retencaoAnoN': retencao.isNotEmpty ? retencao.last : null,
        'noTetoAno1': retencao.isNotEmpty && retencao.first >= 0.9499,
        'mNecessario': mNecessario,
        'mSemFreio': mSemFreio,
        'mCrescimentoReal': mReal,
        'mSemConvergencia': mSemConv,
        'mSemTeto': mSemTeto,
        'mFimDeAno': mFimDeAno,
        'fechaSemFreio': fracaoFechada(mSemFreio),
        'fechaCrescimentoReal': fracaoFechada(mReal),
        'fechaSemConvergencia': fracaoFechada(mSemConv),
        'fechaSemTeto': fracaoFechada(mSemTeto),
      });
    }
    stderr.writeln('');

    File('docs/validacao/fluxo_explicito.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida);
    stderr.writeln('\nescrito docs/validacao/fluxo_explicito.json '
        '(${saida.length} ativos)');
  } finally {
    await ctx.dispose();
  }
}

void _imprimir(List<Map<String, dynamic>> l) {
  List<double> col(String k) => [
        for (final e in l)
          if (e[k] != null && (e[k] as num).toDouble().isFinite)
            (e[k] as num).toDouble(),
      ];

  stdout.writeln('\n=== D4 — O RESÍDUO DO FLUXO EXPLÍCITO — ${l.length} '
      'avaliados ===\n');

  final r1 = col('retencaoAno1'), rn = col('retencaoAnoN');
  stdout.writeln('-- retenção imposta pelo freio --');
  stdout.writeln('  ano 1: mediana=${_pc(_mediana(r1)!)}   '
      'ano N: mediana=${_pc(_mediana(rn)!)}');
  stdout.writeln('  no teto de 95% no ano 1: '
      '${l.where((e) => e['noTetoAno1'] == true).length} de ${l.length}');

  final need = col('mNecessario')..sort();
  stdout.writeln('\n-- quanto o preço justo teria de subir --');
  stdout.writeln('  p25=${_mx(need[need.length ~/ 4])}  '
      'mediana=${_mx(_mediana(need)!)}  '
      'p75=${_mx(need[3 * need.length ~/ 4])}');
  stdout.writeln('  já acima do preço: '
      '${need.where((x) => x <= 1).length} de ${need.length}');
  final so = need.where((x) => x > 1).toList();
  stdout.writeln('  entre os que têm vão a fechar: '
      'mediana=${_mx(_mediana(so)!)}  (n=${so.length})');

  // **Só quem tem vão a fechar.** Trinta dos 120 já saem acima do preço de
  // mercado, e para eles todo contrafactual "fecha tudo" por vacuidade — a
  // mediana com eles dentro elogia qualquer coisa.
  final comVao = [
    for (final e in l)
      if (e['mNecessario'] != null && (e['mNecessario'] as num) > 1.0) e
  ];
  stdout.writeln('\n-- contrafactuais, rodados pela cascata '
      '(${comVao.length} com vão a fechar) --');
  void linha(String nome, String chaveM, String chaveF) {
    final ms = [
      for (final e in comVao)
        if (e[chaveM] != null && (e[chaveM] as num).toDouble().isFinite)
          (e[chaveM] as num).toDouble()
    ];
    final fs = [
      for (final e in comVao)
        if (e[chaveF] != null && (e[chaveF] as num).toDouble().isFinite)
          (e[chaveF] as num).toDouble()
    ];
    if (ms.isEmpty) {
      stdout.writeln('  ${nome.padRight(28)} — sem medida');
      return;
    }
    final fecha = comVao
        .where((e) =>
            e[chaveM] != null &&
            (e[chaveM] as num) >= (e['mNecessario'] as num))
        .length;
    stdout.writeln('  ${nome.padRight(28)} m=${_mx(_mediana(ms)!)}  '
        'fecha ${_pc(_mediana(fs) ?? 0).padLeft(7)} do vão  '
        '(fecha tudo em $fecha de ${ms.length})');
  }

  linha('freio desligado', 'mSemFreio', 'fechaSemFreio');
  linha('freio só no crescimento real', 'mCrescimentoReal',
      'fechaCrescimentoReal');
  linha('sem convergência do ROIC', 'mSemConvergencia', 'fechaSemConvergencia');
  linha('freio sem o teto de 95%', 'mSemTeto', 'fechaSemTeto');

  // Quantos passes a volta veredito-taxa consumiu (decisão 51).
  final passes = <int, int>{};
  var instaveis = 0;
  for (final e in l) {
    final p = e['passesDoVeredito'];
    if (p is int) passes[p] = (passes[p] ?? 0) + 1;
    if (e['vereditoInstavel'] == true) instaveis++;
  }
  if (passes.isNotEmpty) {
    final chaves = passes.keys.toList()..sort();
    stdout.writeln('\n-- passes do veredito da perpetuidade --');
    for (final k in chaves) {
      stdout.writeln('  $k ${k == 1 ? "passe" : "passes"}: ${passes[k]}');
    }
    stdout.writeln('  não estabilizaram no teto: $instaveis');
  }

  // A convenção de caixa não é contrafactual de freio: é a de **antes** da
  // decisão 48, e mede o que o meio de ano vale no universo. Vai como razão
  // pura, sem "fração fechada", porque ela já entrou em produção.
  final fim = [
    for (final e in l)
      if (e['mFimDeAno'] != null && (e['mFimDeAno'] as num).toDouble().isFinite)
        (e['mFimDeAno'] as num).toDouble()
  ];
  if (fim.isNotEmpty) {
    final ordenado = [...fim]..sort();
    stdout.writeln('\n-- o que a convenção de meio de ano vale --');
    stdout.writeln('  justo(fim de ano) ÷ justo(produção): '
        'p10=${_mx(ordenado[(ordenado.length * 0.1).floor()])}  '
        'mediana=${_mx(_mediana(fim)!)}  '
        'p90=${_mx(ordenado[(ordenado.length * 0.9).floor()])}  '
        '(n=${fim.length})');
    stdout.writeln('  ou seja, o meio de ano levanta o preço justo em '
        '${_pc(1 / _mediana(fim)! - 1)} na mediana');
  }

  // O teto de retenção é o único contrafactual que pode DERRUBAR o valor: sem
  // ele a retenção passa de 100% e o fluxo do ano fica negativo.
  final semTeto = l
      .where((e) => e['mSemTeto'] != null && (e['mSemTeto'] as num) < 0.995)
      .toList();
  stdout.writeln('\n-- quem o teto de 95% está segurando --');
  stdout.writeln('  ativos que perdem valor sem o teto: ${semTeto.length}');
  semTeto.sort((a, b) =>
      (a['mSemTeto'] as num).compareTo(b['mSemTeto'] as num));
  for (final e in semTeto.take(10)) {
    stdout.writeln('    ${(e['ticker'] as String).padRight(7)} '
        'm=${_mx((e['mSemTeto'] as num).toDouble()).padLeft(7)}  '
        'retenção ano 1=${_pc((e['retencaoAno1'] as num).toDouble())}  '
        'ROIC=${_pc((e['retornoDaBase'] as num).toDouble())}  '
        'g=${_pc((e['crescimento'] as num).toDouble())}');
  }

  final aliq = col('aliquotaEstrutural');
  if (aliq.isNotEmpty) {
    stdout.writeln('\n-- alíquota estrutural aplicada (via da firma) --');
    stdout.writeln('  mediana=${_pc(_mediana(aliq)!)} contra '
        '${_pc(ValuationParameters.statutoryTaxRate)} estatutários  '
        '(n=${aliq.length})');
  }
}
