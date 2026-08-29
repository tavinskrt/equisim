import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'context.dart';

/// Exporta séries e métricas para conferência independente em Python.
///
/// **Por que isto existe.** O Dart não tem ecossistema científico maduro —
/// não há NumPy nem SciPy. Toda a estatística deste trabalho foi implementada
/// à mão. Afirmar que está certa sem conferência externa seria pedir confiança;
/// exportar as séries e recalcular tudo com bibliotecas consagradas transforma
/// a limitação em evidência de corretude.
///
/// Os arquivos gerados alimentam `cross_validation.py`, que recomputa
/// volatilidade, beta, correlação, Sharpe, XIRR e o DCF, e reporta a diferença.
abstract final class PythonExport {
  /// Separador de campo dos CSV gerados.
  ///
  /// Vírgula, não ponto e vírgula: os arquivos são lidos por `pandas` com o
  /// padrão dele, e os números são gravados com ponto decimal.
  static const String separator = ',';

  /// Gera todos os arquivos de conferência no diretório de saída.
  ///
  /// - [ctx]: contexto com a camada de dados.
  /// - [symbols]: tickers da amostra.
  /// - [outputDir]: destino dos CSV. **Arquivos existentes são
  ///   sobrescritos.**
  /// - [windowYears]: janela histórica exportada. Padrão 5 anos.
  ///
  /// A janela termina em `DateTime.now()`, então **duas execuções em dias
  /// diferentes produzem arquivos diferentes**. É deliberado — a conferência
  /// vale sobre dados correntes —, mas significa que reproduzir um relatório
  /// antigo exige o cache daquela data, não apenas o mesmo comando.
  ///
  /// Ativos sem dados utilizáveis são omitidos dos arquivos em vez de
  /// interromper a exportação.
  static Future<void> run(
    ValidationContext ctx, {
    required List<String> symbols,
    required String outputDir,
    int windowYears = 5,
  }) async {
    final today = DateTime.now();
    final window = DateRange(
      DateTime(today.year - windowYears, today.month, today.day),
      today,
    );

    final tickers = symbols
        .map(Ticker.tryParse)
        .whereType<Ticker>()
        .toList();

    stdout.writeln('  buscando séries...');
    final priceResult = await ctx.prices.dailyBatch(tickers, window);
    if (priceResult.isErr) {
      stderr.writeln('  falha: ${priceResult.failureOrNull!.message}');
      return;
    }
    final priceMap = priceResult.unwrap();

    final dividendResult = await ctx.dividends.historyBatch(tickers);
    final dividendMap =
        dividendResult.getOrElse(const <Ticker, List<DividendEvent>>{});

    final benchmarkResult = await ctx.benchmark.ibovespa(window);

    // 1. Preços de fechamento, um ativo por coluna.
    _exportPrices(priceMap, benchmarkResult.valueOrNull, outputDir);

    // 2. Eventos de provento com rótulo fiscal.
    _exportDividends(dividendMap, outputDir);

    // 3. Séries de retorno total construídas pelo domínio.
    _exportTotalReturns(priceMap, dividendMap, window, outputDir);

    // 4. Métricas calculadas pelo motor, para o Python conferir.
    await _exportMetrics(ctx, priceMap, dividendMap, benchmarkResult.valueOrNull,
        window, outputDir);
  }

  static void _exportPrices(
    Map<Ticker, PriceSeries> prices,
    PriceSeries? benchmark,
    String outputDir,
  ) {
    final tickers = prices.keys.toList()..sort();
    final calendar = <DateTime>{};
    for (final series in prices.values) {
      calendar.addAll(series.dates);
    }
    final dates = calendar.toList()..sort();

    final buffer = StringBuffer()
      ..writeln([
        'date',
        ...tickers.map((t) => t.value),
        if (benchmark != null) 'IBOV',
      ].join(separator));

    for (final date in dates) {
      final row = <String>[_iso(date)];
      for (final ticker in tickers) {
        final close = prices[ticker]!.closeOn(date);
        row.add(close?.toStringAsFixed(6) ?? '');
      }
      if (benchmark != null) {
        row.add(benchmark.closeOn(date)?.toStringAsFixed(6) ?? '');
      }
      buffer.writeln(row.join(separator));
    }

    writeReport('$outputDir/precos.csv', buffer.toString());
  }

  static void _exportDividends(
    Map<Ticker, List<DividendEvent>> dividends,
    String outputDir,
  ) {
    final buffer = StringBuffer()
      ..writeln([
        'ticker',
        'ex_date',
        'payment_date',
        'amount',
        'kind',
        'payment_date_estimated',
      ].join(separator));

    for (final entry in dividends.entries) {
      for (final event in entry.value) {
        buffer.writeln([
          entry.key.value,
          _iso(event.exDate),
          _iso(event.paymentDate),
          event.amountPerShare.toStringAsFixed(8),
          event.kind.label,
          event.paymentDateEstimated ? '1' : '0',
        ].join(separator));
      }
    }

    writeReport('$outputDir/proventos.csv', buffer.toString());
  }

