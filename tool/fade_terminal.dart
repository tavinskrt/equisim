// O degrau da vantagem competitiva, medido antes de ser trocado.
//
// **Por que este utilitário existe.** A [decisão 35](../docs/decisoes/035-dcf-reverso-e-regressao-condicional.md)
// tirou do decaimento contínuo de `RONIC` o argumento que ele tinha: o terminal
// **não** é a causa do viés de nível, e trocá-lo não conserta o nível. A mesma
// decisão diz que quem propuser a troca depois dela precisa de outro argumento.
//
// **O outro argumento é este, e ele é medível:** a exceção de vantagem
// competitiva é um **degrau**. Quem passa nas cinco condições recebe
// `r_∞ + 0,30·(ROIC_ciclo − r_∞)`; quem falha em uma recebe `r_∞`. Duas
// empresas com rentabilidade praticamente igual, uma de cada lado do corte,
// saem com preços justos que diferem em dezenas de por cento — e a diferença
// não vem da economia delas, vem de onde o limiar caiu.
//
// É defeito da mesma família do que a [decisão 34](../docs/decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
// corrigiu na fronteira das vias: preço justo descontínuo numa grandeza
// contínua.
//
// **O que se mede aqui:**
//
//   1. O tamanho do degrau — quanto o preço justo salta entre `λ = 0` e
//      `λ = 0,30`, por ativo, e quanto disso está concentrado perto do corte.
//   2. A resposta do preço justo a `λ` ao longo de toda a faixa, para saber se
//      o degrau é a única descontinuidade.
//   3. Que `λ` a **persistência medida** do próprio ativo sugeriria, contra o
//      0,30 fixo. Se o `λ` estimado ficasse sempre perto de 0,30, a troca seria
//      cosmética e não vale as semanas.
//
// A persistência é estimada por AR(1) sobre o excedente `ROIC_t − r_∞`. Com
// oito a dezesseis pontos o estimador é enviesado para baixo — o viés de
// Kendall é da ordem de `−(1+3φ)/n` —, então o número **não** é usado como
// verdade: ele entra como ordem de grandeza, e o relatório diz isso.
//
// Uso:
//   dart run tool/fade_terminal.dart
//   dart run tool/fade_terminal.dart --limit 30
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 4);

/// Fração do excedente preservada na perpetuidade, na grade da varredura.
///
/// `0` é o terminal neutro de hoje; `0,30` é o que a exceção concede a quem
/// passa. O resto da grade existe para mostrar a forma da resposta.
const _grid = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0];

double? _fairValue(ValuationInputs inputs, double? terminal) {
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
    terminalReturnOverride: terminal,
  ));
  return r.isOk ? r.unwrap().fairValue.reais : null;
}

/// Persistência do excedente por AR(1), sem intercepto forçado.
///
/// Devolve `null` com menos de quatro variações — abaixo disso a inclinação
/// não é identificável e um número saindo dali seria ruído com casas decimais.
({double phi, double r2, int n})? _persistence(List<double> excess) {
  if (excess.length < 5) return null;
  final x = excess.sublist(0, excess.length - 1);
  final y = excess.sublist(1);
  final f = Inference.ols(x, y);
  if (f == null || !f.slope.isFinite) return null;
  return (phi: f.slope, r2: f.r2, n: x.length);
}

