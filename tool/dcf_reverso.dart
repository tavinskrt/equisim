// DCF reverso — o que o preço de mercado está implicando.
//
// **A pergunta.** O potencial mediano do motor está em −38%: a cascata afirma
// que o mercado inteiro está caro. Isso é viés de nível, e há três causas
// candidatas, cada uma com um conserto diferente e caro:
//
//   1. o terminal neutro (`RONIC_∞ = WACC`), que zera todo valor de franquia
//      na perpetuidade e só é dispensado pela exceção binária de vantagem
//      competitiva;
//   2. a taxa de desconto, montada sobre CDI mais prêmio parametrizado de
//      5,5 p.p. com beta de regressão crua;
//   3. as saturações conservadoras — fator de base, trava de saúde, Porta 0.
//
// Corrigir a errada custa semanas. Pior: **o conserto do terminal fecha o vão
// independentemente da causa verdadeira**, porque um retorno terminal livre
// tem graus de liberdade de sobra para absorver um erro de taxa. O resultado
// pareceria certo por fora.
//
// **O que este utilitário mede.** Para cada ativo, varre a cascata inteira em
// dois eixos, um de cada vez, e procura o valor que iguala o preço justo ao
// preço de mercado:
//
//   - `RONIC_∞` implícito — que retorno sobre capital na perpetuidade o preço
//     está pagando, e como ele se compara ao ROIC que a empresa entregou na
//     mediana do ciclo;
//   - prêmio de risco implícito — que prêmio de mercado igualaria os dois, e
//     que Ke isso produz.
//
// **A varredura é por grade antes de bissecção, de propósito.** Bissecar
// pressupõe monotonia, e a cascata tem porta de migração de via, saturação e
// piso de WACC — qualquer um deles pode produzir degrau. A grade mede a
// monotonia em vez de supô-la, e um ativo com mais de um cruzamento é
// declarado como tal em vez de receber a primeira raiz encontrada.
//
// **Identificação.** As duas causas deixam assinaturas transversais
// diferentes: erro de terminal escala com o excedente `ROIC − WACC` do ativo
// — quem tem franquia é quem o motor mais subavalia —, e erro de taxa escala
// com beta e é indiferente ao excedente. A regressão do potencial nos dois
// regressores separa as hipóteses, e ela é a saída que decide o roteiro.
//
// Uso:
//   dart run tool/dcf_reverso.dart              # universo inteiro
//   dart run tool/dcf_reverso.dart PETR4 VALE3  # só estes
//   dart run tool/dcf_reverso.dart --limit 20   # os 20 primeiros
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';
import 'validation/regression.dart';

/// Data de referência. Fixa, para que a reexecução reproduza o relatório.
final _today = DateTime(2026, 9, 4);

/// Grade do retorno terminal, log-espaçada entre 0,5% e 200% ao ano.
///
/// Log e não linear porque a grandeza é um retorno sobre capital: a diferença
/// entre 8% e 10% importa, entre 150% e 152% não.
List<double> _gridRonic() {
  const n = 61;
  const lo = 0.005, hi = 2.0;
  final step = (math.log(hi) - math.log(lo)) / (n - 1);
  return [for (var i = 0; i < n; i++) math.exp(math.log(lo) + step * i)];
}

/// Grade do prêmio de risco, de 0 a 25% em passos de 0,5 p.p.
List<double> _premiumGrid() => [for (var i = 0; i <= 50; i++) i * 0.005];

/// Grade do deslocamento paralelo da taxa livre de risco, de −13 a +5 p.p.
///
/// **Por que este eixo existe, e por que ele é o decisivo.** O prêmio de risco
/// não é o piso do desconto: `CostOfCapital.wacc` não deixa o WACC cair abaixo
/// da própria taxa livre de risco. Zerar o prêmio leva o desconto ao CDI e
/// para ali — de modo que uma varredura só no prêmio não consegue distinguir
/// "o prêmio está alto" de "a taxa livre de risco está alta". Deslocar as
/// duas taxas juntas, a corrente e a de equilíbrio, é o que mede o nível do
/// custo de capital sem esbarrar naquele piso.
///
/// O limite inferior chega perto de zerar a taxa de equilíbrio de 9,40%: é
/// deliberadamente absurdo, porque o interesse é saber **se existe** taxa que
/// alcance o preço, e não propor uma.
List<double> _gridRf() => [for (var i = 0; i <= 72; i++) -0.13 + i * 0.0025];

