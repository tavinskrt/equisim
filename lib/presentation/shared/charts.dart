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

  /// Datas de [values], uma para uma.
  ///
  /// Quando informadas, a curva é posicionada **pela data** e não pela ordem
  /// no vetor. Duas séries de tamanhos diferentes desenhadas por índice ficam
  /// alinhadas pela esquerda, e a mais curta parece terminar antes do fim do
  /// período — foi exatamente esse o sintoma relatado na comparação entre as
  /// carteiras.
  final List<DateTime>? dates;

  const ChartSeries({
    required this.label,
    required this.values,
    required this.color,
    this.dates,
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

  /// Eixo horizontal comum a todas as curvas.
  ///
  /// É a união das datas das séries que as informam; sem nenhuma, cai para o
  /// calendário recebido em [dates].
  List<DateTime> get _axis {
    final union = <DateTime>{};
    for (final s in series) {
      final d = s.dates;
      if (d != null) union.addAll(d);
    }
    if (union.isEmpty) return dates;
    return union.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final axis = _axis;
    if (series.isEmpty || axis.length < 2) {
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

    final position = <DateTime, int>{
      for (var i = 0; i < axis.length; i++) axis[i]: i,
    };

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
                    interval: (axis.length / 4).clamp(1, double.infinity),
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= axis.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          Fmt.shortDate.format(axis[index]),
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
                    spots: _spotsOf(s, position),
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

  /// Pontos de uma curva no eixo mestre.
  ///
  /// Sem datas próprias a série é desenhada na ordem em que veio, que é o
  /// comportamento antigo; com datas, cada valor vai para a sua posição no
  /// calendário comum.
  static List<FlSpot> _spotsOf(ChartSeries s, Map<DateTime, int> position) {
    final dates = s.dates;
    if (dates == null) {
      return [
        for (var i = 0; i < s.values.length; i++)
          FlSpot(i.toDouble(), s.values[i]),
      ];
    }

    final spots = <FlSpot>[];
    final count = dates.length < s.values.length ? dates.length : s.values.length;
    for (var i = 0; i < count; i++) {
      final x = position[dates[i]];
      if (x == null) continue;
      spots.add(FlSpot(x.toDouble(), s.values[i]));
    }
    return spots;
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

/// Um ponto da dispersão risco × retorno, em pontos percentuais.
typedef RiskReturnDot = ({
  String label,
  double risk,
  double ret,
  Color color,
  bool highlight,
});

/// Entrada da legenda das nuvens de ativos.
typedef RiskReturnLegend = ({String label, Color color});

/// Dispersão risco × retorno, com as carteiras destacadas entre os ativos.
///
/// Torna o efeito da diversificação visível: a carteira costuma aparecer à
/// esquerda dos seus componentes, com menos volatilidade para retorno
/// comparável.
///
/// Os limites dos eixos são calculados aqui, e não deixados a cargo do
/// `fl_chart`. O padrão da biblioteca é usar exatamente o mínimo e o máximo
/// dos pontos: com um único ponto — que era o caso, porque só a carteira
/// entrava no gráfico — `minX == maxX` e `minY == maxY`, e a conversão de
/// valor para pixel divide por zero. O resultado era um gráfico ilegível.
class RiskReturnScatter extends StatelessWidget {
  final List<RiskReturnDot> points;

  /// Legenda das nuvens de ativos, uma entrada por carteira representada.
  ///
  /// Fica a cargo de quem monta os pontos: só o chamador sabe quais carteiras
  /// entraram na dispersão e com que cor cada nuvem foi desenhada.
  final List<RiskReturnLegend> assetLegend;

  final bool isLight;

  const RiskReturnScatter({
    super.key,
    required this.points,
    required this.isLight,
    this.assetLegend = const [],
  });

  /// Limites de um eixo com folga, tolerando um único ponto ou pontos
  /// coincidentes.
  ///
  /// A folga vertical é maior porque o rótulo do ativo é desenhado acima ou
  /// abaixo do ponto e precisa caber dentro da área do gráfico.
  static (double, double) _bounds(
    Iterable<double> values, {
    required double slack,
  }) {
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo;
    final pad = span > 0 ? span * slack : (hi.abs() * 0.2).clamp(2.0, 20.0);
    return (lo - pad, hi + pad);
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: 230,
        child: EmptyState(
          isLight: isLight,
          icon: Icons.scatter_plot_outlined,
          title: 'Sem dispersão para exibir',
          message: 'A simulação precisa de ao menos um ativo com histórico '
              'suficiente no período.',
        ),
      );
    }

    final (rawMinX, maxX) = _bounds(points.map((p) => p.risk), slack: 0.18);
    final (minY, maxY) = _bounds(points.map((p) => p.ret), slack: 0.28);

    // Volatilidade negativa não existe; cortar em zero evita um eixo que
    // sugere o contrário.
    final minX = rawMinX < 0 ? 0.0 : rawMinX;
    final xInterval = ((maxX - minX) / 4).clamp(0.5, double.infinity);
    final yInterval = ((maxY - minY) / 4).clamp(0.5, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 250,
          child: ScatterChart(
            ScatterChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                horizontalInterval: yInterval,
                verticalInterval: xInterval,
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
                    reservedSize: 42,
                    interval: yInterval,
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
                    interval: xInterval,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${value.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textMuted(isLight),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              scatterLabelSettings: ScatterLabelSettings(
                showLabel: true,
                getLabelFunction: (index, _) => points[index].label,
                getLabelTextStyleFunction: (index, _) => TextStyle(
                  fontSize: 8.5,
                  fontWeight: points[index].highlight
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: points[index].highlight
                      ? points[index].color
                      : AppColors.textMuted(isLight),
                ),
              ),
              scatterTouchData: ScatterTouchData(
                enabled: true,
                touchTooltipData: ScatterTouchTooltipData(
                  getTooltipColor: (_) => (isLight ? Colors.black : Colors.white)
                      .withValues(alpha: 0.82),
                  getTooltipItems: (spot) {
                    final index = points.indexWhere(
                      (p) => p.risk == spot.x && p.ret == spot.y,
                    );
                    if (index < 0) return null;
                    final p = points[index];
                    return ScatterTooltipItem(
                      '${p.label}\n'
                      'vol ${p.risk.toStringAsFixed(1)}% · '
                      'ret ${p.ret.toStringAsFixed(1)}%',
                      textStyle: TextStyle(
                        color: isLight ? Colors.white : Colors.black,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              scatterSpots: [
                for (final p in points)
                  ScatterSpot(
                    p.risk,
                    p.ret,
                    // As carteiras desenham por cima da nuvem de ativos.
                    renderPriority: p.highlight ? 1 : 0,
                    dotPainter: FlDotCirclePainter(
                      radius: p.highlight ? 8 : 4.5,
                      color: p.color,
                      strokeWidth: p.highlight ? 2 : 0,
                      strokeColor: AppColors.backgroundStart(isLight),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final p in points.where((p) => p.highlight))
              _LegendDot(label: p.label, color: p.color, isLight: isLight),
            for (final entry in assetLegend)
              _LegendDot(
                label: entry.label,
                color: entry.color,
                isLight: isLight,
              ),
          ],
        ),
      ],
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