Future<void> main(List<String> args) async {
  final limitIndex = args.indexOf('--limit');
  final limit = limitIndex >= 0 ? int.tryParse(args[limitIndex + 1]) ?? 0 : 0;

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (limit > 0 && universe.length > limit) {
      universe = universe.sublist(0, limit);
    }
    stderr.writeln('universo: ${universe.length} ativos');

    final output = <Map<String, dynamic>>[];
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
        asOf: _today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      );
      if (prep.isErr) continue;

      final inputs = prep.unwrap();
      final baseResult = ValuationCascade.evaluate(inputs);
      if (baseResult.isErr) continue;
      final base = baseResult.unwrap();
      final rInf = base.diagnostics!.terminalDiscountRate;

      final lane = base.model == ValuationModel.dcfFcff
          ? ValuationLane.firm
          : ValuationLane.shareholder;
      final pub = PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      final series = CapitalSeries.build(pub, lane);
      final cycle = series.cycleReturn(window: ValuationParameters.cycleWindow);
      if (cycle == null || !cycle.isFinite) continue;

      final e0 = cycle - rInf;

      // Excedente por exercício, com o ano — a regressão de persistência só
      // pareia anos adjacentes, e sem o ano não teria como saber.
      final excesses = [
        for (final r in series.returns)
          if (r.value.isFinite) (year: r.year, excess: r.value - rInf),
      ];

      // O veredito completo, com as condições que barram e os dois valores de
      // persistência lado a lado.
      final verdict = GrowthGuards.residualMoat(
        cycleReturn: cycle,
        terminalDiscountRate: rInf,
        externalCapitalRatio: GrowthGuards.externalCapitalRatio(series),
        periods: series.length,
        excessReturns: excesses,
        projectionYears: inputs.projectionYears,
      );

      final curve = <String, double?>{};
      for (final lambda in _grid) {
        curve[lambda.toStringAsFixed(1)] =
            _fairValue(inputs, e0 > 0 ? rInf + lambda * e0 : null);
      }

      final noExcess = curve['0.0'];
      final withDefault = curve['0.3'];
      final jump = (noExcess != null &&
              withDefault != null &&
              noExcess > 0)
          ? withDefault / noExcess - 1
          : null;

      final p = _persistence([for (final e in excesses) e.excess]);
      final positiveYears = excesses.where((x) => x.excess > 0).length /
          (excesses.isEmpty ? 1 : excesses.length);

      output.add({
        'ticker': ticker.value,
        'setor': inputs.sectorKey,
        'via': lane.name,
        'preco': inputs.marketPrice,
        'justoProducao': base.fairValue.reais,
        'potencial': base.upside,
        'rInfinito': rInf,
        'roicCiclo': cycle,
        'excedente': e0,
        'pesoTerminal': base.diagnostics!.terminalShare,
        'moatConcedido': base.diagnostics!.moatApplied,
        'lambdaAplicado': base.diagnostics!.terminalRetainedSpread,
        'phiCru': verdict.rawPersistence,
        'phiAplicado': verdict.persistence,
        'bloqueios': [for (final b in verdict.blocks) b.key],
        // A única fronteira de nível que restou: o excedente ser positivo.
        'folgaPorExcedente': e0,
        'curva': curve,
        'saltoDoDegrau': jump,
        'persistenciaPhi': p?.phi,
        'persistenciaR2': p?.r2,
        'persistenciaN': p?.n,
        'lambdaPorPersistencia':
            p == null ? null : _power(p.phi, inputs.projectionYears),
        'fracaoAnosComExcedente': positiveYears,
      });
    }
    stderr.writeln('');

    File('docs/validacao/fade_terminal.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(output),
    );
    _printReport(output);
    stderr.writeln('\nescrito docs/validacao/fade_terminal.json '
        '(${output.length} ativos)');
  } finally {
    await ctx.dispose();
  }
}

/// `phi^n`, com `phi` negativo tratado como ausência de persistência.
///
/// Excedente que troca de sinal de ano para ano não é vantagem que decai — é
/// oscilação, e elevar um número negativo a dez devolveria persistência
/// positiva por artefato de paridade.
double _power(double phi, int n) {
  if (phi <= 0) return 0;
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= phi;
  }
  return r;
}

