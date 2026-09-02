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

    final benchmarkResult = await ctx.benchmark.ibovespa(window);

    // 1. Preços de fechamento, um ativo por coluna.
    _exportPrices(priceMap, benchmarkResult.valueOrNull, outputDir);

    // 2. Métricas calculadas pelo motor, para o Python conferir.
    await _exportMetrics(
      ctx,
      priceMap,
      benchmarkResult.valueOrNull,
      window,
      outputDir,
    );
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

  static Future<void> _exportMetrics(
    ValidationContext ctx,
    Map<Ticker, PriceSeries> prices,
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
      // Índice de preço em base 1,0 no primeiro pregão da janela: é sobre ele
      // que retorno, risco e beta são apurados, na mesma convenção que o
      // aplicativo usa desde a remoção dos proventos.
      final points = prices[ticker]!
          .points
          .where((point) => window.contains(point.date))
          .toList();
      if (points.length < 2 || points.first.close <= 0) continue;

      final dates = [for (final point in points) point.date];
      final index = [
        for (final point in points) point.close / points.first.close,
      ];
      final totalReturn = index.last / index.first - 1.0;

      final years = DateRange(dates.first, dates.last).years;
      final cagr = Returns.annualize(totalReturn, years);
      final risk = RiskMetrics.fromIndex(
        twrIndex: index,
        cagr: cagr,
        riskFreeRate: riskFree,
      );

      var beta = '';
      var correlation = '';
      var observations = '';
      if (benchmark != null) {
        final aligned = BetaCalculator.alignReturns(
          assetDates: dates,
          assetIndex: index,
          marketDates: benchmark.dates,
          marketIndex: benchmark.points.map((p) => p.close).toList(),
        );
        final estimate = BetaCalculator.estimate(returns: aligned);
        if (estimate.isOk) {
          beta = estimate.unwrap().beta.toStringAsFixed(8);
          correlation = estimate.unwrap().correlation.toStringAsFixed(8);
          observations = '${estimate.unwrap().observations}';
        }
      }

      buffer.writeln([
        ticker.value,
        totalReturn.toStringAsFixed(8),
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
      ..writeln(['desvio_padrao', 'amostral (n-1)'].join(separator));

    writeReport('$outputDir/parametros.csv', parameters.toString());
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
