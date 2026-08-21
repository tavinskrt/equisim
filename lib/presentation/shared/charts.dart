import 'package:equisim_core/equisim_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import 'ui_kit.dart';

/// Uma curva nomeada.
class ChartSeries {
  final String label;
  final List<double> values;
  final Color color;

  const ChartSeries({
    required this.label,
    required this.values,
    required this.color,
  });
}

/// Gráfico de linhas para curvas normalizadas em base 100.
///
/// Base 100 é o que torna carteiras de tamanhos diferentes comparáveis: o eixo
/// deixa de medir dinheiro e passa a medir desempenho relativo.
class Base100Chart extends StatelessWidget {
  final List<ChartSeries> series;
  final List<DateTime> dates;
  final bool isLight;
  final double height;

  const Base100Chart({
    super.key,
    required this.series,
    required this.dates,
    required this.isLight,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || dates.length < 2) {
      return SizedBox(
        height: height,
        child: EmptyState(
          isLight: isLight,
          icon: Icons.show_chart,
          title: 'Sem série para exibir',
          message: 'Defina a carteira e o plano de aportes.',
        ),
      );
    }

    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final s in series) {
      for (final v in s.values) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }
    final padding = ((maxY - minY) * 0.08).clamp(1.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in series) _LegendDot(label: s.label, color: s.color, isLight: isLight),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: minY - padding,
              maxY: maxY + padding,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.divider(isLight),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted(isLight),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: (dates.length / 4).clamp(1, double.infinity),
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= dates.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          Fmt.shortDate.format(dates[index]),
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.textMuted(isLight),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((spot) {
                    final s = series[spot.barIndex];
                    return LineTooltipItem(
                      '${s.label}: ${spot.y.toStringAsFixed(1)}',
                      TextStyle(
                        color: s.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < s.values.length; i++)
                        FlSpot(i.toDouble(), s.values[i]),
                    ],
                    isCurved: false,
                    barWidth: 2,
                    color: s.color,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: s.color.withValues(alpha: 0.08),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Gráfico tornado: quanto cada premissa move o preço justo.
///
/// Responde a pergunta que a banca costuma fazer sobre um DCF — "de que
/// depende esse número?" — em vez de deixá-la implícita.
class TornadoChart extends StatelessWidget {
  final List<({String label, double low, double high})> bars;
  final double baseValue;
  final bool isLight;

  const TornadoChart({
    super.key,
    required this.bars,
    required this.baseValue,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();

    var maxSpan = 0.0;
    for (final bar in bars) {
      final span = ((bar.high - baseValue).abs())
          .clamp(0.0, double.infinity)
          .toDouble();
      final low = ((baseValue - bar.low).abs()).toDouble();
      maxSpan = [maxSpan, span, low].reduce((a, b) => a > b ? a : b);
    }
    if (maxSpan <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final bar in bars) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    bar.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(isLight),
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 18,
                    child: CustomPaint(
                      painter: _TornadoBarPainter(
                        low: bar.low,
                        high: bar.high,
                        base: baseValue,
                        maxSpan: maxSpan,
                        isLight: isLight,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '${Fmt.money(bar.low)} — ${Fmt.money(bar.high)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textMuted(isLight),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TornadoBarPainter extends CustomPainter {
  final double low;
  final double high;
  final double base;
  final double maxSpan;
  final bool isLight;

  _TornadoBarPainter({
    required this.low,
    required this.high,
    required this.base,
    required this.maxSpan,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final scale = center / maxSpan;

    final leftWidth = ((base - low) * scale).clamp(0.0, center);
    final rightWidth = ((high - base) * scale).clamp(0.0, center);

    final downPaint = Paint()..color = AppColors.danger.withValues(alpha: 0.7);
    final upPaint = Paint()..color = AppColors.primary.withValues(alpha: 0.7);

    canvas.drawRect(
      Rect.fromLTWH(center - leftWidth, 3, leftWidth, size.height - 6),
      downPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(center, 3, rightWidth, size.height - 6),
      upPaint,
    );

    canvas.drawLine(
      Offset(center, 0),
      Offset(center, size.height),
      Paint()
        ..color = AppColors.textSecondary(isLight)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _TornadoBarPainter old) =>
      old.low != low || old.high != high || old.base != base;
}

/// Dispersão risco × retorno, com a carteira destacada entre os ativos.
///
/// Torna o efeito da diversificação visível: a carteira aparece à esquerda dos
/// componentes, com menos volatilidade para retorno comparável.
class RiskReturnScatter extends StatelessWidget {
  final List<({String label, double risk, double ret, bool highlight})> points;
  final bool isLight;

  const RiskReturnScatter({
    super.key,
    required this.points,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 230,
      child: ScatterChart(
        ScatterChartData(
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppColors.divider(isLight), strokeWidth: 1),
            getDrawingVerticalLine: (_) =>
                FlLine(color: AppColors.divider(isLight), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              axisNameWidget: Text(
                'Retorno a.a.',
                style: TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textMuted(isLight),
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted(isLight),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: Text(
                'Volatilidade a.a.',
                style: TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textMuted(isLight),
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted(isLight),
                  ),
                ),
              ),
            ),
          ),
          scatterSpots: [
            for (final p in points)
              ScatterSpot(
                p.risk,
                p.ret,
                dotPainter: FlDotCirclePainter(
                  radius: p.highlight ? 8 : 5,
                  color: p.highlight
                      ? AppColors.primary
                      : AppColors.textSecondary(isLight),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mapa de calor da matriz de correlação.
class CorrelationHeatmap extends StatelessWidget {
  final List<Ticker> tickers;
  final List<List<double>> matrix;
  final bool isLight;

  const CorrelationHeatmap({
    super.key,
    required this.tickers,
    required this.matrix,
    required this.isLight,
  });

  Color _cellColor(double rho) {
    // Verde para correlação baixa (diversificação) e vermelho para alta.
    final normalized = ((rho + 1) / 2).clamp(0.0, 1.0);
    return Color.lerp(
      AppColors.primary.withValues(alpha: 0.65),
      AppColors.danger.withValues(alpha: 0.65),
      normalized,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    if (tickers.length < 2) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 58),
              for (final t in tickers)
                SizedBox(
                  width: 46,
                  child: Text(
                    t.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppColors.textMuted(isLight),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          for (var i = 0; i < tickers.length; i++)
            Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    tickers[i].value,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppColors.textMuted(isLight),
                    ),
                  ),
                ),
                for (var j = 0; j < tickers.length; j++)
                  Container(
                    width: 44,
                    height: 26,
                    margin: const EdgeInsets.all(1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cellColor(matrix[i][j]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      matrix[i][j].toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool isLight;

  const _LegendDot({
    required this.label,
    required this.color,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary(isLight),
          ),
        ),
      ],
    );
  }
}
