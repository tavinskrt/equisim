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

const _saida = 'docs/validacao/perpetuidade.json';

/// O peso clássico de Blume: dois terços do beta do ativo, um terço do
/// mercado.
const _blume = 0.67;

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
String _n(double? v, [int c = 3]) => v == null ? '—' : v.toStringAsFixed(c);

/// Os mesmos insumos com as imposições de equilíbrio do B15.
ValuationInputs _impor(
  ValuationInputs b, {
  double? pesoDoBeta,
  double? alavancagem,
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
      terminalBetaWeightOverride: pesoDoBeta,
      terminalLeverageOverride: alavancagem,
    );

Future<void> main() async {
  final c = await Congelado.montar();
  try {
    // --- Passo 1: a montagem de produção, e a alavancagem de cada ativo ----
    final base = <String, ValuationResult>{};
    final insumosDe = <String, ValuationInputs>{};
    final setorDe = <String, String>{};
    final avaliadas = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final insumos = prep.unwrap();
      final r = ValuationCascade.evaluate(insumos);
      avaliadas[t] = r.valueOrNull;
      if (r.isErr) continue;
      base[t.value] = r.unwrap();
      insumosDe[t.value] = insumos;
      final s = insumos.sectorKey;
      if (s != null && s.isNotEmpty) setorDe[t.value] = s;
    }
    stderr.writeln('');

    final divergentes = await c.conferirContraGabarito(avaliadas);

    // --- A mediana de alavancagem de cada setor, hoje ----------------------
    //
    // `D/E` do que o motor avalia, por setor da B3. É a alternativa que o item
    // propõe para o estado estacionário, e ela sai do dado que o projeto tem.
    double? deDe(ValuationResult r) {
      final s = r.diagnostics?.equityShare;
      if (s == null || s <= 0 || s > 1.5) return null;
      return (1 - s) / s;
    }

    final porSetor = <String, List<double>>{};
    for (final e in base.entries) {
      final s = setorDe[e.key];
      final de = deDe(e.value);
      if (s == null || de == null) continue;
      (porSetor[s] ??= []).add(de);
    }
    final medianaDoSetor = <String, double>{
      for (final e in porSetor.entries)
        if (e.value.length >= 3) e.key: _mediana(e.value)!,
    };

    // --- Passo 2: as duas alternativas -------------------------------------
    final linhas = <Map<String, dynamic>>[];
    for (final e in base.entries) {
      final insumos = insumosDe[e.key]!;
      final d = e.value.diagnostics;
      final alvo = medianaDoSetor[setorDe[e.key] ?? ''];

      double? justo(ValuationInputs x) {
        final r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().fairValue.reais : null;
      }

      double? taxaTerminal(ValuationInputs x) {
        final r = ValuationCascade.evaluate(x);
        return r.isOk ? r.unwrap().diagnostics?.terminalDiscountRate : null;
      }

      final comBlume = _impor(insumos, pesoDoBeta: _blume);
      final comSetor =
          alvo == null ? null : _impor(insumos, alavancagem: alvo);

      linhas.add({
        'ticker': e.key,
        'setor': setorDe[e.key],
        'modelo': e.value.model.name,
        'beta': insumos.capm.beta,
        'justo': e.value.fairValue.reais,
        'descontoTerminal': d?.terminalDiscountRate,
        'keTerminal': d?.terminalCostOfEquity,
        'pesoEquityHoje': d?.equityShare,
        'pesoEquityTerminal': d?.terminalEquityShare,
        'deHoje': deDe(e.value),
        // A mesma guarda de `deDe`: participação não positiva não tem `D/E`, e
        // dividir por ela devolveria `Infinity`, que o JSON não serializa.
        'deTerminal': (d?.terminalEquityShare == null ||
                d!.terminalEquityShare! <= 0)
            ? null
            : (1 - d.terminalEquityShare!) / d.terminalEquityShare!,
        'deMedianaDoSetor': alvo,
        'justoComBlume': justo(comBlume),
        'descontoTerminalComBlume': taxaTerminal(comBlume),
        'justoComSetor': comSetor == null ? null : justo(comSetor),
        'descontoTerminalComSetor':
            comSetor == null ? null : taxaTerminal(comSetor),
      });
    }

    File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'medidoEm': hojeCongelado.toIso8601String().substring(0, 10),
        'conferidoContraOGabarito': divergentes?.length,
        'pesoDeBlume': _blume,
        'medianaDeAlavancagemPorSetor': medianaDoSetor,
        'ativos': linhas,
      }),
    );
    _imprimir(linhas, medianaDoSetor, divergentes);
    stderr.writeln('\nescrito $_saida (${linhas.length})');
  } finally {
    await c.ctx.dispose();
  }
}

