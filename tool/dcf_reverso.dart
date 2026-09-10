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
final _hoje = DateTime(2026, 9, 4);

/// Grade do retorno terminal, log-espaçada entre 0,5% e 200% ao ano.
///
/// Log e não linear porque a grandeza é um retorno sobre capital: a diferença
/// entre 8% e 10% importa, entre 150% e 152% não.
List<double> _gradeRonic() {
  const n = 61;
  const lo = 0.005, hi = 2.0;
  final passo = (math.log(hi) - math.log(lo)) / (n - 1);
  return [for (var i = 0; i < n; i++) math.exp(math.log(lo) + passo * i)];
}

/// Grade do prêmio de risco, de 0 a 25% em passos de 0,5 p.p.
List<double> _gradePremio() => [for (var i = 0; i <= 50; i++) i * 0.005];

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
List<double> _gradeRf() => [for (var i = 0; i <= 72; i++) -0.13 + i * 0.0025];

/// Resultado de uma varredura em um eixo.
class Varredura {
  /// Valor que iguala preço justo a preço de mercado. `null` sem raiz única.
  final double? implicito;

  /// Como o preço justo se comporta ao longo da grade.
  final String monotonia;

  /// Quantas vezes `justo − preço` troca de sinal na grade.
  final int cruzamentos;

  /// Preço justo na ponta inferior e na superior da grade.
  final double? justoMin;
  final double? justoMax;

  /// Pontos da grade em que a cascata não devolveu avaliação.
  final int falhas;

  /// Por que não houve raiz, quando não houve.
  ///
  /// A distinção importa mais que a raiz: `fora da grade — preço acima do
  /// teto` diz que **nem retorno terminal infinito** alcança o preço, e nesse
  /// ativo o terminal está descartado como explicação do vão. `já acima do
  /// preço` é o oposto — o eixo não precisa se mover.
  final String situacao;

  const Varredura({
    required this.implicito,
    required this.monotonia,
    required this.cruzamentos,
    required this.justoMin,
    required this.justoMax,
    required this.falhas,
    required this.situacao,
  });

  Map<String, dynamic> toJson() => {
        'implicito': implicito,
        'monotonia': monotonia,
        'cruzamentos': cruzamentos,
        'justoMin': justoMin,
        'justoMax': justoMax,
        'falhas': falhas,
        'situacao': situacao,
      };
}

/// Classifica uma varredura sem raiz pela posição da grade contra o preço.
String _situacao(double? justoMin, double? justoMax, double preco, int cruz) {
  if (justoMin == null || justoMax == null) return 'sem avaliação';
  if (cruz == 1) return 'raiz única';
  if (cruz > 1) return 'múltiplas raízes';
  final maior = justoMin > justoMax ? justoMin : justoMax;
  final menor = justoMin > justoMax ? justoMax : justoMin;
  if (maior < preco) return 'fora da grade — preço acima do teto';
  if (menor > preco) return 'fora da grade — justo acima do preço em toda a grade';
  return 'sem cruzamento';
}

/// Avalia e devolve o preço justo, ou `null` quando a cascata recusa.
double? _justo(ValuationInputs inputs) {
  final r = ValuationCascade.evaluate(inputs);
  return r.isOk ? r.unwrap().fairValue.reais : null;
}

