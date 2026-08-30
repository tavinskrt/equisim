import 'package:equisim_core/equisim_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../components/fin_amount.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'ui_kit.dart';

/// Uma curva nomeada.
class ChartSeries {
  /// Nome da série, para a legenda.
  final String label;

  /// Pontos da série, alinhados posição a posição com o eixo de datas do
  /// gráfico que a recebe. Séries de comprimentos diferentes são desenhadas
  /// até onde alcançam, sem erro.
  final List<double> values;

  /// Cor da linha e do ponto de legenda.
  final Color color;

  /// Datas de [values], uma para uma.
  ///
  /// Quando informadas, a curva é posicionada **pela data** e não pela ordem
  /// no vetor. Duas séries de tamanhos diferentes desenhadas por índice ficam
  /// alinhadas pela esquerda, e a mais curta parece terminar antes do fim do
  /// período — foi exatamente esse o sintoma relatado na comparação entre as
  /// carteiras.
  final List<DateTime>? dates;

  /// Declara a série. Informe [dates] sempre que as séries do mesmo gráfico
  /// puderem ter comprimentos diferentes.
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
  /// Séries a desenhar. Todas compartilham o mesmo eixo temporal.
  final List<ChartSeries> series;

  /// Eixo temporal comum, em ordem cronológica.
  final List<DateTime> dates;

  /// Tema corrente.
  final bool isLight;

  /// Altura do gráfico em pixels lógicos.
  final double height;