void _imprimir(
  List<Map<String, dynamic>> l,
  Map<String, double> medianaDoSetor,
  List<String>? divergentes,
) {
  if (divergentes == null) {
    stdout.writeln('\n!! sem gabarito para conferir');
  } else if (divergentes.isNotEmpty) {
    stdout.writeln('\n!! a montagem DIVERGE do gabarito em '
        '${divergentes.length} ativo(s) — os números abaixo não valem');
  } else {
    stdout.writeln('\nmontagem idêntica à do gabarito.');
  }

  List<double> col(String k, {bool Function(Map<String, dynamic>)? onde}) => [
        for (final e in l)
          if (onde == null || onde(e))
            if (e[k] != null && (e[k] as num).toDouble().isFinite)
              (e[k] as num).toDouble(),
      ];

  final resolvidos = l.where((e) => e['deTerminal'] != null).toList();
  stdout.writeln('\n=== B15 — A PERPETUIDADE ===');
  stdout.writeln('avaliados: ${l.length}   '
      'com taxas resolvidas: ${resolvidos.length}');

  stdout.writeln('\n-- a alavancagem D/E --');
  for (final (nome, k) in [
    ('hoje', 'deHoje'),
    ('no ano N (o do modelo)', 'deTerminal'),
    ('mediana do setor, hoje', 'deMedianaDoSetor'),
  ]) {
    final v = col(k);
    stdout.writeln('  ${nome.padRight(24)} p25 ${_n(_quantil(v, .25), 2)}  '
        'mediana ${_n(_mediana(v), 2)}  p75 ${_n(_quantil(v, .75), 2)}  '
        '(n=${v.length})');
  }
  final pares = [
    for (final e in resolvidos)
      if (e['deHoje'] != null)
        (e['deTerminal'] as num).toDouble() - (e['deHoje'] as num).toDouble(),
  ];
  stdout.writeln('  o ano N contra hoje: mediana ${_n(_mediana(pares), 2)}, '
      'sobe em ${pares.where((x) => x > 0).length} de ${pares.length}');

  stdout.writeln('\n-- mediana de D/E por setor da B3 --');
  for (final e in medianaDoSetor.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    stdout.writeln('  ${e.key.padRight(32)} ${_n(e.value, 2)}');
  }

  stdout.writeln('\n-- o efeito de convergir o beta (Blume, w = $_blume) --');
  _efeito(l, 'justoComBlume', 'descontoTerminalComBlume');

  stdout.writeln('\n-- o efeito de impor a alavancagem mediana do setor --');
  _efeito(l, 'justoComSetor', 'descontoTerminalComSetor');
}

void _efeito(List<Map<String, dynamic>> l, String justoK, String taxaK) {
  final razoes = <double>[];
  final deltaTaxa = <double>[];
  var some = 0;
  for (final e in l) {
    final a = (e['justo'] as num?)?.toDouble();
    final b = (e[justoK] as num?)?.toDouble();
    final ta = (e['descontoTerminal'] as num?)?.toDouble();
    final tb = (e[taxaK] as num?)?.toDouble();
    if (b == null) {
      some++;
      continue;
    }
    if (a != null && a.abs() > 1e-9) razoes.add(b / a - 1);
    if (ta != null && tb != null) deltaTaxa.add(tb - ta);
  }
  stdout.writeln('  taxa de equilíbrio: mediana ${_pc(_mediana(deltaTaxa))}  '
      'p10 ${_pc(_quantil(deltaTaxa, .1))}  p90 ${_pc(_quantil(deltaTaxa, .9))}');
  stdout.writeln('  preço justo:        mediana ${_pc(_mediana(razoes))}  '
      'p10 ${_pc(_quantil(razoes, .1))}  p90 ${_pc(_quantil(razoes, .9))}  '
      '(sobe em ${razoes.where((x) => x > 0).length} de ${razoes.length})');
  if (some > 0) stdout.writeln('  deixam de ser avaliados: $some');
}