/// Resultado de uma varredura em um eixo.
class Sweep {
  /// Valor que iguala preço justo a preço de mercado. `null` sem raiz única.
  final double? implied;

  /// Como o preço justo se comporta ao longo da grade.
  final String monotonicity;

  /// Quantas vezes `justo − preço` troca de sinal na grade.
  final int crossings;

  /// Preço justo na ponta inferior e na superior da grade.
  final double? fairValueMin;
  final double? fairValueMax;

  /// Pontos da grade em que a cascata não devolveu avaliação.
  final int failures;

  /// Por que não houve raiz, quando não houve.
  ///
  /// A distinção importa mais que a raiz: `fora da grade — preço acima do
  /// teto` diz que **nem retorno terminal infinito** alcança o preço, e nesse
  /// ativo o terminal está descartado como explicação do vão. `já acima do
  /// preço` é o oposto — o eixo não precisa se mover.
  final String situation;

  const Sweep({
    required this.implied,
    required this.monotonicity,
    required this.crossings,
    required this.fairValueMin,
    required this.fairValueMax,
    required this.failures,
    required this.situation,
  });

  Map<String, dynamic> toJson() => {
        'implicito': implied,
        'monotonia': monotonicity,
        'cruzamentos': crossings,
        'justoMin': fairValueMin,
        'justoMax': fairValueMax,
        'falhas': failures,
        'situacao': situation,
      };
}

/// Classifica uma varredura sem raiz pela posição da grade contra o preço.
String _situation(double? fairValueMin, double? fairValueMax, double price, int crossCount) {
  if (fairValueMin == null || fairValueMax == null) return 'sem avaliação';
  if (crossCount == 1) return 'raiz única';
  if (crossCount > 1) return 'múltiplas raízes';
  final isGreater = fairValueMin > fairValueMax ? fairValueMin : fairValueMax;
  final smaller = fairValueMin > fairValueMax ? fairValueMax : fairValueMin;
  if (isGreater < price) return 'fora da grade — preço acima do teto';
  if (smaller > price) return 'fora da grade — justo acima do preço em toda a grade';
  return 'sem cruzamento';
}

/// Avalia e devolve o preço justo, ou `null` quando a cascata recusa.
double? _fairValue(ValuationInputs inputs) {
  final r = ValuationCascade.evaluate(inputs);
  return r.isOk ? r.unwrap().fairValue.reais : null;
}

