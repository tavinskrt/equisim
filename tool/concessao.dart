// D8 — a perpetuidade aplicada a contrato que acaba.
//
// **A pergunta.** O valor terminal do motor é perpétuo para todo ativo. Uma
// concessão — rodovia, transmissão, saneamento, aeroporto — tem prazo, e no
// fim dele o ativo reverte ao poder concedente. Descontar fluxo perpétuo de um
// contrato que acaba em doze anos não é aproximação, é outra empresa.
//
// **O que a fonte não dá.** Prazo de concessão. Não há campo, e não haveria
// como haver: uma concessionária tem dezenas de contratos com vencimentos
// diferentes.
//
// **O que ela dá.** A base de ativos e a amortização anual. Numa concessão o
// ativo é registrado como intangível e amortizado **ao longo do prazo do
// contrato** — de modo que `(imobilizado + intangível) ÷ D&A` é a vida
// remanescente média da base, e numa concessionária ela É o prazo médio
// remanescente. Em empresa comum a mesma razão mede vida útil de máquina, que
// é outra coisa; por isso a medida sozinha não classifica nada, e a
// classificação vem do setor.
//
// Uso:
//   dart run tool/concessao.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

String _pc(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// Fração do valor terminal perpétuo que sobra ao truncá-lo em [anos].
///
/// ```
/// VT_finito / VT_perpétuo = 1 − ((1 + g) / (1 + r))^anos
/// ```
///
/// É a soma de uma progressão geométrica: a perpetuidade é a série infinita, e
/// truncá-la remove a cauda, que vale `((1+g)/(1+r))^anos` do total.
double fracaoQueSobra({
  required double anos,
  required double g,
  required double r,
}) {
  if (!anos.isFinite || anos <= 0) return 0.0;
  if (r <= g) return 1.0;
  final cauda = math.pow((1 + g) / (1 + r), anos).toDouble();
  final v = 1 - cauda;
  return v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 1.0;
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
      final r = ValuationCascade.evaluate(inputs);
      if (r.isErr) continue;
      final v = r.unwrap();
      final d = v.diagnostics!;

      final pub = PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      if (pub.isEmpty) continue;

      // Vida remanescente da base, medida na mediana dos exercícios: um ano
      // isolado com baixa/reavaliação distorce a razão.
      final vidas = <double>[];
      for (final s in pub) {
        final base = (s.propertyPlantEquipment ?? 0) + (s.intangibleAssets ?? 0);
        final da = s.depreciationAndAmortization;
        if (da == null || da <= 0 || base <= 0) continue;
        final anos = base / da;
        if (anos.isFinite && anos > 0 && anos < 200) vidas.add(anos);
      }

      saida.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'subsetor': inputs.industry,
        'via': v.model.name,
        'justo': v.fairValue.reais,
        'preco': inputs.marketPrice,
        'pesoTerminal': d.terminalShare,
        'crescimentoPerpetuo': d.growthRate,
        'descontoTerminal': d.terminalDiscountRate,
        'vidaRemanescente': _mediana(vidas),
        'exerciciosComVida': vidas.length,
        'intangivel': pub.last.intangibleAssets,
        'imobilizado': pub.last.propertyPlantEquipment,
        // O que o terminal promete: excedente de retorno preservado na
        // perpetuidade. Num contrato com prazo, ele é a promessa mais forte
        // que o motor faz — e a que o contrato mais claramente nega.
        'moat': d.moatApplied,
        'lambda': d.terminalRetainedSpread,
        'retornoTerminal': d.terminalReturnOnCapital,
      });
    }
    stderr.writeln('');

    File('docs/validacao/concessao.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(saida),
    );
    _imprimir(saida);
    stderr.writeln('\nescrito docs/validacao/concessao.json (${saida.length})');
  } finally {
    await ctx.dispose();
  }
}

/// Subsetores que operam sob contrato de prazo determinado no Brasil.
///
/// **É classificação, não parâmetro.** Nenhum número sai daqui; o que sai é a
/// pergunta "este negócio tem data para acabar?", e ela se responde pelo
/// rótulo da fonte.
const _termosDeConcessao = [
  'energia eletrica',
  'agua e saneamento',
  'exploracao de rodovias',
  'transporte ferroviario',
  'aeroportu',
  'concessao',
  'servicos de transporte',
];

bool _souConcessao(Map<String, dynamic> e) {
  final sub = _normalizar((e['subsetor'] as String?) ?? '');
  final setor = _normalizar((e['setor'] as String?) ?? '');
  if (setor == 'saneamento' || setor == 'infraestrutura') return true;
  for (final t in _termosDeConcessao) {
    if (sub.contains(t)) return true;
  }
  return false;
}