/// Varre um eixo pela grade, classifica a monotonia e refina a raiz.
///
/// - [grade]: valores a percorrer, em ordem crescente.
/// - [monta]: constrói os insumos para um valor da grade.
/// - [preco]: preço de mercado, o alvo da igualdade.
Varredura _varrer({
  required List<double> grade,
  required ValuationInputs Function(double) monta,
  required double preco,
}) {
  final xs = <double>[], fs = <double>[];
  var falhas = 0;
  for (final x in grade) {
    final j = _justo(monta(x));
    if (j == null || !j.isFinite) {
      falhas++;
      continue;
    }
    xs.add(x);
    fs.add(j - preco);
  }
  if (xs.length < 3) {
    return Varredura(
      implicito: null,
      monotonia: 'sem avaliação',
      cruzamentos: 0,
      justoMin: null,
      justoMax: null,
      falhas: falhas,
      situacao: 'sem avaliação',
    );
  }

  // Monotonia medida, com tolerância relativa ao preço: variação abaixo de
  // 0,1% do preço é ruído de ponto flutuante, não direção.
  final tol = preco * 1e-3;
  var sobe = false, desce = false;
  for (var i = 1; i < fs.length; i++) {
    final d = fs[i] - fs[i - 1];
    if (d > tol) sobe = true;
    if (d < -tol) desce = true;
  }
  final monotonia = (sobe && desce)
      ? 'não monótona'
      : sobe
          ? 'crescente'
          : desce
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
      return _comRaiz(xs[i - 1], monotonia, 1, fs, preco, falhas);
    }
    if ((fs[i - 1] < 0) != (fs[i] < 0)) brackets.add([i - 1, i]);
  }
  if (brackets.length != 1) {
    return Varredura(
      implicito: null,
      monotonia: monotonia,
      cruzamentos: brackets.length,
      justoMin: fs.first + preco,
      justoMax: fs.last + preco,
      falhas: falhas,
      situacao:
          _situacao(fs.first + preco, fs.last + preco, preco, brackets.length),
    );
  }

  // Bissecção dentro do único intervalo que muda de sinal.
  var lo = xs[brackets[0][0]], hi = xs[brackets[0][1]];
  var flo = fs[brackets[0][0]];
  for (var it = 0; it < 60; it++) {
    final mid = (lo + hi) / 2;
    final j = _justo(monta(mid));
    if (j == null || !j.isFinite) break;
    final f = j - preco;
    if ((f < 0) == (flo < 0)) {
      lo = mid;
      flo = f;
    } else {
      hi = mid;
    }
    if ((hi - lo).abs() < 1e-9) break;
  }
  return _comRaiz((lo + hi) / 2, monotonia, 1, fs, preco, falhas);
}

Varredura _comRaiz(
  double raiz,
  String monotonia,
  int cruzamentos,
  List<double> fs,
  double preco,
  int falhas,
) =>
    Varredura(
      implicito: raiz,
      monotonia: monotonia,
      cruzamentos: cruzamentos,
      justoMin: fs.first + preco,
      justoMax: fs.last + preco,
      falhas: falhas,
      situacao: 'raiz única',
    );

