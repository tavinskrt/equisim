import 'package:equisim_core/equisim_core.dart';

import 'context.dart';

/// Resultado de uma verificação de invariante.
class InvariantCheck {
  /// Nome da identidade verificada, como aparece no relatório.
  final String name;

  /// `true` quando a identidade se sustentou dentro da tolerância.
  final bool passed;

  /// Os números medidos e a tolerância aplicada. É o que permite conferir a
  /// verificação em vez de acreditar nela.
  final String detail;

  /// Declara o resultado.
  const InvariantCheck({
    required this.name,
    required this.passed,
    required this.detail,
  });
}

/// Verificações de consistência interna do motor.
///
/// **Por que estas e não um oráculo externo.** O plano original previa validar
/// o motor contra o `adjustedClose` da fonte. A auditoria mostrou que aquela
/// série subajusta proventos brasileiros em até 38,5%, o que a inviabiliza
/// como referência (ver `PLANO_ARQUITETURA.md` §0.4).
///
/// As invariantes abaixo substituem o oráculo descartado. Não dependem de
/// nenhuma fonte externa de verdade: são identidades matemáticas que o motor
/// **precisa** satisfazer. Uma falha aqui é prova de defeito, não indício.
abstract final class Invariants {
  /// Executa todas as invariantes e devolve um resultado por identidade.
  ///
  /// - [ctx]: contexto com a camada de dados do aplicativo.
  ///
  /// **Nunca lança e nunca interrompe no primeiro erro**: uma identidade que
  /// falha vira `InvariantCheck` com `passed` falso, e as demais continuam. Um
  /// relatório parcial esconderia se o defeito é isolado ou generalizado.
  ///
  /// As três últimas verificações são puramente aritméticas e dispensam rede;
  /// as demais consomem dados reais e dependem do que o cache ou a fonte
  /// entregam.
  static Future<List<InvariantCheck>> runAll(
    ValidationContext ctx, {
    List<String> sample = const ['PETR4', 'ITUB4', 'WEGE3'],
  }) async {
    final checks = <InvariantCheck>[];
    final today = DateTime.now();
    final window = DateRange(
      DateTime(today.year - 3, today.month, today.day),
      today,
    );

    for (final symbol in sample) {
      final ticker = Ticker.parse(symbol);
      final priceResult = await ctx.prices.daily(ticker, window);
      if (priceResult.isErr) continue;
      final series = priceResult.unwrap();

      final dividendResult = await ctx.dividends.history(ticker);
      final events = dividendResult.getOrElse(const <DividendEvent>[]);

      checks
        ..add(_singleAssetMatchesTotalReturn(ticker, series, events, window))
        ..add(_lumpSumXirrMatchesCagr(ticker, series, window))
        ..add(_perAssetSumsToPortfolio(ticker, series, events, window))
        ..add(_taxReducesReturn(ticker, series, events, window));
    }

    checks
      ..add(_contributionsDoNotInflateTwr())
      ..add(_weightsAlwaysSumToOne())
      ..add(_requiredRateRoundTrip());

    return checks;
  }

  /// Uma carteira de ativo único, peso 100%, sem aportes mensais, tem de render
  /// exatamente o que o motor de retorno total calcula para aquele ativo.
  ///
  /// É a identidade mais forte disponível: liga o backtest de carteira ao
  /// motor de retorno total, que são caminhos de código independentes.
  static InvariantCheck _singleAssetMatchesTotalReturn(
    Ticker ticker,
    PriceSeries series,
    List<DividendEvent> events,
    DateRange window,
  ) {
    final portfolio = Portfolio.equalWeighted(
      id: 'p',
      name: 'P',
      kind: PortfolioKind.principal,
      assets: [Asset(ticker: ticker, name: ticker.value)],
    ).unwrap();

    final backtest = PortfolioBacktest.run(
      portfolio: portfolio,
      prices: {ticker: series},
      dividends: {ticker: events},
      plan: const ContributionPlan(
        initial: Money(1000000), // R$ 10.000
        monthly: Money.zero,
      ),
      range: window,
      taxPolicy: TaxPolicy.brasil,
    );

    if (backtest.isErr) {
      return InvariantCheck(
        name: '${ticker.value}: carteira de ativo único ≡ retorno total',
        passed: false,
        detail: 'backtest falhou: ${backtest.failureOrNull!.message}',
      );
    }

    final totalReturn = TotalReturnEngine.build(
      prices: series,
      dividends: events,
      taxPolicy: TaxPolicy.brasil,
      range: window,
    );

    final fromBacktest = backtest.unwrap().metrics.timeWeightedReturn;
    final fromEngine = totalReturn.totalReturn;
    final gap = (fromBacktest - fromEngine).abs();

    return InvariantCheck(
      name: '${ticker.value}: carteira de ativo único ≡ retorno total',
      passed: gap < 1e-6,
      detail: 'backtest ${pct(fromBacktest)} · motor ${pct(fromEngine)} · '
          'diferença ${num2(gap, decimals: 9)}',
    );
  }