  static void _exportTotalReturns(
    Map<Ticker, PriceSeries> prices,
    Map<Ticker, List<DividendEvent>> dividends,
    DateRange window,
    String outputDir,
  ) {
    final tickers = prices.keys.toList()..sort();
    final series = <Ticker, TotalReturnSeries>{};
    for (final ticker in tickers) {
      series[ticker] = TotalReturnEngine.build(
        prices: prices[ticker]!,
        dividends: dividends[ticker] ?? const [],
        taxPolicy: TaxPolicy.brasil,
        range: window,
      );
    }

    final calendar = <DateTime>{};
    for (final s in series.values) {
      calendar.addAll(s.dates);
    }
    final dates = calendar.toList()..sort();

    final index = <Ticker, Map<DateTime, double>>{
      for (final ticker in tickers)
        ticker: {
          for (var i = 0; i < series[ticker]!.dates.length; i++)
            series[ticker]!.dates[i]: series[ticker]!.index[i],
        },
    };

    final buffer = StringBuffer()
      ..writeln(['date', ...tickers.map((t) => t.value)].join(separator));

    for (final date in dates) {
      final row = <String>[_iso(date)];
      for (final ticker in tickers) {
        final value = index[ticker]![date];
        row.add(value?.toStringAsFixed(8) ?? '');
      }
      buffer.writeln(row.join(separator));
    }

    writeReport('$outputDir/retorno_total.csv', buffer.toString());
  }

  static Future<void> _exportMetrics(
    ValidationContext ctx,
    Map<Ticker, PriceSeries> prices,
    Map<Ticker, List<DividendEvent>> dividends,
    PriceSeries? benchmark,
    DateRange window,
    String outputDir,
  ) async {
    final riskFreeResult = await ctx.macro.riskFreeDaily(window);
    final riskFree = riskFreeResult.isOk
        ? riskFreeResult.unwrap().annualized()
        : MarketAnchors.fallback2026.riskFreeCagr;

    final buffer = StringBuffer()
      ..writeln([
        'ticker',
        'retorno_total',
        'cagr',
        'volatilidade_anual',
        'max_drawdown',
        'sharpe',
        'sortino',
        'beta',
        'correlacao_ibov',
        'observacoes',
      ].join(separator));

    for (final ticker in prices.keys.toList()..sort()) {
      final total = TotalReturnEngine.build(
        prices: prices[ticker]!,
        dividends: dividends[ticker] ?? const [],
        taxPolicy: TaxPolicy.brasil,
        range: window,
      );
      if (total.isEmpty) continue;

      final years = DateRange(total.dates.first, total.dates.last).years;
      final cagr = Returns.annualize(total.totalReturn, years);
      final risk = RiskMetrics.fromIndex(
        twrIndex: total.index,
        cagr: cagr,
        riskFreeRate: riskFree,
      );

      var beta = '';
      var correlation = '';
      var observations = '';
      if (benchmark != null) {
        final aligned = BetaCalculator.alignReturns(
          assetDates: total.dates,
          assetIndex: total.index,
          marketDates: benchmark.dates,
          marketIndex: benchmark.points.map((p) => p.close).toList(),
        );
        final estimate = BetaCalculator.estimate(
          assetReturns: aligned.asset,
          marketReturns: aligned.market,
        );
        if (estimate.isOk) {
          beta = estimate.unwrap().beta.toStringAsFixed(8);
          correlation = estimate.unwrap().correlation.toStringAsFixed(8);
          observations = '${estimate.unwrap().observations}';
        }
      }

      buffer.writeln([
        ticker.value,
        total.totalReturn.toStringAsFixed(8),
        cagr.toStringAsFixed(8),
        risk.volatility.toStringAsFixed(8),
        risk.maxDrawdown.toStringAsFixed(8),
        risk.sharpe.toStringAsFixed(8),
        risk.sortino.toStringAsFixed(8),
        beta,
        correlation,
        observations,
      ].join(separator));
    }

    writeReport('$outputDir/metricas_equisim.csv', buffer.toString());

    // Parâmetros usados, para o Python reproduzir exatamente.
    final parameters = StringBuffer()
      ..writeln(['parametro', 'valor'].join(separator))
      ..writeln(['taxa_livre_risco_anual', riskFree.toStringAsFixed(8)].join(separator))
      ..writeln(['pregoes_por_ano', '$tradingDaysPerYear'].join(separator))
      ..writeln(['janela_inicio', _iso(window.start)].join(separator))
      ..writeln(['janela_fim', _iso(window.end)].join(separator))
      ..writeln(['aliquota_jcp', '0.15'].join(separator))
      ..writeln(['desvio_padrao', 'amostral (n-1)'].join(separator));

    writeReport('$outputDir/parametros.csv', parameters.toString());
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
