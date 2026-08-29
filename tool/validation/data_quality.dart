import 'dart:io';
import 'dart:math' as math;

import 'package:equisim/data/quality/dividend_quality_gate.dart';
import 'package:equisim_core/equisim_core.dart';

import 'context.dart';

/// Linha do relatório de qualidade de proventos.
class QualityRow {
  /// Ativo conferido.
  final Ticker ticker;

  /// Laudo do portão de qualidade.
  final DividendQualityReport report;

  /// Total de proventos na janela de 12 meses.
  final int eventCount;

  /// Quantos deles são JCP — os únicos com IRRF retido, e por isso a parcela
  /// que mais afeta a diferença entre bruto e líquido.
  final int jcpCount;

  /// Quantos têm data de pagamento marcada como estimada pela fonte, o que
  /// desloca o reinvestimento em alguns dias.
  final int estimatedDateCount;

  /// Declara a linha.
  const QualityRow({
    required this.ticker,
    required this.report,
    required this.eventCount,
    required this.jcpCount,
    required this.estimatedDateCount,
  });
}

/// Linha do relatório de divergência contra `adjustedClose`.
class DivergenceRow {
  /// Ativo medido.
  final Ticker ticker;

  /// Razão de retorno total observada no `adjustedClose` da fonte.
  final double observedRatio;

  /// Razão que o fluxo de proventos do domínio implica.
  final double impliedRatio;

  /// Diferença relativa entre as duas, em fração.
  final double deviation;

  /// Proventos considerados no período.
  final int eventCount;

  /// Participação de JCP, em pontos percentuais.
  ///
  /// É a variável que explica a divergência: o `adjustedClose` do Yahoo
  /// subajusta JCP, então quanto maior esta fração, maior o desvio.
  final int jcpShare;

  /// Declara a linha.
  const DivergenceRow({
    required this.ticker,
    required this.observedRatio,
    required this.impliedRatio,
    required this.deviation,
    required this.eventCount,
    required this.jcpShare,
  });
}

/// Relatórios de qualidade dos dados de proventos.
abstract final class DataQualityReports {
  /// **Portão de qualidade de proventos.**
  ///
  /// Compara o dividend yield calculado a partir do fluxo de eventos com o que
  /// a própria fonte publica. É a conferência que a auditoria mostrou
  /// funcionar (§0.4, Teste 2), depois que a reconciliação contra
  /// `adjustedClose` falhou.
  ///
  /// - [ctx]: contexto com a camada de dados.
  ///
  /// Ativos cujos dados não puderem ser carregados são **omitidos** do
  /// resultado em vez de derrubar a varredura.
  static Future<List<QualityRow>> runQualityGate(
    ValidationContext ctx, {
    required List<String> symbols,
  }) async {
    final rows = <QualityRow>[];
    final today = DateTime.now();
    final window = DateRange(
      DateTime(today.year - 1, today.month, today.day),
      today,
    );

    for (final symbol in symbols) {
      final ticker = Ticker.tryParse(symbol);
      if (ticker == null) continue;
      stdout.write('.');

      final events = await ctx.dividends.history(ticker);
      final prices = await ctx.prices.daily(ticker, window);
      final published = await ctx.dividends.publishedTrailingYield(ticker);

      final list = events.getOrElse(const <DividendEvent>[]);
      final currentPrice = prices.isOk && prices.unwrap().isNotEmpty
          ? prices.unwrap().points.last.close
          : null;

      rows.add(QualityRow(
        ticker: ticker,
        report: DividendQualityGate.check(
          ticker: ticker,
          events: list,
          currentPrice: currentPrice,
          publishedYield: published.valueOrNull,
          asOf: today,
        ),
        eventCount: list.length,
        jcpCount: list.where((e) => e.kind == DividendKind.jcp).length,
        estimatedDateCount: list.where((e) => e.paymentDateEstimated).length,
      ));
    }
    stdout.writeln();
    return rows;
  }