/// Varre um eixo pela grade, classifica a monotonia e refina a raiz.
///
/// - [grid]: valores a percorrer, em ordem crescente.
/// - [buildInputs]: constrói os insumos para um valor da grade.
/// - [price]: preço de mercado, o alvo da igualdade.
Sweep _sweep({
  required List<double> grid,
  required ValuationInputs Function(double) buildInputs,
  required double price,
}) {
  final xs = <double>[], fs = <double>[];
  var failures = 0;
  for (final x in grid) {
    final j = _fairValue(buildInputs(x));
    if (j == null || !j.isFinite) {
      failures++;
      continue;
    }
    xs.add(x);
    fs.add(j - price);
  }
  if (xs.length < 3) {
    return Sweep(
      implied: null,
      monotonicity: 'sem avaliação',
      crossings: 0,
      fairValueMin: null,
      fairValueMax: null,
      failures: failures,
      situation: 'sem avaliação',
    );
  }

  // Monotonia medida, com tolerância relativa ao preço: variação abaixo de
  // 0,1% do preço é ruído de ponto flutuante, não direção.
  final tol = price * 1e-3;
  var rises = false, falls = false;
  for (var i = 1; i < fs.length; i++) {
    final d = fs[i] - fs[i - 1];
    if (d > tol) rises = true;
    if (d < -tol) falls = true;
  }
  final monotonicity = (rises && falls)
      ? 'não monótona'
      : rises
          ? 'crescente'
          : falls
              ? 'decrescente'
              : 'plana';

  // Cruzamentos de zero.
  final brackets = <List<int>>[];
  for (var i = 1; i < fs.length; i++) {
    // Ponto da grade que já iguala o preço dentro da tolerância. Exigir zero
    // cravado numa diferença entre dois valores monetários calculados nunca
    // dispararia, e a bissecção teria de reencontrar por dentro uma raiz que
    // está bem debaixo do ponto.
    if (fs[i - 1].abs() < tol) {
      return _withRoot(xs[i - 1], monotonicity, 1, fs, price, failures);
    }
    if ((fs[i - 1] < 0) != (fs[i] < 0)) brackets.add([i - 1, i]);
  }
  if (brackets.length != 1) {
    return Sweep(
      implied: null,
      monotonicity: monotonicity,
      crossings: brackets.length,
      fairValueMin: fs.first + price,
      fairValueMax: fs.last + price,
      failures: failures,
      situation:
          _situation(fs.first + price, fs.last + price, price, brackets.length),
    );
  }

  // Bissecção dentro do único intervalo que muda de sinal.
  var lo = xs[brackets[0][0]], hi = xs[brackets[0][1]];
  var flo = fs[brackets[0][0]];
  for (var it = 0; it < 60; it++) {
    final mid = (lo + hi) / 2;
    final j = _fairValue(buildInputs(mid));
    if (j == null || !j.isFinite) break;
    final f = j - price;
    if ((f < 0) == (flo < 0)) {
      lo = mid;
      flo = f;
    } else {
      hi = mid;
    }
    if ((hi - lo).abs() < 1e-9) break;
  }
  return _withRoot((lo + hi) / 2, monotonicity, 1, fs, price, failures);
}

Sweep _withRoot(
  double root,
  String monotonicity,
  int crossings,
  List<double> fs,
  double price,
  int failures,
) =>
    Sweep(
      implied: root,
      monotonicity: monotonicity,
      crossings: crossings,
      fairValueMin: fs.first + price,
      fairValueMax: fs.last + price,
      failures: failures,
      situation: 'raiz única',
    );

/// Reconstrói os insumos trocando apenas o retorno terminal.
ValuationInputs _withRonic(ValuationInputs b, double ronic) => ValuationInputs(
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
      prices: b.prices,
      isDistressed: b.isDistressed,
      terminalReturnOverride: ronic,
    );

/// Reconstrói os insumos trocando apenas o prêmio de risco de mercado.
///
/// O prêmio viaja no `capm`, e `CapmInputs.withRiskFree` o preserva — de modo
/// que trocar aqui desloca **as duas** taxas, a corrente e a de equilíbrio, o
/// que é a definição de um deslocamento paralelo do custo de capital.
ValuationInputs _withPremium(ValuationInputs b, double premium) => ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: CapmInputs(
        riskFreeRate: b.capm.riskFreeRate,
        beta: b.capm.beta,
        marketPremium: premium,
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
      prices: b.prices,
      isDistressed: b.isDistressed,
    );

/// Reconstrói os insumos deslocando **as duas** taxas livres de risco.
///
/// A corrente e a de equilíbrio andam juntas: o interesse é o nível da curva,
/// e mover só uma delas mudaria a inclinação da estrutura a termo, que é outra
/// pergunta. O piso de 0,1% evita taxa negativa, que não tem leitura aqui.
ValuationInputs _withRf(ValuationInputs b, double shift) {
  double floor(double x) => x < 0.001 ? 0.001 : x;
  return ValuationInputs(
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: b.capm.withRiskFree(floor(b.capm.riskFreeRate + shift)),
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: floor(b.terminalRiskFreeRate + shift),
    prices: b.prices,
    isDistressed: b.isDistressed,
  );
}