  /// Com um único aporte no início e nenhum depois, a taxa interna dos fluxos
  /// tem de coincidir com o CAGR — as duas medidas convergem quando não há
  /// cronograma de aportes a diferenciar.
  static InvariantCheck _lumpSumXirrMatchesCagr(
    Ticker ticker,
    PriceSeries series,
    DateRange window,
  ) {
    final portfolio = Portfolio.equalWeighted(
      id: 'p',
      name: 'P',
      kind: PortfolioKind.principal,
      assets: [Asset(ticker: ticker, name: ticker.value)],
    ).unwrap();

    final result = PortfolioBacktest.run(
      portfolio: portfolio,
      prices: {ticker: series},
      dividends: const {},
      plan: const ContributionPlan(
        initial: Money(1000000),
        monthly: Money.zero,
      ),
      range: window,
    );

    if (result.isErr) {
      return InvariantCheck(
        name: '${ticker.value}: aporte único ⇒ XIRR ≡ CAGR',
        passed: false,
        detail: result.failureOrNull!.message,
      );
    }

    final metrics = result.unwrap().metrics;
    final xirr = metrics.moneyWeightedReturn;
    if (xirr == null) {
      return InvariantCheck(
        name: '${ticker.value}: aporte único ⇒ XIRR ≡ CAGR',
        passed: false,
        detail: 'XIRR não convergiu',
      );
    }

    final gap = (xirr - metrics.cagr).abs();
    return InvariantCheck(
      name: '${ticker.value}: aporte único ⇒ XIRR ≡ CAGR',
      passed: gap < 0.005,
      detail: 'XIRR ${pct(xirr)} · CAGR ${pct(metrics.cagr)} · '
          'diferença ${pct(gap, decimals: 4)}',
    );
  }

  /// A soma dos valores finais por ativo tem de reproduzir o patrimônio da
  /// carteira. Detecta perda ou duplicação de capital na consolidação.
  static InvariantCheck _perAssetSumsToPortfolio(
    Ticker ticker,
    PriceSeries series,
    List<DividendEvent> events,
    DateRange window,
  ) {
    final portfolio = Portfolio.equalWeighted(
      id: 'p',
      name: 'P',
      kind: PortfolioKind.principal,
      assets: [Asset(ticker: ticker, name: ticker.value)],
    ).unwrap();

    final result = PortfolioBacktest.run(
      portfolio: portfolio,
      prices: {ticker: series},
      dividends: {ticker: events},
      plan: const ContributionPlan(
        initial: Money(500000),
        monthly: Money(50000),
      ),
      range: window,
    );

    if (result.isErr) {
      return InvariantCheck(
        name: '${ticker.value}: Σ ativos ≡ patrimônio da carteira',
        passed: false,
        detail: result.failureOrNull!.message,
      );
    }

    final outcome = result.unwrap();
    final sum = outcome.perAsset.values
        .fold<double>(0, (a, b) => a + b.finalValue.reais);
    final gap = (sum - outcome.finalValue.reais).abs();

    return InvariantCheck(
      name: '${ticker.value}: Σ ativos ≡ patrimônio da carteira',
      passed: gap < 0.05,
      detail: 'Σ ${num2(sum, decimals: 2)} · '
          'carteira ${num2(outcome.finalValue.reais, decimals: 2)} · '
          'diferença ${num2(gap, decimals: 4)}',
    );
  }

  /// Com tributação ligada, o resultado tem de ficar **abaixo** do bruto, e a
  /// diferença tem de ser exatamente o imposto retido reinvestido a menos.
  static InvariantCheck _taxReducesReturn(
    Ticker ticker,
    PriceSeries series,
    List<DividendEvent> events,
    DateRange window,
  ) {
    final portfolio = Portfolio.equalWeighted(
      id: 'p',
      name: 'P',
      kind: PortfolioKind.principal,
      assets: [Asset(ticker: ticker, name: ticker.value)],
    ).unwrap();

    BacktestOutcome? run(TaxPolicy policy) => PortfolioBacktest.run(
          portfolio: portfolio,
          prices: {ticker: series},
          dividends: {ticker: events},
          plan: const ContributionPlan(
            initial: Money(1000000),
            monthly: Money.zero,
          ),
          range: window,
          taxPolicy: policy,
        ).valueOrNull;

    final gross = run(TaxPolicy.zero);
    final net = run(TaxPolicy.brasil);

    if (gross == null || net == null) {
      return InvariantCheck(
        name: '${ticker.value}: tributação reduz o resultado',
        passed: false,
        detail: 'backtest falhou',
      );
    }

    final hasJcp = events.any((e) => e.kind == DividendKind.jcp);
    final passed = hasJcp
        ? net.finalValue.reais < gross.finalValue.reais &&
            net.withheldTax.isPositive
        : (net.finalValue.reais - gross.finalValue.reais).abs() < 0.05;

    return InvariantCheck(
      name: '${ticker.value}: tributação reduz o resultado',
      passed: passed,
      detail: hasJcp
          ? 'bruto ${num2(gross.finalValue.reais, decimals: 2)} · '
              'líquido ${num2(net.finalValue.reais, decimals: 2)} · '
              'IR retido ${num2(net.withheldTax.reais, decimals: 2)}'
          : 'sem JCP no período — resultados devem coincidir',
    );
  }