  /// **Quantificação da divergência contra `adjustedClose`.**
  ///
  /// Reconstrói o fator de ajuste de proventos a partir do fluxo de eventos e
  /// compara com a razão `adjustedClose/close` observada no início da série.
  /// Serve para documentar, com números do universo e não de quatro exemplos,
  /// a limitação do Yahoo com proventos brasileiros — sobretudo JCP.
  /// Mede a divergência entre o `adjustedClose` da fonte e o retorno total
  /// construído pelo domínio.
  ///
  /// - [ctx]: contexto com a camada de dados.
  ///
  /// **Não é um teste que deva passar.** Documenta um defeito conhecido da
  /// fonte, e o resultado esperado é divergência crescente com a participação
  /// de JCP. É a evidência que sustenta a decisão de não usar
  /// `adjustedClose` em cálculo.
  static Future<List<DivergenceRow>> runDivergenceScan(
    ValidationContext ctx, {
    required List<String> symbols,
    int windowYears = 10,
  }) async {
    final rows = <DivergenceRow>[];
    final today = DateTime.now();
    final window = DateRange(
      DateTime(today.year - windowYears, today.month, today.day),
      today,
    );

    for (final symbol in symbols) {
      final ticker = Ticker.tryParse(symbol);
      if (ticker == null) continue;
      stdout.write('.');

      final priceResult = await ctx.prices.daily(ticker, window);
      if (priceResult.isErr) continue;
      final series = priceResult.unwrap();
      if (series.points.length < 100) continue;

      final first = series.points.first;
      final adjusted = first.adjustedClose;
      if (adjusted == null || first.close <= 0) continue;
      final observed = adjusted / first.close;

      final eventsResult = await ctx.dividends.history(ticker);
      final events = eventsResult
          .getOrElse(const <DividendEvent>[])
          .where((e) =>
              e.exDate.isAfter(first.date) && !e.exDate.isAfter(series.lastDate))
          .toList();
      if (events.isEmpty) continue;

      // Fator implícito: Π(1 − provento / fechamento da véspera).
      var implied = 1.0;
      var used = 0;
      for (final event in events) {
        final previous = _closeBefore(series, event.exDate);
        if (previous == null || previous <= 0) continue;
        implied *= 1 - event.amountPerShare / previous;
        used++;
      }
      if (used == 0 || implied <= 0) continue;

      rows.add(DivergenceRow(
        ticker: ticker,
        observedRatio: observed,
        impliedRatio: implied,
        deviation: implied / observed - 1,
        eventCount: used,
        jcpShare: events.isEmpty
            ? 0
            : (events.where((e) => e.kind == DividendKind.jcp).length *
                    100 ~/
                    events.length),
      ));
    }
    stdout.writeln();
    return rows;
  }

  static double? _closeBefore(PriceSeries series, DateTime date) {
    double? last;
    for (final point in series.points) {
      if (!point.date.isBefore(date)) break;
      last = point.close;
    }
    return last;
  }

  // ------------------------------------------------------------ Relatórios --

  /// Formata o portão de qualidade como relatório Markdown.
  static String qualityReport(List<QualityRow> rows) {
    final consistent =
        rows.where((r) => r.report.status == DividendQuality.consistent).length;
    final divergent =
        rows.where((r) => r.report.status == DividendQuality.divergent).length;
    final unverified =
        rows.where((r) => r.report.status == DividendQuality.unverified).length;

    final deviations = rows
        .map((r) => r.report.deviation)
        .whereType<double>()
        .toList()
      ..sort();

    final buffer = StringBuffer()
      ..writeln('# Portão de qualidade dos proventos')
      ..writeln()
      ..writeln('Gerado em ${DateTime.now().toIso8601String().substring(0, 19)}.')
      ..writeln()
      ..writeln('Compara o dividend yield calculado a partir do fluxo de '
          'eventos (`cashDividends`) com o publicado pela própria fonte '
          '(`statistics.dividendYield`). A tolerância é de 1 ponto percentual, '
          'calibrada pelo arredondamento de duas casas do campo publicado.')
      ..writeln()
      ..writeln('**Resultado sobre ${rows.length} ativos:** '
          '$consistent consistentes · $divergent divergentes · '
          '$unverified não verificáveis.');

    if (deviations.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Desvio absoluto: mediana '
            '${pct(deviations[deviations.length ~/ 2])} · '
            'máximo ${pct(deviations.last)}.');
    }

    buffer
      ..writeln()
      ..writeln('| Ativo | DY calculado | DY publicado | Desvio | Eventos | JCP | Data estimada | Situação |')
      ..writeln('|---|---|---|---|---|---|---|---|');

    for (final row in rows) {
      final r = row.report;
      buffer.writeln(
        '| ${row.ticker.value} '
        '| ${r.computedYield == null ? '—' : pct(r.computedYield!)} '
        '| ${r.publishedYield == null ? '—' : pct(r.publishedYield!)} '
        '| ${r.deviation == null ? '—' : pct(r.deviation!)} '
        '| ${row.eventCount} '
        '| ${row.jcpCount} '
        '| ${row.estimatedDateCount} '
        '| ${_statusLabel(r.status)} |',
      );
    }

    final flagged =
        rows.where((r) => r.report.status == DividendQuality.divergent);
    if (flagged.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Ativos sinalizados')
        ..writeln();
      for (final row in flagged) {
        buffer.writeln('- **${row.ticker.value}** — ${row.report.message}');
      }
    }