Future<void> main(List<String> args) async {
  final limitIndex = args.indexOf('--limit');
  final limit =
      limitIndex >= 0 ? int.tryParse(args[limitIndex + 1]) ?? 0 : 0;
  final targets = [
    for (final a in args)
      if (!a.startsWith('--') && int.tryParse(a) == null) a,
  ];

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stderr.writeln('âncoras: rf=${anchors.currentRiskFreeRate.toStringAsFixed(4)} '
        'rfTerm=${anchors.riskFreeCagr.toStringAsFixed(4)} '
        'gNom=${anchors.nominalEconomyGrowth.toStringAsFixed(4)}');

    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (targets.isNotEmpty) {
      universe = universe.where((t) => targets.contains(t.value)).toList();
    }
    if (limit > 0 && universe.length > limit) {
      universe = universe.sublist(0, limit);
    }
    stderr.writeln('universo: ${universe.length} ativos');

    final gridRonic = _gridRonic();
    final premiumGrid = _premiumGrid();
    final gridRf = _gridRf();

    final output = <Map<String, dynamic>>[];
    final stopwatch = Stopwatch()..start();
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 10 == 0) {
        stderr.write('  $i/${universe.length} '
            '(${stopwatch.elapsed.inSeconds}s)      \r');
      }

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
      if (prep.isErr) {
        output.add({
          'ticker': ticker.value,
          'avaliado': false,
          'recusa': prep.failureOrNull?.message,
        });
        continue;
      }

      final inputs = prep.unwrap();
      final baseResult = ValuationCascade.evaluate(inputs);
      if (baseResult.isErr) {
        output.add({
          'ticker': ticker.value,
          'avaliado': false,
          'recusa': baseResult.failureOrNull?.message,
        });
        continue;
      }
      final base = baseResult.unwrap();
      final price = inputs.marketPrice;

      // Retorno do ciclo na via que a cascata efetivamente escolheu: comparar
      // ROIC com WACC numa e ROE com Ke na outra é a única comparação em que
      // o excedente significa a mesma coisa.
      final lane = base.model == ValuationModel.dcfFcff
          ? ValuationLane.firm
          : ValuationLane.shareholder;
      final pub = PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      final series = CapitalSeries.build(pub, lane);
      final cycleReturn =
          series.cycleReturn(window: ValuationParameters.cycleWindow);

      final ronic = _sweep(
        grid: gridRonic,
        buildInputs: (x) => _withRonic(inputs, x),
        price: price,
      );
      final premium = _sweep(
        grid: premiumGrid,
        buildInputs: (x) => _withPremium(inputs, x),
        price: price,
      );

      final rf = _sweep(
        grid: gridRf,
        buildInputs: (x) => _withRf(inputs, x),
        price: price,
      );

      // Quarto eixo, e este sai por identidade em vez de varredura: o DCF é
      // homogêneo de grau 1 no fluxo-base, então multiplicar o fluxo por `k`
      // multiplica o valor da firma por `k`. Na via do acionista o valor é o
      // próprio preço justo e o fator necessário é `preço ÷ justo`; na via da
      // firma a dívida líquida não escala junto, e o fator sai da ponte:
      //
      //   EV = E + D,  E = justo·N  =>  D por papel = justo·(1 − s)/s
      //   k = (preço + D/N) ÷ (justo + D/N)
      //
      // Varrer seria mais caro e devolveria o mesmo número.
      final s = base.diagnostics?.equityShare;
      final fairValue = base.fairValue.reais;
      double? multiplier;
      if (fairValue > 0) {
        if (lane == ValuationLane.firm && s != null && s > 0 && s <= 1) {
          final debtPerShare = fairValue * (1 - s) / s;
          multiplier = (price + debtPerShare) / (fairValue + debtPerShare);
        } else {
          multiplier = price / fairValue;
        }
      }

      final impliedKe = premium.implied == null
          ? null
          : inputs.capm.riskFreeRate + inputs.capm.beta * premium.implied!;
      final impliedTerminalRf = rf.implied == null
          ? null
          : inputs.terminalRiskFreeRate + rf.implied!;

      output.add({
        'ticker': ticker.value,
        'avaliado': true,
        'setor': inputs.sectorKey,
        'preco': price,
        'justo': base.fairValue.reais,
        'potencial': base.upside,
        'via': lane.name,
        'modelo': base.model.name,
        'desconto': base.discountRate,
        'pesoTerminal': base.diagnostics?.terminalShare,
        'participacaoEquity': base.diagnostics?.equityShare,
        'fatorBase': base.diagnostics?.baseFactor,
        'moat': base.diagnostics?.moatApplied,
        'beta': inputs.capm.beta,
        'betaOrigem': inputs.capm.betaSource.name,
        'premioBase': inputs.capm.marketPremium,
        'rf': inputs.capm.riskFreeRate,
        'rfTerminal': inputs.terminalRiskFreeRate,
        'retornoCiclo': cycleReturn,
        'excedente':
            cycleReturn == null ? null : cycleReturn - base.discountRate,
        'ronicImplicito': ronic.toJson(),
        'premioImplicito': premium.toJson(),
        'rfImplicito': rf.toJson(),
        'keImplicito': impliedKe,
        'rfTerminalImplicito': impliedTerminalRf,
        'multiplicadorFluxo': multiplier,
      });
    }
    stderr.writeln('\nvarredura em ${stopwatch.elapsed.inSeconds}s');

    final identification = _identify(output);

    File('docs/validacao/dcf_reverso.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ')
          .convert({'ativos': output, 'identificacao': identification}),
    );
    stderr.writeln('escrito docs/validacao/dcf_reverso.json '
        '(${output.where((e) => e['avaliado'] == true).length} avaliados)');
    _printReport(output, identification);
  } finally {
    await ctx.dispose();
  }
}