/// Reconstrói os insumos trocando apenas o retorno terminal.
ValuationInputs _comRonic(ValuationInputs b, double ronic) => ValuationInputs(
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
ValuationInputs _comPremio(ValuationInputs b, double premio) => ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: CapmInputs(
        riskFreeRate: b.capm.riskFreeRate,
        beta: b.capm.beta,
        marketPremium: premio,
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
ValuationInputs _comRf(ValuationInputs b, double desloc) {
  double piso(double x) => x < 0.001 ? 0.001 : x;
  return ValuationInputs(
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: b.capm.withRiskFree(piso(b.capm.riskFreeRate + desloc)),
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: piso(b.terminalRiskFreeRate + desloc),
    prices: b.prices,
    isDistressed: b.isDistressed,
  );
}

Future<void> main(List<String> args) async {
  final limiteIdx = args.indexOf('--limit');
  final limite =
      limiteIdx >= 0 ? int.tryParse(args[limiteIdx + 1]) ?? 0 : 0;
  final alvos = [
    for (final a in args)
      if (!a.startsWith('--') && int.tryParse(a) == null) a,
  ];

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stderr.writeln('âncoras: rf=${anchors.currentRiskFreeRate.toStringAsFixed(4)} '
        'rfTerm=${anchors.riskFreeCagr.toStringAsFixed(4)} '
        'gNom=${anchors.nominalEconomyGrowth.toStringAsFixed(4)}');

    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (alvos.isNotEmpty) {
      universe = universe.where((t) => alvos.contains(t.value)).toList();
    }
    if (limite > 0 && universe.length > limite) {
      universe = universe.sublist(0, limite);
    }
    stderr.writeln('universo: ${universe.length} ativos');

    final gradeRonic = _gradeRonic();
    final gradePremio = _gradePremio();
    final gradeRf = _gradeRf();

    final saida = <Map<String, dynamic>>[];
    final cronometro = Stopwatch()..start();
    var i = 0;
    for (final ticker in universe) {
      i++;
      if (i % 10 == 0) {
        stderr.write('  $i/${universe.length} '
            '(${cronometro.elapsed.inSeconds}s)      \r');
      }

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
      if (prep.isErr) {
        saida.add({
          'ticker': ticker.value,
          'avaliado': false,
          'recusa': prep.failureOrNull?.message,
        });
        continue;
      }

      final inputs = prep.unwrap();
      final baseRes = ValuationCascade.evaluate(inputs);
      if (baseRes.isErr) {
        saida.add({
          'ticker': ticker.value,
          'avaliado': false,
          'recusa': baseRes.failureOrNull?.message,
        });
        continue;
      }
      final base = baseRes.unwrap();
      final preco = inputs.marketPrice;

      // Retorno do ciclo na via que a cascata efetivamente escolheu: comparar
      // ROIC com WACC numa e ROE com Ke na outra é a única comparação em que
      // o excedente significa a mesma coisa.
      final via = base.model == ValuationModel.dcfFcff
          ? ValuationLane.firm
          : ValuationLane.shareholder;
      final pub = PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      final serie = CapitalSeries.build(pub, via);
      final retornoCiclo =
          serie.cycleReturn(window: ValuationParameters.cycleWindow);

      final ronic = _varrer(
        grade: gradeRonic,
        monta: (x) => _comRonic(inputs, x),
        preco: preco,
      );
      final premio = _varrer(
        grade: gradePremio,
        monta: (x) => _comPremio(inputs, x),
        preco: preco,
      );

      final rf = _varrer(
        grade: gradeRf,
        monta: (x) => _comRf(inputs, x),
        preco: preco,
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
      final justo = base.fairValue.reais;
      double? multiplicador;
      if (justo > 0) {
        if (via == ValuationLane.firm && s != null && s > 0 && s <= 1) {
          final dividaPorPapel = justo * (1 - s) / s;
          multiplicador = (preco + dividaPorPapel) / (justo + dividaPorPapel);
        } else {
          multiplicador = preco / justo;
        }
      }

      final keImplicito = premio.implicito == null
          ? null
          : inputs.capm.riskFreeRate + inputs.capm.beta * premio.implicito!;
      final rfTerminalImplicito = rf.implicito == null
          ? null
          : inputs.terminalRiskFreeRate + rf.implicito!;

      saida.add({
        'ticker': ticker.value,
        'avaliado': true,
        'setor': inputs.sectorKey,
        'preco': preco,
        'justo': base.fairValue.reais,
        'potencial': base.upside,
        'via': via.name,
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
        'retornoCiclo': retornoCiclo,
        'excedente':
            retornoCiclo == null ? null : retornoCiclo - base.discountRate,
        'ronicImplicito': ronic.toJson(),
        'premioImplicito': premio.toJson(),
        'rfImplicito': rf.toJson(),
        'keImplicito': keImplicito,
        'rfTerminalImplicito': rfTerminalImplicito,
        'multiplicadorFluxo': multiplicador,
      });
    }
    stderr.writeln('\nvarredura em ${cronometro.elapsed.inSeconds}s');

    final identificacao = _identificar(saida);

    File('docs/validacao/dcf_reverso.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ')
          .convert({'ativos': saida, 'identificacao': identificacao}),
    );
    stderr.writeln('escrito docs/validacao/dcf_reverso.json '
        '(${saida.where((e) => e['avaliado'] == true).length} avaliados)');
    _imprimir(saida, identificacao);
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
Map<String, dynamic> _identificar(List<Map<String, dynamic>> linhas) {
  final ok = [
    for (final e in linhas)
      if (e['avaliado'] == true &&
          e['potencial'] != null &&
          e['excedente'] != null &&
          e['beta'] != null)
        e,
  ];
  if (ok.length < 20) {
    return {'n': ok.length, 'erro': 'amostra insuficiente'};
  }

  final pot = [for (final e in ok) (e['potencial'] as num).toDouble()];
  final exc = [for (final e in ok) (e['excedente'] as num).toDouble()];
  final bet = [for (final e in ok) (e['beta'] as num).toDouble()];

  // Postos padronizados: o potencial tem cauda pesada (a QUAL3 sozinha chega a
  // +477%), e regressão de nível sobre ele mede o extremo, não a relação.
  final zPot = Regression.standardizedRanks(pot);
  final zExc = Regression.standardizedRanks(exc);
  final zBet = Regression.standardizedRanks(bet);

  final conjunta = Regression.ols([zExc, zBet], zPot);
  final soExc = Regression.ols([zExc], zPot);
  final soBet = Regression.ols([zBet], zPot);

  return {
    'n': ok.length,
    'spearmanPotencialExcedente': Regression.spearman(pot, exc),
    'spearmanPotencialBeta': Regression.spearman(pot, bet),
    'spearmanExcedenteBeta': Regression.spearman(exc, bet),
    'conjunta': conjunta == null
        ? null
        : {
            'coefExcedente': conjunta.coefficients[1],
            'tExcedente': conjunta.tStats[1],
            'coefBeta': conjunta.coefficients[2],
            'tBeta': conjunta.tStats[2],
            'r2': conjunta.r2,
          },
    'soExcedente': soExc == null
        ? null
        : {'coef': soExc.coefficients[1], 't': soExc.tStats[1], 'r2': soExc.r2},
    'soBeta': soBet == null
        ? null
        : {'coef': soBet.coefficients[1], 't': soBet.tStats[1], 'r2': soBet.r2},
  };
}

void _imprimir(
  List<Map<String, dynamic>> linhas,
  Map<String, dynamic> ident,
) {
  final ok = [for (final e in linhas) if (e['avaliado'] == true) e];
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

  final pot = [for (final e in ok) (e['potencial'] as num).toDouble()];
  stdout.writeln('potencial mediano: ${pc(med(pot))}   '
      'positivos: ${pot.where((p) => p > 0).length}');

  // --- Eixo do retorno terminal ---
  final comRonic = [
    for (final e in ok)
      if ((e['ronicImplicito'] as Map)['implicito'] != null) e,
  ];
  void situacoes(String eixo) {
    final conta = <String, int>{};
    for (final e in ok) {
      final s = (e[eixo] as Map)['situacao'] as String;
      conta[s] = (conta[s] ?? 0) + 1;
    }
    final ordenado = conta.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ordenado) {
      stdout.writeln('  ${e.value.toString().padLeft(4)}  ${e.key}');
    }
  }

  stdout.writeln('\n-- RONIC_infinito implícito --');
  situacoes('ronicImplicito');
  final naoMono = ok
      .where((e) => (e['ronicImplicito'] as Map)['monotonia'] == 'não monótona')
      .length;
  final planos =
      ok.where((e) => (e['ronicImplicito'] as Map)['monotonia'] == 'plana').length;
  stdout.writeln('não monótonos: $naoMono   planos (terminal insensível): $planos');
  if (comRonic.isNotEmpty) {
    final r = [
      for (final e in comRonic)
        ((e['ronicImplicito'] as Map)['implicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do RONIC implícito: ${pc(med(r))}');
    final comCiclo = [
      for (final e in comRonic)
        if (e['retornoCiclo'] != null)
          ((e['ronicImplicito'] as Map)['implicito'] as num).toDouble() /
              (e['retornoCiclo'] as num).toDouble(),
    ];
    stdout.writeln('mediana de RONIC implícito ÷ ROIC do ciclo: '
        '${med(comCiclo)?.toStringAsFixed(2) ?? '—'}x');
    final acima = comCiclo.where((x) => x > 1).length;
    stdout.writeln('acima do ciclo: $acima de ${comCiclo.length}');
  }

  // --- Eixo do prêmio ---
  final comPremio = [
    for (final e in ok)
      if ((e['premioImplicito'] as Map)['implicito'] != null) e,
  ];
  stdout.writeln('\n-- prêmio de risco implícito --');
  situacoes('premioImplicito');
  if (comPremio.isNotEmpty) {
    final p = [
      for (final e in comPremio)
        ((e['premioImplicito'] as Map)['implicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do prêmio implícito: ${pc(med(p))} '
        '(parametrizado: 5,5%)');
    final ke = [
      for (final e in comPremio)
        if (e['keImplicito'] != null) (e['keImplicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do Ke implícito: ${pc(med(ke))}');
    final zero = p.where((x) => x <= 0.0001).length;
    stdout.writeln('no piso da grade (prêmio nulo não basta): $zero');
  }

  // --- Eixo do nível da taxa livre de risco ---
  final comRf = [
    for (final e in ok)
      if ((e['rfImplicito'] as Map)['implicito'] != null) e,
  ];
  stdout.writeln('\n-- deslocamento da taxa livre de risco --');
  situacoes('rfImplicito');
  if (comRf.isNotEmpty) {
    final d = [
      for (final e in comRf)
        ((e['rfImplicito'] as Map)['implicito'] as num).toDouble(),
    ];
    stdout.writeln('mediana do deslocamento: ${pc(med(d))} '
        '(negativo = a curva teria de ser mais baixa)');
    final rt = [
      for (final e in comRf)
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
  final fatores = [
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
  if (fatores.isNotEmpty) {
    stdout.writeln('fator de normalização APLICADO: '
        'mediana=${med(fatores)!.toStringAsFixed(2)}x  '
        'abaixo de 1: ${fatores.where((x) => x < 0.999).length} de '
        '${fatores.length}');
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
  bool resolve(Map<String, dynamic> e, String eixo) =>
      (e[eixo] as Map)['implicito'] != null;
  bool inatingivel(Map<String, dynamic> e, String eixo) =>
      ((e[eixo] as Map)['situacao'] as String).contains('acima do teto');

  final taxaResolveTerminalNao = ok
      .where((e) => resolve(e, 'rfImplicito') && inatingivel(e, 'ronicImplicito'))
      .length;
  final terminalResolveTaxaNao = ok
      .where((e) => resolve(e, 'ronicImplicito') && inatingivel(e, 'rfImplicito'))
      .length;
  final nosTres = ok
      .where((e) =>
          inatingivel(e, 'ronicImplicito') &&
          inatingivel(e, 'premioImplicito') &&
          inatingivel(e, 'rfImplicito'))
      .toList();

  stdout.writeln('\n-- cruzamento dos eixos --');
  stdout.writeln('  a TAXA resolve e o TERMINAL é inatingível: '
      '$taxaResolveTerminalNao');
  stdout.writeln('  o TERMINAL resolve e a TAXA é inatingível: '
      '$terminalResolveTaxaNao');
  stdout.writeln('  inatingível nos TRÊS eixos:                '
      '${nosTres.length} de ${ok.length}');
  if (nosTres.isNotEmpty) {
    final nomes = [for (final e in nosTres) e['ticker'] as String]..sort();
    stdout.writeln('    ${nomes.join(', ')}');
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