  /// Declara o gráfico.
  ///
  /// Espera séries **normalizadas em base 100** — o índice TWR, não a curva
  /// bruta de patrimônio, que salta no dia do aporte.
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
      // `minHeight`, e nao `height`: a altura declarada e a do GRAFICO, e o
      // estado vazio que ocupa o lugar dele carrega titulo mais mensagem.
      // Travar o teto faz o texto estourar assim que a escala de fonte sobe --
      // o mesmo defeito ja corrigido na coluna de carteira vazia.
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: EmptyState(
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
            for (final s in series)
              _LegendDot(label: s.label, color: s.color, isLight: isLight),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          child: // Curva de patrimônio: repinta só quando a série muda, não a
              // cada quadro de rolagem da lista que a contém.
              RepaintBoundary(
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
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
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
                            '${s.label}: ${Fmt.ratio(spot.y, decimals: 1)}',
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
    final count = dates.length < s.values.length
        ? dates.length
        : s.values.length;
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
  /// Barras de sensibilidade: o rótulo da premissa e os valores resultantes
  /// nos extremos dela.
  final List<({String label, double low, double high})> bars;

  /// Valor do cenário central, onde fica a linha de referência vertical.
  final double baseValue;

  /// Tema corrente.
  final bool isLight;

  /// Declara o gráfico de tornado.
  ///
  /// A ordenação das barras é responsabilidade do chamador — o gráfico desenha
  /// na ordem recebida, e a convenção do formato é da premissa mais sensível
  /// para a menos.
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
                    child: RepaintBoundary(
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
/// O ponto mais próximo de uma coordenada tocada.
///
/// Existe para NÃO comparar `double` por igualdade. O ponto tocado é sempre um
/// dos que desenhamos, então a igualdade exata "funciona" quase sempre — e é
/// justamente esse quase que a torna traiçoeira: basta o `fl_chart` devolver a
/// coordenada com um bit de diferença (`12.345000000000001` contra `12.345`)
/// para o `indexWhere` não achar nada e a legenda não abrir, sem erro nenhum.
///
/// Distância quadrática dispensa escolher um epsilon, que teria de ser
/// calibrado para duas grandezas de escalas diferentes — volatilidade e
/// retorno. O mínimo é sempre bem definido.
RiskReturnDot? _nearest(List<RiskReturnDot> points, double x, double y) {
  if (points.isEmpty) return null;

  var melhor = points.first;
  var menor = double.infinity;

  for (final p in points) {
    final dx = p.risk - x;
    final dy = p.ret - y;
    final d = dx * dx + dy * dy;
    if (d < menor) {
      menor = d;
      melhor = p;
    }
  }
  return melhor;
}

class RiskReturnScatter extends StatelessWidget {
  /// Pontos do gráfico: um por ativo e um por carteira.
  final List<RiskReturnDot> points;

  /// Legenda das nuvens de ativos, uma entrada por carteira representada.
  ///
  /// Fica a cargo de quem monta os pontos: só o chamador sabe quais carteiras
  /// entraram na dispersão e com que cor cada nuvem foi desenhada.
  final List<RiskReturnLegend> assetLegend;

  /// Tema corrente.
  final bool isLight;

  /// Declara a dispersão.
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
      // Ver a justificativa em `Base100Chart`: piso, nao teto.
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 230),
        child: EmptyState(
          icon: Icons.scatter_plot_outlined,
          title: 'Sem dispersão para exibir',
          message:
              'A simulação precisa de ao menos um ativo com histórico '
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
          child: RepaintBoundary(
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
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
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
                    getTooltipColor: (_) =>
                        // A dica inverte em relacao ao fundo: escura no tema
                        // claro e clara no escuro. `textPrimary` ja carrega
                        // exatamente essa inversao.
                        context.fin.textPrimary.withValues(alpha: 0.82),
                    getTooltipItems: (spot) {
                      final p = _nearest(points, spot.x, spot.y);
                      if (p == null) return null;
                      return ScatterTooltipItem(
                        '${p.label}\n'
                        'vol ${Fmt.ratio(p.risk, decimals: 1)}% · '
                        'ret ${Fmt.ratio(p.ret, decimals: 1)}%',
                        textStyle: TextStyle(
                          color: context.fin.surface,
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
///
/// É stateful apenas por causa do [ScrollController]: a rolagem horizontal
/// sempre existiu, mas sem barra visível ninguém descobria que havia colunas
/// além da borda — a auditoria visual flagrou a matriz como "cortada". Manter
/// a barra sempre à mostra exige um controlador com ciclo de vida próprio.
class CorrelationHeatmap extends StatefulWidget {
  /// Ativos, na mesma ordem das linhas e colunas de [matrix].
  final List<Ticker> tickers;

  /// Matriz de correlação `n × n`, simétrica, com valores em `[-1, 1]`.
  final List<List<double>> matrix;

  /// Tema corrente.
  final bool isLight;

  /// Declara o mapa de calor.
  ///
  /// [matrix] precisa ter a mesma dimensão de [tickers]; a construção fica com
  /// `BetaCalculator.correlationMatrix`, que garante a simetria.
  const CorrelationHeatmap({
    super.key,
    required this.tickers,
    required this.matrix,
    required this.isLight,
  });

  @override
  State<CorrelationHeatmap> createState() => _CorrelationHeatmapState();
}

class _CorrelationHeatmapState extends State<CorrelationHeatmap> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Ticker> get tickers => widget.tickers;
  List<List<double>> get matrix => widget.matrix;
  bool get isLight => widget.isLight;

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

    // Grade medida, nao declarada. O container ROLA na horizontal, entao
    // largura maior nao estoura nada -- so exige mais rolagem. Com constante,
    // o ticker de seis letras sob fonte ampliada era cortado dentro da propria
    // celula, e o usuario nao tinha como saber que faltava letra.
    // `tipo`, e nao `t`: o laco de cabecalho abaixo declara `for (final t in
    // tickers)` e sombrearia a tipografia com um Ticker.
    final tipo = context.finType;
    final rotulo = tipo.caption;
    var nomeWidth = 0.0;
    for (final ticker in tickers) {
      final w = FinAmount.measure(context, ticker.value, rotulo);
      if (w > nomeWidth) nomeWidth = w;
    }
    // Medida no papel NUMERICO, que e o que a celula realmente pinta.
    final celulaWidth =
        FinAmount.measure(context, '-0,00', tipo.numSm) + FinSpace.sm;

    return Scrollbar(
      controller: _controller,
      // Sempre visível: numa matriz que já chega cortada na borda, a barra é a
      // única pista de que existem colunas adiante.
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        // Espaço para a barra não cobrir a última linha da matriz.
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: nomeWidth + FinSpace.md),
                for (final t in tickers)
                  SizedBox(
                    width: celulaWidth + 2,
                    child: Text(
                      t.value,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rotulo.copyWith(color: context.fin.textTertiary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            for (var i = 0; i < tickers.length; i++)
              Row(
                children: [
                  SizedBox(
                    width: nomeWidth + FinSpace.md,
                    child: Text(
                      tickers[i].value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: rotulo.copyWith(color: context.fin.textTertiary),
                    ),
                  ),
                  for (var j = 0; j < tickers.length; j++)
                    Builder(
                      builder: (context) {
                        final fill = _cellColor(matrix[i][j]);
                        return Container(
                          width: celulaWidth,
                          // Padding, e nao altura fixa: a celula cresce com a fonte
                          // do usuario em vez de cortar o numero.
                          padding: const EdgeInsets.symmetric(
                            vertical: FinSpace.xs,
                          ),
                          margin: const EdgeInsets.all(1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            Fmt.ratio(matrix[i][j]),
                            // A tinta e escolhida pela luminancia do PROPRIO
                            // preenchimento: no tema claro a celula e clara e pede
                            // tinta escura. Branco fixo dava 1,94:1 ali.
                            style: tipo.numSm.copyWith(
                              color: context.fin.inkOn(fill),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
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