/// O teste que separa as duas hipóteses de viés de nível.
///
/// Erro de **terminal** escala com o excedente `retorno do ciclo − desconto`:
/// a empresa com franquia é a que o estado estacionário mais castiga. Erro de
/// **taxa** escala com beta, e é indiferente ao excedente. Regredir o
/// potencial nos dois de uma vez é o que impede que a correlação de um seja
/// lida como evidência do outro.
Map<String, dynamic> _identify(List<Map<String, dynamic>> rows) {
  final ok = [
    for (final e in rows)
      if (e['avaliado'] == true &&
          e['potencial'] != null &&
          e['excedente'] != null &&
          e['beta'] != null)
        e,
  ];
  if (ok.length < 20) {
    return {'n': ok.length, 'erro': 'amostra insuficiente'};
  }

  final upsides = [for (final e in ok) (e['potencial'] as num).toDouble()];
  final exc = [for (final e in ok) (e['excedente'] as num).toDouble()];
  final bet = [for (final e in ok) (e['beta'] as num).toDouble()];

  // Postos padronizados: o potencial tem cauda pesada (a QUAL3 sozinha chega a
  // +477%), e regressão de nível sobre ele mede o extremo, não a relação.
  final zUpside = Regression.standardizedRanks(upsides);
  final zExc = Regression.standardizedRanks(exc);
  final zBet = Regression.standardizedRanks(bet);

  final joint = Regression.ols([zExc, zBet], zUpside);
  final onlyExc = Regression.ols([zExc], zUpside);
  final onlyBet = Regression.ols([zBet], zUpside);

  return {
    'n': ok.length,
    'spearmanPotencialExcedente': Regression.spearman(upsides, exc),
    'spearmanPotencialBeta': Regression.spearman(upsides, bet),
    'spearmanExcedenteBeta': Regression.spearman(exc, bet),
    'conjunta': joint == null
        ? null
        : {
            'coefExcedente': joint.coefficients[1],
            'tExcedente': joint.tStats[1],
            'coefBeta': joint.coefficients[2],
            'tBeta': joint.tStats[2],
            'r2': joint.r2,
          },
    'soExcedente': onlyExc == null
        ? null
        : {'coef': onlyExc.coefficients[1], 't': onlyExc.tStats[1], 'r2': onlyExc.r2},
    'soBeta': onlyBet == null
        ? null
        : {'coef': onlyBet.coefficients[1], 't': onlyBet.tStats[1], 'r2': onlyBet.r2},
  };
}