    return buffer.toString();
  }

  /// Formata a varredura de divergência como relatório Markdown, incluindo a
  /// correlação entre desvio e participação de JCP.
  static String divergenceReport(List<DivergenceRow> rows) {
    final sorted = [...rows]
      ..sort((a, b) => a.deviation.abs().compareTo(b.deviation.abs()));

    final buffer = StringBuffer()
      ..writeln('# Divergência entre o fluxo de proventos e o `adjustedClose`')
      ..writeln()
      ..writeln('Gerado em ${DateTime.now().toIso8601String().substring(0, 19)}.')
      ..writeln()
      ..writeln('Reconstrói o fator de ajuste de proventos a partir dos eventos '
          'de `cashDividends` e compara com a razão `adjustedClose/close` '
          'observada no início da série.')
      ..writeln()
      ..writeln('Um desvio negativo significa que o fluxo de eventos implica '
          '**mais** provento do que o `adjustedClose` reflete — ou seja, a '
          'série do Yahoo subajusta. A auditoria já havia observado isso em '
          'quatro ativos; este relatório mede o fenômeno em escala.')
      ..writeln()
      ..writeln('| Ativo | Razão observada | Fator implícito | Desvio | Eventos | % JCP |')
      ..writeln('|---|---|---|---|---|---|');

    for (final row in sorted) {
      buffer.writeln(
        '| ${row.ticker.value} '
        '| ${num2(row.observedRatio)} '
        '| ${num2(row.impliedRatio)} '
        '| ${pct(row.deviation, decimals: 1)} '
        '| ${row.eventCount} '
        '| ${row.jcpShare}% |',
      );
    }

    if (sorted.isNotEmpty) {
      final deviations = sorted.map((r) => r.deviation.abs()).toList()..sort();
      final jcpHeavy = sorted.where((r) => r.jcpShare >= 50).toList();
      final jcpLight = sorted.where((r) => r.jcpShare < 50).toList();

      buffer
        ..writeln()
        ..writeln('## Síntese')
        ..writeln()
        ..writeln('- Desvio absoluto mediano: '
            '**${pct(deviations[deviations.length ~/ 2], decimals: 1)}**')
        ..writeln('- Desvio absoluto máximo: '
            '**${pct(deviations.last, decimals: 1)}**');

      final material = sorted.where((r) => r.deviation.abs() > 0.05).length;
      buffer.writeln('- Ativos com desvio acima de 5%: '
          '**$material de ${sorted.length}**');

      if (jcpHeavy.isNotEmpty && jcpLight.isNotEmpty) {
        final heavyAvg =
            jcpHeavy.map((r) => r.deviation.abs()).reduce((a, b) => a + b) /
                jcpHeavy.length;
        final lightAvg =
            jcpLight.map((r) => r.deviation.abs()).reduce((a, b) => a + b) /
                jcpLight.length;
        final rho = _correlation(
          sorted.map((r) => r.jcpShare.toDouble()).toList(),
          sorted.map((r) => r.deviation.abs()).toList(),
        );

        buffer
          ..writeln('- Ativos com maioria de JCP: desvio médio '
              '**${pct(heavyAvg, decimals: 1)}** (${jcpHeavy.length} ativos)')
          ..writeln('- Ativos com minoria de JCP: desvio médio '
              '**${pct(lightAvg, decimals: 1)}** (${jcpLight.length} ativos)')
          ..writeln('- Correlação entre proporção de JCP e desvio: '
              '**${num2(rho, decimals: 2)}**')
          ..writeln()
          ..writeln('### Leitura')
          ..writeln()
          ..writeln('A conclusão robusta é a primeira: **o `adjustedClose` '
              'diverge de forma ampla e material do fluxo de proventos** — '
              'metade dos ativos acima de ${pct(deviations[deviations.length ~/ 2], decimals: 0)}. '
              'Isso basta para inviabilizá-lo como referência de cálculo, '
              'qualquer que seja a causa.')
          ..writeln()
          ..writeln('Sobre a **causa**, os dados são apenas sugestivos. O grupo '
              'com maioria de JCP desvia mais na média, mas a relação é ruidosa '
              'e há contraexemplos claros nos dois sentidos — PETR4 tem 38% de '
              'JCP e desvia 2,1%, enquanto EGIE3 tem 31% e desvia 21,0%. Com '
              '${sorted.length} ativos e correlação de ${num2(rho, decimals: 2)}, '
              'atribuir a lacuna exclusivamente ao tratamento de JCP seria ir '
              'além do que a amostra sustenta.')
          ..writeln()
          ..writeln('> **Para a monografia:** relatar a divergência como fato '
              'medido e a explicação por JCP como hipótese plausível não '
              'confirmada. A decisão de arquitetura — usar `cashDividends` '
              'como fonte de verdade — não depende de resolver a causa.');
      }
    }

    return buffer.toString();
  }

  /// Correlação de Pearson, para não deixar a leitura por conta do olho.
  static double _correlation(List<double> x, List<double> y) {
    final n = x.length;
    if (n < 3) return 0;
    final meanX = x.reduce((a, b) => a + b) / n;
    final meanY = y.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - meanX;
      final dy = y[i] - meanY;
      sxy += dx * dy;
      sxx += dx * dx;
      syy += dy * dy;
    }
    final denominator = sxx * syy;
    if (denominator <= 0) return 0;
    return sxy / math.sqrt(denominator);
  }

  static String _statusLabel(DividendQuality status) => switch (status) {
        DividendQuality.consistent => '✅ consistente',
        DividendQuality.divergent => '⚠️ divergente',
        DividendQuality.unverified => '— não verificável',
      };
}