void _printReport(List<Map<String, dynamic>> rows) {
  double? med(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  String pc(double? x) =>
      x == null ? '—' : '${(x * 100).toStringAsFixed(1)}%';

  final withExcess =
      rows.where((e) => (e['excedente'] as num) > 0).toList();
  final granted = rows.where((e) => e['moatConcedido'] == true).toList();

  stdout.writeln('\n=== O DEGRAU DA VANTAGEM COMPETITIVA — '
      '${rows.length} avaliados ===\n');
  stdout.writeln('com excedente positivo (ROIC do ciclo > r_infinito): '
      '${withExcess.length}');
  stdout.writeln('exceção concedida hoje:                              '
      '${granted.length}');

  // --- 1. O tamanho do degrau ---
  final jumps = [
    for (final e in withExcess)
      if (e['saltoDoDegrau'] != null) (e['saltoDoDegrau'] as num).toDouble(),
  ];
  stdout.writeln('\n-- tamanho do degrau (justo em λ=0,30 contra λ=0) --');
  if (jumps.isNotEmpty) {
    final s = [...jumps]..sort();
    stdout.writeln('  n=${s.length}  p25=${pc(s[s.length ~/ 4])}  '
        'mediana=${pc(med(s))}  p75=${pc(s[3 * s.length ~/ 4])}  '
        'máx=${pc(s.last)}');
    stdout.writeln('  acima de 10%: ${s.where((x) => x > 0.10).length}   '
        'acima de 25%: ${s.where((x) => x > 0.25).length}');
  }

  // --- 2. Quem está perto do corte ---
  //
  // A folga é a distância ao corte que menos falta. Perto de zero, dois ativos
  // economicamente iguais caem em lados diferentes.
  stdout.writeln('\n-- ativos na vizinhança do corte (folga em ±3 p.p.) --');
  final neighbors = [
    for (final e in withExcess)
      if (_margin(e) != null && _margin(e)!.abs() <= 0.03) e,
  ]..sort((a, b) => _margin(a)!.compareTo(_margin(b)!));
  stdout.writeln('  ${neighbors.length} ativos');
  for (final e in neighbors) {
    stdout.writeln('    ${(e['ticker'] as String).padRight(7)} '
        'folga=${(_margin(e)! * 100).toStringAsFixed(2).padLeft(6)} p.p.  '
        'concedido=${e['moatConcedido'] == true ? 'sim' : 'não'}  '
        'salto=${pc(e['saltoDoDegrau'] as double?).padLeft(7)}  '
        'ROIC=${pc(e['roicCiclo'] as double?)}');
  }

  // --- 3. O lambda que a produção passou a aplicar ---
  final applied = [
    for (final e in rows)
      if (e['lambdaAplicado'] != null && (e['lambdaAplicado'] as num) > 0)
        (e['lambdaAplicado'] as num).toDouble(),
  ];
  stdout.writeln('\n-- lambda EM PRODUÇÃO (decisão 36) --');
  stdout.writeln('  ativos com preservação > 0: ${applied.length} de '
      '${rows.length}   (o degrau concedia a 8)');
  if (applied.isNotEmpty) {
    final s = [...applied]..sort();
    stdout.writeln('  λ: mediana=${med(s)!.toStringAsFixed(4)}  '
        'p75=${s[3 * s.length ~/ 4].toStringAsFixed(4)}  '
        'p90=${s[9 * s.length ~/ 10].toStringAsFixed(4)}  '
        'máx=${s.last.toStringAsFixed(4)}   contra 0,3000 fixo');
    stdout.writeln('  acima de 0,30: ${s.where((x) => x > 0.30).length}');
  }

  // --- 4. Que lambda a persistência crua sugeriria ---
  final phis = [
    for (final e in withExcess)
      if (e['persistenciaPhi'] != null)
        (e['persistenciaPhi'] as num).toDouble(),
  ];
  final lambdas = [
    for (final e in withExcess)
      if (e['lambdaPorPersistencia'] != null)
        (e['lambdaPorPersistencia'] as num).toDouble(),
  ];
  stdout.writeln('\n-- persistência medida do excedente (AR(1)) --');
  if (phis.isNotEmpty) {
    final s = [...phis]..sort();
    stdout.writeln('  φ:  n=${s.length}  p25=${s[s.length ~/ 4].toStringAsFixed(2)}  '
        'mediana=${med(s)!.toStringAsFixed(2)}  '
        'p75=${s[3 * s.length ~/ 4].toStringAsFixed(2)}');
    stdout.writeln('  φ ≤ 0 (excedente oscila em vez de decair): '
        '${s.where((x) => x <= 0).length} de ${s.length}');
  }
  if (lambdas.isNotEmpty) {
    final s = [...lambdas]..sort();
    stdout.writeln('  λ = φ^10:  mediana=${med(s)!.toStringAsFixed(3)}  '
        'p90=${s[9 * s.length ~/ 10].toStringAsFixed(3)}  '
        'contra 0,300 fixo');
    stdout.writeln('  acima de 0,30: ${s.where((x) => x > 0.30).length} de '
        '${s.length}');
  }
  final fractions = [
    for (final e in withExcess)
      (e['fracaoAnosComExcedente'] as num).toDouble(),
  ];
  if (fractions.isNotEmpty) {
    stdout.writeln('  fração de anos com excedente positivo: '
        'mediana=${med(fractions)!.toStringAsFixed(2)}');
  }
}

/// Distância à única fronteira de nível que restou: o excedente ser positivo.
double? _margin(Map<String, dynamic> e) =>
    (e['folgaPorExcedente'] as num?)?.toDouble();