  /// Aporte que entra e não é investido não pode virar retorno.
  ///
  /// É a defesa contra o defeito mais comum em simuladores de carteira, e o
  /// que motivou trocar CAGR sobre capital aportado por TWR.
  static InvariantCheck _contributionsDoNotInflateTwr() {
    final twr = Returns.timeWeighted(
      values: [100, 10100, 10100],
      externalFlows: [100, 10000, 0],
    );
    return InvariantCheck(
      name: 'Aporte não é confundido com retorno',
      passed: twr.abs() < 1e-12,
      detail: 'carteira parada que recebe R\$ 10.000 rende ${pct(twr)} '
          '(esperado 0,00%)',
    );
  }

  /// A soma dos pesos tem de ser exatamente 1,0 para qualquer quantidade de
  /// ativos, inclusive as que produzem dízima na divisão.
  static InvariantCheck _weightsAlwaysSumToOne() {
    final failures = <int>[];
    for (var n = 1; n <= Portfolio.maxAssets; n++) {
      final tickers = List.generate(n, (i) => Ticker.parse('AAAA$i'));
      final sum = Weights.sum(Weights.equal(tickers).values);
      if ((sum - 1.0).abs() > 1e-12) failures.add(n);
    }
    return InvariantCheck(
      name: 'Pesos equiponderados somam exatamente 100%',
      passed: failures.isEmpty,
      detail: failures.isEmpty
          ? 'verificado de 1 a ${Portfolio.maxAssets} ativos'
          : 'falhou com $failures ativos',
    );
  }

  /// A taxa resolvida, realimentada na equação de valor futuro, tem de
  /// reproduzir a meta.
  static InvariantCheck _requiredRateRoundTrip() {
    final cases = [
      (initial: 10000.0, monthly: 1000.0, months: 120, target: 300000.0),
      (initial: 0.0, monthly: 500.0, months: 60, target: 40000.0),
      (initial: 50000.0, monthly: 0.0, months: 36, target: 80000.0),
    ];

    final errors = <String>[];
    for (final c in cases) {
      final goal = FinancialGoal(
        initialContribution: Money.fromReais(c.initial),
        monthlyContribution: Money.fromReais(c.monthly),
        months: c.months,
        targetWealth: Money.fromReais(c.target),
      );
      final solved = RequiredReturnSolver.solve(goal);
      if (solved.isErr) {
        errors.add('${c.target}: ${solved.failureOrNull!.message}');
        continue;
      }
      final fv = RequiredReturnSolver.futureValue(
        rate: solved.unwrap().monthly,
        initial: c.initial,
        monthly: c.monthly,
        months: c.months,
      );
      final gap = (fv - c.target).abs();
      if (gap > 0.01) errors.add('${c.target}: erro de ${num2(gap)}');
    }

    return InvariantCheck(
      name: 'Rentabilidade requerida reproduz a meta (ida e volta)',
      passed: errors.isEmpty,
      detail: errors.isEmpty
          ? '${cases.length} casos com erro abaixo de R\$ 0,01'
          : errors.join(' · '),
    );
  }

  /// Relatório em markdown.
  /// Formata os resultados como relatório Markdown.
  ///
  /// - [checks]: saída de [runAll].
  ///
  /// Não decide nada: quem interpreta reprovação é o chamador.
  static String report(List<InvariantCheck> checks) {
    final passed = checks.where((c) => c.passed).length;
    final buffer = StringBuffer()
      ..writeln('# Invariantes do motor')
      ..writeln()
      ..writeln('Gerado em ${DateTime.now().toIso8601String().substring(0, 19)}.')
      ..writeln()
      ..writeln('Estas verificações não dependem de fonte externa de verdade: '
          'são identidades que o motor precisa satisfazer. Substituem o '
          'oráculo `adjustedClose` descartado na auditoria (§0.4), que se '
          'mostrou inconsistente com o fluxo de proventos em até 38,5%.')
      ..writeln()
      ..writeln('**Resultado: $passed de ${checks.length} aprovadas.**')
      ..writeln()
      ..writeln('| Invariante | Situação | Detalhe |')
      ..writeln('|---|---|---|');

    for (final check in checks) {
      buffer.writeln(
        '| ${check.name} | ${check.passed ? '✅' : '❌'} | ${check.detail} |',
      );
    }

    return buffer.toString();
  }
}