void _printReport(
  List<Map<String, dynamic>> rows,
  Map<String, dynamic> ident,
) {
  final ok = [for (final e in rows) if (e['avaliado'] == true) e];
  if (ok.isEmpty) {
    stdout.writeln('nenhum ativo avaliado');
    return;
  }

  double? med(Iterable<double> v) {
    final s = v.toList()..sort();
    if (s.isEmpty) return null;
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  String pc(double? x) =>
      x == null ? '—' : '${(x * 100).toStringAsFixed(1)}%';

  stdout.writeln('\n=== DCF REVERSO — ${ok.length} avaliados ===\n');

  final upsides = [for (final e in ok) (e['potencial'] as num).toDouble()];
  stdout.writeln('potencial mediano: ${pc(med(upsides))}   '
      'positivos: ${upsides.where((p) => p > 0).length}');

  // --- Eixo do retorno terminal ---
  final withRonic = [
    for (final e in ok)
      if ((e['ronicImplicito'] as Map)['implicito'] != null) e,
  ];
  void situations(String axis) {
    final account = <String, int>{};
    for (final e in ok) {
      final s = (e[axis] as Map)['situacao'] as String;
      account[s] = (account[s] ?? 0) + 1;
    }
    final sortedEntries = account.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sortedEntries) {
      stdout.writeln('  ${e.value.toString().padLeft(4)}  ${e.key}');
    }
  }

  stdout.writeln('\n-- RONIC_infinito implícito --');
  situations('ronicImplicito');
  final nonMonotonic = ok
      .where((e) => (e['ronicImplicito'] as Map)['monotonia'] == 'não monótona')
      .length;
  final flatOnes =
      ok.where((e) => (e['ronicImplicito'] as Map)['monotonia'] == 'plana').length;
  stdout.writeln('não monótonos: $nonMonotonic   planos (terminal insensível): $flatOnes');
  if (withRonic.isNotEmpty) {
    final r = [
      for (final e in withRonic)
        ((e['ronicImplicito'] as Map)['implicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do RONIC implícito: ${pc(med(r))}');
    final withCycle = [
      for (final e in withRonic)
        if (e['retornoCiclo'] != null)
          ((e['ronicImplicito'] as Map)['implicito'] as num).toDouble() /
              (e['retornoCiclo'] as num).toDouble(),
    ];
    stdout.writeln('mediana de RONIC implícito ÷ ROIC do ciclo: '
        '${med(withCycle)?.toStringAsFixed(2) ?? '—'}x');
    final above = withCycle.where((x) => x > 1).length;
    stdout.writeln('acima do ciclo: $above de ${withCycle.length}');
  }

  // --- Eixo do prêmio ---
  final withPremium = [
    for (final e in ok)
      if ((e['premioImplicito'] as Map)['implicito'] != null) e,
  ];
  stdout.writeln('\n-- prêmio de risco implícito --');
  situations('premioImplicito');
  if (withPremium.isNotEmpty) {
    final p = [
      for (final e in withPremium)
        ((e['premioImplicito'] as Map)['implicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do prêmio implícito: ${pc(med(p))} '
        '(parametrizado: 5,5%)');
    final ke = [
      for (final e in withPremium)
        if (e['keImplicito'] != null) (e['keImplicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do Ke implícito: ${pc(med(ke))}');
    final zero = p.where((x) => x <= 0.0001).length;
    stdout.writeln('no piso da grade (prêmio nulo não basta): $zero');
  }

  // --- Eixo do nível da taxa livre de risco ---
  final withRf = [
    for (final e in ok)
      if ((e['rfImplicito'] as Map)['implicito'] != null) e,
  ];
  stdout.writeln('\n-- deslocamento da taxa livre de risco --');
  situations('rfImplicito');
  if (withRf.isNotEmpty) {
    final d = [
      for (final e in withRf)
        ((e['rfImplicito'] as Map)['implicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do deslocamento: ${pc(med(d))} '
        '(negativo = a curva teria de ser mais baixa)');
    final rt = [
      for (final e in withRf)
        if (e['rfTerminalImplicito'] != null)
          (e['rfTerminalImplicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana da taxa de equilíbrio implícita: ${pc(med(rt))} '
        '(medida: 9,4%)');
  }

  // --- Eixo do fluxo-base ---
  final mult = [
    for (final e in ok)
      if (e['multiplicadorFluxo'] != null)
        (e['multiplicadorFluxo'] as num).toDouble(),
  ]..sort();
  final factors = [
    for (final e in ok)
      if (e['fatorBase'] != null) (e['fatorBase'] as num).toDouble(),
  ];
  stdout.writeln('\n-- fluxo-base --');
  if (mult.isNotEmpty) {
    stdout.writeln('multiplicador necessário para igualar o preço: '
        'p25=${mult[mult.length ~/ 4].toStringAsFixed(2)}x  '
        'mediana=${med(mult)!.toStringAsFixed(2)}x  '
        'p75=${mult[3 * mult.length ~/ 4].toStringAsFixed(2)}x');
    stdout.writeln('acima de 1: ${mult.where((x) => x > 1).length} de '
        '${mult.length}');
  }
  if (factors.isNotEmpty) {
    stdout.writeln('fator de normalização APLICADO: '
        'mediana=${med(factors)!.toStringAsFixed(2)}x  '
        'abaixo de 1: ${factors.where((x) => x < 0.999).length} de '
        '${factors.length}');
  }
  stdout.writeln('desconto corrente mediano: '
      '${pc(med([for (final e in ok) (e['desconto'] as num).toDouble()]))}');

  // --- O cruzamento dos eixos ---
  //
  // Duas perguntas diferentes, e confundi-las produz número errado:
  // *resolver* é ter raiz única; *ser inatingível* é o preço ficar fora do
  // alcance da grade inteira. "Múltiplas raízes" não é nenhuma das duas — o
  // eixo alcança o preço, mas não devolve um valor. A assimetria só significa
  // alguma coisa medida contra o inatingível.
  bool resolve(Map<String, dynamic> e, String axis) =>
      (e[axis] as Map)['implicito'] != null;
  bool unreachable(Map<String, dynamic> e, String axis) =>
      ((e[axis] as Map)['situacao'] as String).contains('acima do teto');

  final rateResolvesButTerminalNot = ok
      .where((e) => resolve(e, 'rfImplicito') && unreachable(e, 'ronicImplicito'))
      .length;
  final terminalResolvesButRateNot = ok
      .where((e) => resolve(e, 'ronicImplicito') && unreachable(e, 'rfImplicito'))
      .length;
  final inAllThree = ok
      .where((e) =>
          unreachable(e, 'ronicImplicito') &&
          unreachable(e, 'premioImplicito') &&
          unreachable(e, 'rfImplicito'))
      .toList();

  stdout.writeln('\n-- cruzamento dos eixos --');
  stdout.writeln('  a TAXA resolve e o TERMINAL é inatingível: '
      '$rateResolvesButTerminalNot');
  stdout.writeln('  o TERMINAL resolve e a TAXA é inatingível: '
      '$terminalResolvesButRateNot');
  stdout.writeln('  inatingível nos TRÊS eixos:                '
      '${inAllThree.length} de ${ok.length}');
  if (inAllThree.isNotEmpty) {
    final names = [for (final e in inAllThree) e['ticker'] as String]..sort();
    stdout.writeln('    ${names.join(', ')}');
  }

  // --- Identificação ---
  stdout.writeln('\n-- identificação (postos padronizados, n=${ident['n']}) --');
  final c = ident['conjunta'] as Map?;
  if (c != null) {
    stdout.writeln('potencial ~ excedente + beta');
    stdout.writeln('  excedente: coef=${(c['coefExcedente'] as double).toStringAsFixed(3)} '
        't=${(c['tExcedente'] as double).toStringAsFixed(2)}');
    stdout.writeln('  beta:      coef=${(c['coefBeta'] as double).toStringAsFixed(3)} '
        't=${(c['tBeta'] as double).toStringAsFixed(2)}');
    stdout.writeln('  R²=${(c['r2'] as double).toStringAsFixed(3)}');
  }
  stdout.writeln('Spearman potencial×excedente: '
      '${(ident['spearmanPotencialExcedente'] as num?)?.toStringAsFixed(3) ?? '—'}');
  stdout.writeln('Spearman potencial×beta:      '
      '${(ident['spearmanPotencialBeta'] as num?)?.toStringAsFixed(3) ?? '—'}');
}
