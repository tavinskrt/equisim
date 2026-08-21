import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'context.dart';

/// Avaliação de um ativo sob uma configuração de premissas.
class SensitivityPoint {
  final Ticker ticker;
  final String scenario;
  final ValuationModel? model;
  final double? fairValue;
  final double? discountRate;
  final String? failure;

  const SensitivityPoint({
    required this.ticker,
    required this.scenario,
    this.model,
    this.fairValue,
    this.discountRate,
    this.failure,
  });
}

abstract final class SensitivityReports {
  /// Varre a amostra medindo a sensibilidade do preço justo às premissas.
  ///
  /// Três eixos, escolhidos porque são exatamente os que uma banca questiona
  /// num DCF: a defasagem de publicação assumida, o prêmio de risco de mercado
  /// (que é parâmetro declarado, não observado) e o horizonte de projeção.
  static Future<List<SensitivityPoint>> run(
    ValidationContext ctx, {
    required List<String> symbols,
  }) async {
    final points = <SensitivityPoint>[];
    final today = DateTime.now();

    for (final symbol in symbols) {
      final ticker = Ticker.tryParse(symbol);
      if (ticker == null) continue;
      stdout.write('.');

      final anchors = await ResolveMarketAnchors.call(
        macro: ctx.macro,
        benchmark: ctx.benchmark,
      );
      final riskFree = anchors
          .getOrElse(MarketAnchors.fallback2026)
          .riskFreeCagr;

      final base = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        dividends: ctx.dividends,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: riskFree,
        asOf: today,
      );

      if (base.isErr) {
        points.add(SensitivityPoint(
          ticker: ticker,
          scenario: 'base',
          failure: base.failureOrNull!.message,
        ));
        continue;
      }

      final inputs = base.unwrap();

      // Eixo 1 — defasagem de publicação assumida.
      for (final lagDays in [0, 90, 180, 365]) {
        final view = PointInTimeView(today, publicationLag: Duration(days: lagDays));
        final visible = view.published(inputs.fundamentals);
        points.add(_evaluate(
          ValuationInputs(
            ticker: ticker,
            asOf: today,
            fundamentals: visible,
            dividends: inputs.dividends,
            marketPrice: inputs.marketPrice,
            capm: inputs.capm,
          ),
          'defasagem ${lagDays}d',
        ));
      }

      // Eixo 2 — prêmio de risco de mercado.
      for (final premium in [0.045, 0.055, 0.065]) {
        points.add(_evaluate(
          ValuationInputs(
            ticker: ticker,
            asOf: today,
            fundamentals: inputs.fundamentals,
            dividends: inputs.dividends,
            marketPrice: inputs.marketPrice,
            capm: CapmInputs(
              riskFreeRate: inputs.capm.riskFreeRate,
              beta: inputs.capm.beta,
              marketPremium: premium,
              betaSource: inputs.capm.betaSource,
            ),
          ),
          'prêmio ${pct(premium, decimals: 1)}',
        ));
      }

      // Eixo 3 — horizonte de projeção explícita.
      for (final years in [3, 5, 10]) {
        points.add(_evaluate(
          ValuationInputs(
            ticker: ticker,
            asOf: today,
            fundamentals: inputs.fundamentals,
            dividends: inputs.dividends,
            marketPrice: inputs.marketPrice,
            capm: inputs.capm,
            projectionYears: years,
          ),
          'projeção ${years}a',
        ));
      }
    }
    stdout.writeln();
    return points;
  }

  static SensitivityPoint _evaluate(ValuationInputs inputs, String scenario) {
    final result = ValuationCascade.evaluate(inputs);
    return result.fold(
      (valuation) => SensitivityPoint(
        ticker: inputs.ticker,
        scenario: scenario,
        model: valuation.model,
        fairValue: valuation.fairValue.reais,
        discountRate: valuation.discountRate,
      ),
      (failure) => SensitivityPoint(
        ticker: inputs.ticker,
        scenario: scenario,
        failure: failure.message,
      ),
    );
  }

  static String report(List<SensitivityPoint> points) {
    final byTicker = <Ticker, List<SensitivityPoint>>{};
    for (final point in points) {
      (byTicker[point.ticker] ??= []).add(point);
    }

    final buffer = StringBuffer()
      ..writeln('# Sensibilidade da avaliação às premissas')
      ..writeln()
      ..writeln('Gerado em ${DateTime.now().toIso8601String().substring(0, 19)}.')
      ..writeln()
      ..writeln('Mede quanto o preço justo se move ao variar três premissas '
          'declaradas: a defasagem de publicação dos demonstrativos, o prêmio '
          'de risco de mercado e o horizonte de projeção explícita. Nenhuma '
          'das três é observável — todas são escolhas metodológicas, e o '
          'trabalho precisa mostrar o peso de cada uma.')
      ..writeln();

    // --- Distribuição dos modelos aplicados ---
    final modelCounts = <ValuationModel, int>{};
    var failures = 0;
    for (final point in points) {
      if (point.model != null) {
        modelCounts[point.model!] = (modelCounts[point.model!] ?? 0) + 1;
      } else {
        failures++;
      }
    }

    buffer
      ..writeln('## Modelos efetivamente aplicados')
      ..writeln()
      ..writeln('A cascata escolhe o modelo mais exigente que os dados '
          'sustentam. A distribuição abaixo indica a qualidade média dos dados '
          'disponíveis na fonte.')
      ..writeln()
      ..writeln('| Modelo | Ocorrências |')
      ..writeln('|---|---|');
    for (final entry in modelCounts.entries) {
      buffer.writeln('| ${entry.key.label} | ${entry.value} |');
    }
    if (failures > 0) {
      buffer.writeln('| *(não avaliável)* | $failures |');
    }

    // --- Amplitude por ativo ---
    buffer
      ..writeln()
      ..writeln('## Amplitude do preço justo por ativo')
      ..writeln()
      ..writeln('| Ativo | Mínimo | Base | Máximo | Amplitude | Premissa mais influente |')
      ..writeln('|---|---|---|---|---|---|');

    for (final entry in byTicker.entries) {
      final valued =
          entry.value.where((p) => p.fairValue != null).toList();
      if (valued.isEmpty) {
        buffer.writeln(
          '| ${entry.key.value} | — | — | — | — | '
          '${entry.value.first.failure ?? 'sem dados'} |',
        );
        continue;
      }

      final values = valued.map((p) => p.fairValue!).toList()..sort();
      final baseline = valued.firstWhere(
        (p) => p.scenario == 'defasagem 90d',
        orElse: () => valued.first,
      );
      final spread = baseline.fairValue! > 0
          ? (values.last - values.first) / baseline.fairValue!
          : 0.0;

      buffer.writeln(
        '| ${entry.key.value} '
        '| ${num2(values.first, decimals: 2)} '
        '| ${num2(baseline.fairValue!, decimals: 2)} '
        '| ${num2(values.last, decimals: 2)} '
        '| ${pct(spread, decimals: 0)} '
        '| ${_mostInfluential(valued, baseline.fairValue!)} |',
      );
    }

    // --- Detalhamento ---
    buffer
      ..writeln()
      ..writeln('## Detalhamento')
      ..writeln()
      ..writeln('| Ativo | Cenário | Modelo | Preço justo | Taxa de desconto |')
      ..writeln('|---|---|---|---|---|');
    for (final point in points) {
      buffer.writeln(
        '| ${point.ticker.value} '
        '| ${point.scenario} '
        '| ${point.model?.label ?? '—'} '
        '| ${point.fairValue == null ? '—' : num2(point.fairValue!, decimals: 2)} '
        '| ${point.discountRate == null ? '—' : pct(point.discountRate!)} |',
      );
    }

    return buffer.toString();
  }

  /// Qual eixo produz o maior desvio em relação ao cenário central.
  static String _mostInfluential(
    List<SensitivityPoint> points,
    double baseline,
  ) {
    if (baseline <= 0) return '—';
    final byAxis = <String, double>{};
    for (final point in points) {
      if (point.fairValue == null) continue;
      final axis = point.scenario.split(' ').first;
      final deviation = (point.fairValue! - baseline).abs() / baseline;
      if (deviation > (byAxis[axis] ?? 0)) byAxis[axis] = deviation;
    }
    if (byAxis.isEmpty) return '—';
    final worst =
        byAxis.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return '${worst.key} (${pct(worst.value, decimals: 0)})';
  }
}
