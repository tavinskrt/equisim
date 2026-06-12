import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:math';
import 'package:intl/intl.dart' hide TextDirection;
import '../controllers/theme_controller.dart';
import '../utils/app_colors.dart';
import '../utils/audio_helper.dart';

/// Tela de detalhamento de um backtest salvo no histórico do usuário.
class BacktestDetailPage extends StatefulWidget {
  final Map<String, dynamic> backtestData;

  const BacktestDetailPage({super.key, required this.backtestData});

  @override
  State<BacktestDetailPage> createState() => _BacktestDetailPageState();
}

class _BacktestDetailPageState extends State<BacktestDetailPage> {
  String _activeTab = 'resumo'; // 'resumo', 'params', 'metricas'

  @override
  void initState() {
    super.initState();
    AudioHelper.playSuccessSound();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    final bt = widget.backtestData;

    // Extrai data de execução
    String formattedDate = '';
    try {
      final execDate = DateTime.parse(bt['executionDate'] as String);
      formattedDate = DateFormat('dd/MM/yyyy').format(execDate);
    } catch (e) {
      formattedDate = (bt['date'] ?? '').toString();
    }

    final String stock = bt['stockTicker'] ?? '';
    final String fii = bt['fiiTicker'] ?? '';
    final List<String> tickers = [stock, fii].where((t) => t.isNotEmpty).toList();

    final int period = (bt['periodMonths'] ?? 0) as int;
    final String methodLabel = (bt['valuationMethodLabel'] ?? '').toString();
    final String paramText = (bt['paramText'] ?? '').toString();
    final double monthlyInvestment = (bt['monthlyInvestment'] ?? 0.0) as double;
    final double totalInvested = (bt['totalInvested'] ?? 0.0) as double;

    // Métricas dos cenários
    final double retBh = (bt['totalReturnBuyHold'] ?? 0.0) as double;
    final double retVal = (bt['totalReturnValuation'] ?? 0.0) as double;

    final double valBh = (bt['finalValueBuyHold'] ?? 0.0) as double;
    final double valVal = (bt['finalValueValuation'] ?? 0.0) as double;

    final double cagrBh = (bt['cagrBuyHold'] ?? 0.0) as double;
    final double cagrVal = (bt['cagrValuation'] ?? 0.0) as double;

    // final double sharpeBh = (bt['sharpeBuyHold'] ?? 0.0) as double;
    // final double sharpeVal = (bt['sharpeValuation'] ?? 0.0) as double;

    final double ddBh = (bt['maxDrawdownBuyHold'] ?? 0.0) as double;
    final double ddVal = (bt['maxDrawdownValuation'] ?? 0.0) as double;

    // final double volBh = (bt['volatilidadeBuyHold'] ?? 0.0) as double;
    // final double volVal = (bt['volatilidadeValuation'] ?? 0.0) as double;

    // Define o vencedor
    final bool valuationWon = retVal > retBh;

    final double winnerReturn = valuationWon ? retVal : retBh;
    final double loserReturn = valuationWon ? retBh : retVal;

    final double winnerValue = valuationWon ? valVal : valBh;
    final double loserValue = valuationWon ? valBh : valVal;

    final double winnerCagr = valuationWon ? cagrVal : cagrBh;
    // final double winnerSharpe = valuationWon ? sharpeVal : sharpeBh;
    final double winnerDd = valuationWon ? ddVal : ddBh;
    // final double winnerVol = valuationWon ? volVal : volBh;

    final String loserLabel = valuationWon ? 'Buy & Hold' : 'Valuation Inteligente';

    final double capitalDifference = (winnerValue - loserValue).abs();

    // Dados das curvas
    final List<double> valuesBh = List<double>.from(bt['monthlyValuesBuyHold'] ?? []);
    final List<double> valuesVal = List<double>.from(bt['monthlyValuesValuation'] ?? []);
    final List<String> dates = List<String>.from(bt['monthlyDates'] ?? []);

    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(isLight),
        ),
        child: Stack(
          children: [
            // Efeitos decorativos de fundo
            Positioned(
              top: -100,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -80,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.05),
                ),
              ),
            ),

            Column(
              children: [
                // Header (Glassmorphism)
                ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.only(top: 52, left: 16, right: 20, bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundStart(isLight).withValues(alpha: 0.6),
                        border: Border(bottom: BorderSide(color: AppColors.surfaceBorder(isLight))),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isLight
                                        ? Colors.black.withValues(alpha: 0.05)
                                        : Colors.white.withValues(alpha: 0.06),
                                    border: Border.all(
                                      color: isLight
                                          ? Colors.black.withValues(alpha: 0.08)
                                          : Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.arrow_back_ios_new,
                                    color: isLight ? AppColors.textPrimary(true) : Colors.white60,
                                    size: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Tickers Analisados
                                    Row(
                                      children: tickers.map((t) {
                                        return Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            t,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$formattedDate · $period meses',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Botão de compartilhamento mantido
                              GestureDetector(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Compartilhamento de simulações estará disponível em breve!'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    color: isLight
                                        ? Colors.black.withValues(alpha: 0.04)
                                        : Colors.white.withValues(alpha: 0.05),
                                    border: Border.all(
                                      color: isLight
                                          ? Colors.black.withValues(alpha: 0.07)
                                          : Colors.white.withValues(alpha: 0.09),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.share_outlined,
                                    size: 14,
                                    color: AppColors.textPrimary(isLight).withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Abas de Navegação (Tabs)
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: isLight
                                  ? Colors.black.withValues(alpha: 0.04)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                _buildTabButton('resumo', 'Resumo', isLight),
                                _buildTabButton('params', 'Parâmetros', isLight),
                                _buildTabButton('metricas', 'Métricas', isLight),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Conteúdo Principal Baseado na Aba Ativa
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_activeTab == 'resumo') ...[
                          // Card de Hero de Retorno
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.surface(isLight),
                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'RETORNO TOTAL',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.textSecondary(isLight),
                                    letterSpacing: 0.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${winnerReturn >= 0 ? '+' : ''}${winnerReturn.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'vs. $loserLabel ${loserReturn >= 0 ? '+' : ''}${loserReturn.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary(isLight),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Detalhamento de patrimônio final
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isLight
                                        ? Colors.black.withValues(alpha: 0.025)
                                        : Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PATRIMÔNIO FINAL',
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: AppColors.textMuted(isLight),
                                              letterSpacing: 0.4,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            nf.format(winnerValue),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary(isLight),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${loserLabel.toUpperCase()} TERIA',
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: AppColors.textMuted(isLight),
                                              letterSpacing: 0.4,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            nf.format(loserValue),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textSecondary(isLight),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.check, color: AppColors.primary, size: 12),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${nf.format(capitalDifference)} a mais que o $loserLabel',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Evolução Patrimonial Gráfico
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface(isLight),
                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Evolução Patrimonial',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(isLight),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        _buildLegendDot('Buy & Hold', Colors.grey),
                                        const SizedBox(width: 10),
                                        _buildLegendDot('Valuation Inteligente', AppColors.primary),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Gráfico de linha interativo
                                SizedBox(
                                  height: 160,
                                  child: CustomPaint(
                                    painter: _DetailChartPainter(
                                      s1: valuesBh,
                                      s2: valuesVal,
                                      dates: dates,
                                      isLight: isLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Grid de chips informativos
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.2,
                            children: [
                              _buildInfoChip('MÉTODO', methodLabel, isLight),
                              _buildInfoChip('PARÂMETRO-CHAVE', paramText, isLight),
                              _buildInfoChip('APORTE MENSAL', nf.format(monthlyInvestment), isLight),
                              _buildInfoChip('TOTAL INVESTIDO', nf.format(totalInvested), isLight),
                            ],
                          ),
                        ] else if (_activeTab == 'params') ...[
                          // Card de Parâmetros de Valuation
                          _buildSectionContainer(
                            icon: Icons.tune,
                            title: 'MÉTODO DE VALUATION',
                            isLight: isLight,
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    methodLabel,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                 _buildParameterRow('Parâmetro principal', paramText, isLight),
                                 if (bt['valuationMethod'] == 'dcf') ...[
                                   _buildParameterRow('Taxa de Desconto (Ke)', '${bt['dcfDiscountRate'] ?? 12}%', isLight),
                                   _buildParameterRow('Crescimento (g)', '${bt['dcfGrowthRate'] ?? 8}%', isLight),
                                   _buildParameterRow('Crescimento Perpétuo (gp)', '${bt['dcfPerpetualGrowth'] ?? 4}%', isLight),
                                   _buildParameterRow('Anos Projetados', '${bt['dcfProjectionYears'] ?? 5} anos', isLight),
                                 ],
                                 _buildParameterRow('Data Inicial', DateFormat('dd/MM/yyyy').format(DateTime.parse(bt['startDate'])), isLight),
                                 _buildParameterRow('Data Final', DateFormat('dd/MM/yyyy').format(DateTime.parse(bt['endDate'])), isLight),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Card de Ativos & Aportes
                          _buildSectionContainer(
                            icon: Icons.business_center_outlined,
                            title: 'ATIVOS & APORTES',
                            isLight: isLight,
                            child: Column(
                              children: [
                                _buildParameterRow(
                                  'Ações analisadas',
                                  stock,
                                  isLight,
                                  customValueWidget: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(stock, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                  ),
                                ),
                                _buildParameterRow(
                                  'Fundos analisados',
                                  fii,
                                  isLight,
                                  customValueWidget: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(fii, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                  ),
                                ),
                                _buildParameterRow('Aporte mensal', nf.format(monthlyInvestment), isLight),
                                _buildParameterRow('Período simulado', '$period meses', isLight),
                                _buildParameterRow('Total investido', nf.format(totalInvested), isLight),
                                _buildParameterRow('Dia do Aporte', 'Todo dia ${bt['diaCompra'] ?? 1}', isLight),
                                _buildParameterRow('Reinvestir Dividendos', (bt['considerarReinvestimento'] ?? false) ? 'Sim' : 'Não', isLight),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Métricas Avançadas
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.5,
                            children: [
                              _buildMetricTile('Retorno Total', '${winnerReturn >= 0 ? '+' : ''}${winnerReturn.toStringAsFixed(1)}%', AppColors.primary, '↑', '$period meses', isLight),
                              _buildMetricTile('CAGR Anualizado', '${winnerCagr >= 0 ? '+' : ''}${winnerCagr.toStringAsFixed(1)}%', AppColors.primary, 'α', 'Retorno anual composto', isLight),
                              // _buildMetricTile('Índice Sharpe', winnerSharpe.toStringAsFixed(2), Colors.blue, 'S', 'Relação Retorno/Risco', isLight),
                              _buildMetricTile('Max. Drawdown', '${winnerDd.toStringAsFixed(1)}%', AppColors.danger, '↓', 'Pior queda histórica', isLight),
                              // _buildMetricTile('Volatilidade', '${winnerVol.toStringAsFixed(1)}%', Colors.orange, 'σ', 'Volatilidade anual', isLight),
                              _buildMetricTile('Rentabilidade Mínima', '${loserReturn >= 0 ? '+' : ''}${loserReturn.toStringAsFixed(1)}%', Colors.grey, 'B', 'Cenário perdedor', isLight),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Barra comparativa de capital final
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface(isLight),
                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Comparativo de capital final',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary(isLight),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                _buildCapitalBar('Valuation Inteligente', valVal, valVal, AppColors.primary, nf, isLight),
                                const SizedBox(height: 10),
                                _buildCapitalBar('Buy & Hold', valBh, valVal, Colors.blue, nf, isLight),
                                const SizedBox(height: 10),
                                _buildCapitalBar('Total investido', totalInvested, valVal, Colors.grey, nf, isLight),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Caixa de Feedback de Risco/Retorno
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: valuationWon
                                  ? AppColors.primary.withValues(alpha: 0.05)
                                  : Colors.blue.withValues(alpha: 0.05),
                              border: Border.all(
                                color: valuationWon
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : Colors.blue.withValues(alpha: 0.15),
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: valuationWon ? const Color(0xFF00CC8F) : Colors.blue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        valuationWon ? 'Desempenho Superior' : 'Buy & Hold Venceu',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: valuationWon
                                              ? const Color(0xFF00CC8F)
                                              : Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        valuationWon
                                            ? 'Neste backtest, a alocação tática baseada em valuation gerou um ganho excedente significativo de ${nf.format(capitalDifference)} sobre a estratégia passiva.'
                                            : 'Neste backtest, a estratégia Buy & Hold passiva superou a alocação tática de valuation por uma diferença de ${nf.format(capitalDifference)}.',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary(isLight),
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói botões de pílulas para as abas da tela de detalhes
  Widget _buildTabButton(String tabId, String label, bool isLight) {
    final bool isActive = _activeTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = tabId;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isActive ? const Color(0xFF00CC8F) : AppColors.textSecondary(isLight),
            ),
          ),
        ),
      ),
    );
  }

  /// Constrói um indicador de legenda de gráfico
  Widget _buildLegendDot(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Bloco de informações gerais
  Widget _buildInfoChip(String label, String value, bool isLight) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface(isLight),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: AppColors.textMuted(isLight),
              letterSpacing: 0.4,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(isLight),
            ),
          ),
        ],
      ),
    );
  }

  /// Card agrupador para abas secundárias
  Widget _buildSectionContainer({
    required IconData icon,
    required String title,
    required bool isLight,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(isLight),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary(isLight),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildParameterRow(String label, String value, bool isLight, {Widget? customValueWidget}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(isLight))),
          customValueWidget ??
              Text(
                value,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
              ),
        ],
      ),
    );
  }

  /// Card individual para a aba de métricas avançadas
  Widget _buildMetricTile(
    String label,
    String value,
    Color color,
    String icon,
    String desc,
    bool isLight,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface(isLight),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  icon,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
          ),
          Text(
            desc,
            style: TextStyle(fontSize: 8, color: AppColors.textMuted(isLight)),
          ),
        ],
      ),
    );
  }

  /// Barra horizontal proporcional para comparação visual de capital final
  Widget _buildCapitalBar(
    String label,
    double value,
    double maxValue,
    Color color,
    NumberFormat nf,
    bool isLight,
  ) {
    final double pct = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(isLight))),
            Text(
              nf.format(value),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: pct,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// CustomPainter para traçar as duas curvas patrimoniais de evolução (Buy & Hold vs Valuation Inteligente)
class _DetailChartPainter extends CustomPainter {
  final List<double> s1; // Buy & Hold
  final List<double> s2; // Valuation Inteligente
  final List<String> dates;
  final bool isLight;

  _DetailChartPainter({
    required this.s1,
    required this.s2,
    required this.dates,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (s1.isEmpty || s2.isEmpty) return;

    double maxVal = s1.reduce(max);
    maxVal = max(maxVal, s2.reduce(max));
    double minVal = s1.reduce(min);
    minVal = min(minVal, s2.reduce(min));

    const double paddingLeft = 46.0;
    const double paddingRight = 10.0;
    const double paddingTop = 10.0;
    const double paddingBottom = 22.0;

    final double width = size.width - paddingLeft - paddingRight;
    final double height = size.height - paddingTop - paddingBottom;

    final double valRange = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;
    final double yScaler = height / (valRange * 1.08);

    final Paint gridPaint = Paint()
      ..color = isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 1. Desenha as linhas horizontais do grid e labels de Y
    const int gridRows = 3;
    for (int i = 0; i <= gridRows; i++) {
      final double y = paddingTop + height - (i * (height / gridRows));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      final double val = minVal + (i * (valRange * 1.08 / gridRows));
      String label = '';
      if (val >= 1000) {
        label = '${(val / 1000).toStringAsFixed(0)}k';
      } else {
        label = val.toStringAsFixed(0);
      }

      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 8.5,
          color: isLight ? Colors.black45 : Colors.white38,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2));
    }

    // 2. Mapeia pontos das curvas
    final List<Offset> s1Points = [];
    final List<Offset> s2Points = [];

    for (int i = 0; i < s1.length; i++) {
      final double x = paddingLeft + (i * (width / (s1.length - 1)));
      final double y1 = paddingTop + height - ((s1[i] - minVal) * yScaler);
      final double y2 = paddingTop + height - ((s2[i] - minVal) * yScaler);

      s1Points.add(Offset(x, y1));
      s2Points.add(Offset(x, y2));
    }

    // 3. Desenha a área sombreada do Valuation Inteligente
    final Path fillPath = Path();
    fillPath.moveTo(s2Points.first.dx, size.height - paddingBottom);
    for (var pt in s2Points) {
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(s2Points.last.dx, size.height - paddingBottom);
    fillPath.close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary.withValues(alpha: 0.16),
          AppColors.primary.withValues(alpha: 0.00),
        ],
      ).createShader(Rect.fromLTWH(paddingLeft, paddingTop, width, height));
    canvas.drawPath(fillPath, fillPaint);

    // 4. Desenha a curva de Buy & Hold (Cinza tracejada)
    final Paint linePaint1 = Paint()
      ..color = isLight ? Colors.black38 : Colors.white30
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final Path path1 = Path();
    path1.moveTo(s1Points.first.dx, s1Points.first.dy);
    for (int i = 1; i < s1Points.length; i++) {
      path1.lineTo(s1Points[i].dx, s1Points[i].dy);
    }
    
    // Desenha tracejado para Buy & Hold
    _drawDashedPath(canvas, path1, linePaint1, 4.0, 3.0);

    // 5. Desenha a curva do Valuation Inteligente (Verde contínua e grossa)
    final Paint linePaint2 = Paint()
      ..color = const Color(0xFF00B37E)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path2 = Path();
    path2.moveTo(s2Points.first.dx, s2Points.first.dy);
    for (int i = 1; i < s2Points.length; i++) {
      path2.lineTo(s2Points[i].dx, s2Points[i].dy);
    }
    canvas.drawPath(path2, linePaint2);

    // 6. Marcadores finais das curvas
    final Paint circleBorder = Paint()
      ..color = isLight ? Colors.white : const Color(0xFF0B1E4B)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final Paint marker1 = Paint()
      ..color = isLight ? Colors.grey : Colors.grey.shade400
      ..style = PaintingStyle.fill;
    final Paint marker2 = Paint()
      ..color = const Color(0xFF00B37E)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(s1Points.last, 3.5, marker1);
    canvas.drawCircle(s1Points.last, 3.5, circleBorder);

    canvas.drawCircle(s2Points.last, 4.5, marker2);
    canvas.drawCircle(s2Points.last, 4.5, circleBorder);

    // 7. Legendas no eixo X
    final int xTicks = min(4, dates.length);
    if (xTicks > 1) {
      for (int i = 0; i < xTicks; i++) {
        final int index = ((dates.length - 1) * (i / (xTicks - 1))).round();
        final double x = paddingLeft + (index * (width / (dates.length - 1)));

        // Formata data abreviada para o gráfico (ex: dd/mm/yyyy para mm/yy)
        String xLabel = dates[index];
        try {
          final parts = dates[index].split('/');
          if (parts.length == 3) {
            final monthStr = _getMonthAbbr(int.parse(parts[1]));
            xLabel = '$monthStr/${parts[2].substring(2)}';
          }
        } catch (_) {}

        textPainter.text = TextSpan(
          text: xLabel,
          style: TextStyle(
            fontSize: 8,
            color: isLight ? Colors.black45 : Colors.white38,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - paddingBottom + 6));
      }
    }
  }

  /// Método utilitário para desenhar caminhos tracejados
  void _drawDashedPath(Canvas canvas, Path path, Paint paint, double dashLength, double spaceLength) {
    final PathMetrics pathMetrics = path.computeMetrics();
    for (final PathMetric pathMetric in pathMetrics) {
      double distance = 0.0;
      bool draw = true;
      while (distance < pathMetric.length) {
        final double length = draw ? dashLength : spaceLength;
        final Path extract = pathMetric.extractPath(distance, distance + length);
        if (draw) {
          canvas.drawPath(extract, paint);
        }
        distance += length;
        draw = !draw;
      }
    }
  }

  String _getMonthAbbr(int month) {
    const list = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    if (month >= 1 && month <= 12) return list[month - 1];
    return '';
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
