// B15 — o beta e a estrutura de capital com que a perpetuidade é descontada.
//
// **O apontamento, e o que dele sobrou.** A lente `metodo` disse em 15/09/2026
// que a taxa de equilíbrio troca só a taxa livre de risco: mesmo beta, e — na
// via da firma — o WACC com o peso e a dívida **de hoje**. Metade disso caiu
// com a [decisão 105](../docs/decisoes/105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md):
// o aplicativo passou a resolver o caminho de taxas, e a alavancagem de
// equilíbrio virou a que a própria projeção alcança no ano N. **O beta não**:
// ele é o de hoje, estimado na janela de cinco anos, e vai à perpetuidade sem
// convergir.
//
// **O que este programa mede, sobre a entrada congelada do gabarito:**
//
//   1. a alavancagem de equilíbrio que o modelo produz, contra a de hoje e
//      contra a mediana do setor da B3 — o modelo chega a um estado
//      estacionário, ou só continua a tendência da projeção?
//   2. o efeito de convergir o beta de equilíbrio em direção a 1 (Blume, com
//      `w = 0,67`) sobre a taxa e sobre o preço justo;
//   3. o efeito de impor a alavancagem mediana do setor na perpetuidade.
//
// As duas alternativas entram por **imposição de diagnóstico**, como as demais:
// elas não são do aplicativo, e medir o efeito é o que permite ao registro
// escolher.
//
// Uso:
//   dart run tool/gabarito_cascata.dart      # congela a entrada
//   dart run tool/perpetuidade.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

const _output = 'docs/validacao/perpetuidade.json';

/// O peso clássico de Blume: dois terços do beta do ativo, um terço do
/// mercado.
const _blume = 0.67;

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
String _n(double? v, [int c = 3]) => v == null ? '—' : v.toStringAsFixed(c);

/// Os mesmos insumos com as imposições de equilíbrio do B15.
ValuationInputs _impose(
  ValuationInputs b, {
  double? betaWeight,
  double? leverage,
}) =>
    ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: b.capm,
      marginOfSafety: b.marginOfSafety,
      projectionYears: b.projectionYears,
      perpetualGrowthCap: b.perpetualGrowthCap,
      sectorKey: b.sectorKey,
      industry: b.industry,
      inflation: b.inflation,
      declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
      riskFreeCurve: b.riskFreeCurve,
      officialShares: b.officialShares,
      prices: b.prices,
      isDistressed: b.isDistressed,
      unleveredBeta: b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
      creditReferenceRiskFree: b.creditReferenceRiskFree,
      declaredSharesPerUnit: b.declaredSharesPerUnit,
      terminalBetaWeightOverride: betaWeight,
      terminalLeverageOverride: leverage,
    );

Future<void> main() async {
  final c = await Frozen.build();
  try {
    // --- Passo 1: a montagem de produção, e a alavancagem de cada ativo ----
    final base = <String, ValuationResult>{};
    final inputsOf = <String, ValuationInputs>{};
    final sectorOf = <String, String>{};
    final evaluated = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${c.universe.length}   \r');
      final prep = await c.prepare(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final r = ValuationCascade.evaluate(inputs);
      evaluated[t] = r.valueOrNull;
      if (r.isErr) continue;
      base[t.value] = r.unwrap();
      inputsOf[t.value] = inputs;
      final s = inputs.sectorKey;
      if (s != null && s.isNotEmpty) sectorOf[t.value] = s;
    }
    stderr.writeln('');

    final divergent = await c.checkAgainstAnswerKey(evaluated);

    // --- A mediana de alavancagem de cada setor, hoje ----------------------
    //
    // `D/E` do que o motor avalia, por setor da B3. É a alternativa que o item
    // propõe para o estado estacionário, e ela sai do dado que o projeto tem.
    double? debtToEquityOf(ValuationResult r) {
      final s = r.diagnostics?.equityShare;
      if (s == null || s <= 0 || s > 1.5) return null;
      return (1 - s) / s;
    }

    final bySector = <String, List<double>>{};
    for (final e in base.entries) {
      final s = sectorOf[e.key];
      final debtToEquity = debtToEquityOf(e.value);
      if (s == null || debtToEquity == null) continue;
      (bySector[s] ??= []).add(debtToEquity);
    }
    final sectorMedian = <String, double>{
      for (final e in bySector.entries)
        if (e.value.length >= 3) e.key: _median(e.value)!,
    };

    // --- Passo 2: as duas alternativas -------------------------------------
    final rows = <Map<String, dynamic>>[];
    for (final e in base.entries) {
      final inputs = inputsOf[e.key]!;
      final d = e.value.diagnostics;
      final target = sectorMedian[sectorOf[e.key] ?? ''];

      double? fairValue(ValuationInputs x) {
        final r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().fairValue.reais : null;
      }

      double? terminalRate(ValuationInputs x) {
        final r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().diagnostics?.terminalDiscountRate : null;
      }

      final withBlume = _impose(inputs, betaWeight: _blume);
      final withSector =
          target == null ? null : _impose(inputs, leverage: target);

      rows.add({
        'ticker': e.key,
        'setor': sectorOf[e.key],
        'modelo': e.value.model.name,
        'beta': inputs.capm.beta,
        'justo': e.value.fairValue.reais,
        'descontoTerminal': d?.terminalDiscountRate,
        'keTerminal': d?.terminalCostOfEquity,
        'pesoEquityHoje': d?.equityShare,
        'pesoEquityTerminal': d?.terminalEquityShare,
        'deHoje': debtToEquityOf(e.value),
        // A mesma guarda de `debtToEquityOf`: participação não positiva não tem `D/E`, e
        // dividir por ela devolveria `Infinity`, que o JSON não serializa.
        'deTerminal': (d?.terminalEquityShare == null ||
                d!.terminalEquityShare! <= 0)
            ? null
            : (1 - d.terminalEquityShare!) / d.terminalEquityShare!,
        'deMedianaDoSetor': target,
        'justoComBlume': fairValue(withBlume),
        'descontoTerminalComBlume': terminalRate(withBlume),
        'justoComSetor': withSector == null ? null : fairValue(withSector),
        'descontoTerminalComSetor':
            withSector == null ? null : terminalRate(withSector),
      });
    }

    File(_output).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'medidoEm': frozenToday.toIso8601String().substring(0, 10),
        'conferidoContraOGabarito': divergent?.length,
        'pesoDeBlume': _blume,
        'medianaDeAlavancagemPorSetor': sectorMedian,
        'ativos': rows,
      }),
    );
    _printReport(rows, sectorMedian, divergent);
    stderr.writeln('\nescrito $_output (${rows.length})');
  } finally {
    await c.ctx.dispose();
  }
}