String _normalizar(String v) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final c in v.toLowerCase().runes) {
    final ch = String.fromCharCode(c);
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i].toLowerCase() : ch);
  }
  return b.toString();
}

void _imprimir(List<Map<String, dynamic>> l) {
  stdout.writeln('\n=== D8 — A PERPETUIDADE SOBRE CONTRATO COM PRAZO — '
      '${l.length} ===\n');

  // --- 1. O indicador que parecia servir, e não serve ---------------------
  final concessoes = l.where(_souConcessao).toList();
  final resto = l.where((e) => !_souConcessao(e)).toList();
  List<double> vidas(List<Map<String, dynamic>> xs) => [
        for (final e in xs)
          if (e['vidaRemanescente'] != null)
            (e['vidaRemanescente'] as num).toDouble()
      ];
  final vc = vidas(concessoes)..sort();
  final vr = vidas(resto)..sort();
  stdout.writeln('-- (imobilizado + intangível) ÷ D&A identifica concessão? --');
  if (vc.isNotEmpty && vr.isNotEmpty) {
    stdout.writeln('  concessionárias: mediana=${_mediana(vc)!.toStringAsFixed(1)} '
        'anos  p10=${vc[(vc.length * 0.1).floor()].toStringAsFixed(1)}  '
        'p90=${vc[(vc.length * 0.9).floor()].toStringAsFixed(1)}  (n=${vc.length})');
    stdout.writeln('  as demais:       mediana=${_mediana(vr)!.toStringAsFixed(1)} '
        'anos  p10=${vr[(vr.length * 0.1).floor()].toStringAsFixed(1)}  '
        'p90=${vr[(vr.length * 0.9).floor()].toStringAsFixed(1)}  (n=${vr.length})');
    // Sobreposição: fração das concessionárias dentro do intervalo central das
    // demais. Alta sobreposição = o indicador não distingue.
    final q1 = vr[(vr.length * 0.25).floor()];
    final q3 = vr[(vr.length * 0.75).floor()];
    final dentro = vc.where((x) => x >= q1 && x <= q3).length;
    stdout.writeln('  concessionárias dentro do miolo das demais '
        '(${q1.toStringAsFixed(1)}–${q3.toStringAsFixed(1)} anos): '
        '$dentro de ${vc.length}');
  }

  // --- 2. A exposição, que existe independentemente do indicador ----------
  stdout.writeln('\n-- exposição: quem opera sob prazo --');
  stdout.writeln('  ativos em setor de concessão: ${concessoes.length} de '
      '${l.length}');
  final pesos = [
    for (final e in concessoes)
      if (e['pesoTerminal'] != null) (e['pesoTerminal'] as num).toDouble()
  ];
  if (pesos.isNotEmpty) {
    stdout.writeln('  peso do terminal neles: mediana=${_pc(_mediana(pesos)!)}  '
        'acima de 50%: ${pesos.where((x) => x > 0.5).length}');
  }
  final comMoat = concessoes.where((e) => e['moat'] == true).toList();
  stdout.writeln('  **com excedente de retorno preservado na perpetuidade: '
      '${comMoat.length}**');
  for (final e in comMoat) {
    stdout.writeln('    ${(e['ticker'] as String).padRight(7)} '
        'λ=${((e['lambda'] as num?) ?? 0).toStringAsFixed(4)}  '
        'terminal=${_pc(((e['pesoTerminal'] as num?) ?? 0).toDouble())}  '
        '${e['subsetor']}');
  }

  // --- 3. O tamanho do que não se pode corrigir sem o prazo ---------------
  stdout.writeln('\n-- se o contrato acabasse em N anos, quanto do preço '
      'justo sobraria --');
  for (final anos in [10.0, 20.0, 30.0]) {
    final efeitos = <double>[];
    for (final e in concessoes) {
      final g = e['crescimentoPerpetuo'] as num?;
      final r = e['descontoTerminal'] as num?;
      final peso = e['pesoTerminal'] as num?;
      if (g == null || r == null || peso == null) continue;
      final sobra = fracaoQueSobra(
        anos: anos,
        g: g.toDouble(),
        r: r.toDouble(),
      );
      efeitos.add(1 + peso.toDouble() * (sobra - 1));
    }
    if (efeitos.isEmpty) continue;
    stdout.writeln('  ${anos.toStringAsFixed(0).padLeft(2)} anos → '
        'preço justo × ${_mediana(efeitos)!.toStringAsFixed(2)} na mediana  '
        '(n=${efeitos.length})');
  }
}