void _printReport(
  List<Map<String, dynamic>> l,
  Map<String, double> sectorMedian,
  List<String>? divergent,
) {
  if (divergent == null) {
    stdout.writeln('\n!! sem gabarito para conferir');
  } else if (divergent.isNotEmpty) {
    stdout.writeln('\n!! a montagem DIVERGE do gabarito em '
        '${divergent.length} ativo(s) — os números abaixo não valem');
  } else {
    stdout.writeln('\nmontagem idêntica à do gabarito.');
  }

  List<double> col(String k, {bool Function(Map<String, dynamic>)? where}) => [
        for (final e in l)
          if (where == null || where(e))
            if (e[k] != null && (e[k] as num).toDouble().isFinite)
              (e[k] as num).toDouble(),
      ];

  final resolved = l.where((e) => e['deTerminal'] != null).toList();
  stdout.writeln('\n=== B15 — A PERPETUIDADE ===');
  stdout.writeln('avaliados: ${l.length}   '
      'com taxas resolvidas: ${resolved.length}');

  stdout.writeln('\n-- a alavancagem D/E --');
  for (final (name, k) in [
    ('hoje', 'deHoje'),
    ('no ano N (o do modelo)', 'deTerminal'),
    ('mediana do setor, hoje', 'deMedianaDoSetor'),
  ]) {
    final v = col(k);
    stdout.writeln('  ${name.padRight(24)} p25 ${_n(_quantile(v, .25), 2)}  '
        'mediana ${_n(_median(v), 2)}  p75 ${_n(_quantile(v, .75), 2)}  '
        '(n=${v.length})');
  }
  final pairs = [
    for (final e in resolved)
      if (e['deHoje'] != null)
        (e['deTerminal'] as num).toDouble() - (e['deHoje'] as num).toDouble(),
  ];
  stdout.writeln('  o ano N contra hoje: mediana ${_n(_median(pairs), 2)}, '
      'sobe em ${pairs.where((x) => x > 0).length} de ${pairs.length}');

  stdout.writeln('\n-- mediana de D/E por setor da B3 --');
  for (final e in sectorMedian.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    stdout.writeln('  ${e.key.padRight(32)} ${_n(e.value, 2)}');
  }

  stdout.writeln('\n-- o efeito de convergir o beta (Blume, w = $_blume) --');
  _effect(l, 'justoComBlume', 'descontoTerminalComBlume');

  stdout.writeln('\n-- o efeito de impor a alavancagem mediana do setor --');
  _effect(l, 'justoComSetor', 'descontoTerminalComSetor');
}

void _effect(List<Map<String, dynamic>> l, String fairKey, String rateKey) {
  final ratios = <double>[];
  final rateDelta = <double>[];
  var some = 0;
  for (final e in l) {
    final a = (e['justo'] as num?)?.toDouble();
    final b = (e[fairKey] as num?)?.toDouble();
    final rateA = (e['descontoTerminal'] as num?)?.toDouble();
    final rateB = (e[rateKey] as num?)?.toDouble();
    if (b == null) {
      some++;
      continue;
    }
    if (a != null && a.abs() > 1e-9) ratios.add(b / a - 1);
    if (rateA != null && rateB != null) rateDelta.add(rateB - rateA);
  }
  stdout.writeln('  taxa de equilíbrio: mediana ${_pc(_median(rateDelta))}  '
      'p10 ${_pc(_quantile(rateDelta, .1))}  p90 ${_pc(_quantile(rateDelta, .9))}');
  stdout.writeln('  preço justo:        mediana ${_pc(_median(ratios))}  '
      'p10 ${_pc(_quantile(ratios, .1))}  p90 ${_pc(_quantile(ratios, .9))}  '
      '(sobe em ${ratios.where((x) => x > 0).length} de ${ratios.length})');
  if (some > 0) stdout.writeln('  deixam de ser avaliados: $some');
}
