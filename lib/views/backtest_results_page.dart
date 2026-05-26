import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:math';
import 'package:intl/intl.dart' hide TextDirection;
import '../controllers/backtest_controller.dart';
import '../controllers/theme_controller.dart';
import '../models/backtest.dart';
import '../utils/app_colors.dart';

class BacktestResultsPage extends StatefulWidget {
  const BacktestResultsPage({super.key});

  @override
  State<BacktestResultsPage> createState() => _BacktestResultsPageState();
}

class _BacktestResultsPageState extends State<BacktestResultsPage> {
  int? _selectedIndex;
  int? _lockedIndex; // Locked selection index from clicking/tapping

  @override
  Widget build(BuildContext context) {
    final backtestController = Provider.of<BacktestController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    final result = backtestController.lastResult;

    if (result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sem Resultados')),
        body: const Center(child: Text('Nenhuma simulação executada.')),
      );
    }

    final s1 = result.scenario1;
    final s2 = result.scenario2;
    final config = result.config;

    final numberFormat = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    // Preparar dados do gráfico
    final List<double> s1Values = s1.monthlyPositions.map((p) => p.getAssetValue()).toList();
    final List<double> s2Values = s2.monthlyPositions.map((p) => p.getAssetValue()).toList();
    final List<String> dates = s1.monthlyPositions.map((p) => DateFormat('dd/MM/yy').format(p.date)).toList();

    final int activeIdx = _selectedIndex ?? _lockedIndex ?? (dates.length - 1);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(isLight),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios, color: AppColors.textPrimary(isLight), size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resultado da Simulação',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(isLight),
                          ),
                        ),
                        Text(
                          '${config.stockTicker} + ${config.fiiTicker} · ${DateFormat('dd/MM/yyyy').format(config.startDate)} a ${DateFormat('dd/MM/yyyy').format(config.endDate)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(isLight),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Corpo Principal Responsivo
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;

                    final List<Widget> content = [
                      // Esquerda: Gráfico
                      Expanded(
                        flex: isWide ? 3 : 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              child: _buildWinnerCard(result, isLight),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: _buildGlassChartContainer(
                                  s1,
                                  s2,
                                  s1Values,
                                  s2Values,
                                  dates,
                                  isLight,
                                  config,
                                  selectedIndex: _selectedIndex,
                                  lockedIndex: _lockedIndex,
                                  onIndexChanged: (idx) {
                                    setState(() {
                                      _selectedIndex = idx;
                                    });
                                  },
                                  onLockedIndexChanged: (idx) {
                                    setState(() {
                                      if (_lockedIndex == idx) {
                                        _lockedIndex = null;
                                      } else {
                                        _lockedIndex = idx;
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Direita: Painel Numérico
                      Expanded(
                        flex: isWide ? 2 : 0,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildComparisonTable(s1, s2, activeIdx, config, numberFormat, isLight),
                              const SizedBox(height: 16),
                              _buildOperationsSummary(s1, s2, activeIdx, isLight),
                              const SizedBox(height: 16),
                              _buildDetailsCard(config, isLight),
                            ],
                          ),
                        ),
                      ),
                    ];

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: content,
                      );
                    } else {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(
                              height: 380,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: _buildWinnerCard(result, isLight),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: _buildGlassChartContainer(
                                        s1,
                                        s2,
                                        s1Values,
                                        s2Values,
                                        dates,
                                        isLight,
                                        config,
                                        selectedIndex: _selectedIndex,
                                        lockedIndex: _lockedIndex,
                                        onIndexChanged: (idx) {
                                          setState(() {
                                            _selectedIndex = idx;
                                          });
                                        },
                                        onLockedIndexChanged: (idx) {
                                          setState(() {
                                            if (_lockedIndex == idx) {
                                              _lockedIndex = null;
                                            } else {
                                              _lockedIndex = idx;
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...content.sublist(1).map((w) => w is Expanded ? w.child : w),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWinnerCard(BacktestResult result, bool isLight) {
    final w = result.getWinner();
    final diff = result.getAbsoluteDifference();
    final diffPct = result.getPercentageDifference();
    
    // Identificar equivalência/empate se a diferença patrimonial for menor que R$ 5,00
    final bool isTie = diff < 5.0;

    if (isTie) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isLight ? Colors.grey.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isLight ? Colors.black12 : Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isLight ? Colors.grey.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.balance,
                color: isLight ? Colors.black54 : Colors.white70,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resultado Equivalente',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary(isLight),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Ambos os Cenários Empatados',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'R\$ ${diff.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                ),
                Text(
                  'Diferença irrelevante',
                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary(isLight)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final isValuationWinner = w.scenarioName.contains('Valuation');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isValuationWinner 
                  ? const Color(0xFF00B37E).withValues(alpha: 0.12) 
                  : AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isValuationWinner ? Icons.verified : Icons.trending_up,
              color: isValuationWinner ? const Color(0xFF00B37E) : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cenário Vencedor',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(isLight),
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  w.scenarioName,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+ ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(diff)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00B37E)),
              ),
              Text(
                '${diffPct.toStringAsFixed(4)}% a mais',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary(isLight)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassChartContainer(
    BacktestScenarioResult s1Result,
    BacktestScenarioResult s2Result,
    List<double> s1,
    List<double> s2,
    List<String> dates,
    bool isLight,
    BacktestConfig config, {
    required int? selectedIndex,
    required int? lockedIndex,
    required ValueChanged<int?> onIndexChanged,
    required ValueChanged<int?> onLockedIndexChanged,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface(isLight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceBorder(isLight)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Legenda do gráfico
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem('Apenas Ações', const Color(0xFF94A3B8), false),
                  const SizedBox(width: 20),
                  _buildLegendItem('Ações + FIIs (Valuation)', AppColors.primary, true),
                ],
              ),
              const SizedBox(height: 14),
              
              // Canvas do gráfico Interativo com Hover e Toque
              Expanded(
                child: _GlassChartWithTooltip(
                  s1Result: s1Result,
                  s2Result: s2Result,
                  config: config,
                  s1: s1,
                  s2: s2,
                  dates: dates,
                  isLight: isLight,
                  selectedIndex: selectedIndex,
                  lockedIndex: lockedIndex,
                  onIndexChanged: onIndexChanged,
                  onLockedIndexChanged: onLockedIndexChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, bool isGradient) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isGradient ? AppColors.brandGradient : null,
            color: !isGradient ? color : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildComparisonTable(
    BacktestScenarioResult s1,
    BacktestScenarioResult s2,
    int activeIdx,
    BacktestConfig config,
    NumberFormat nf,
    bool isLight,
  ) {
    // Current positions at activeIdx
    final pos1 = s1.monthlyPositions[activeIdx];
    final pos2 = s2.monthlyPositions[activeIdx];
    final DateTime currentDate = pos1.date;

    // Current portfolio values
    final double val1 = pos1.getTotalValue();
    final double val2 = pos2.getTotalValue();

    // Total invested up to activeIdx (filtered by operationDate)
    final double totalInvested1 = s1.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.monthlyInvestment);
    final double totalInvested2 = s2.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.monthlyInvestment);

    // Total actually spent on purchasing shares up to activeIdx (filtered by operationDate)
    final double totalAllocated1 = s1.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + (op.quantityBought * op.priceBought));
    final double totalAllocated2 = s2.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + (op.quantityBought * op.priceBought));

    // Total dividends received up to activeIdx (filtered by operationDate)
    final double totalDividends1 = s1.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.stockDividends + op.fiiDividends);
    final double totalDividends2 = s2.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.stockDividends + op.fiiDividends);

    // Break down dividends by ticker (filtered by operationDate)
    final double stockDividends1 = s1.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.stockDividends);
    final double fiiDividends1 = s1.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.fiiDividends);

    final double stockDividends2 = s2.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.stockDividends);
    final double fiiDividends2 = s2.operations.where((op) => !op.operationDate.isAfter(currentDate)).fold(0.0, (sum, op) => sum + op.fiiDividends);

    // Returns
    final double return1 = totalInvested1 > 0 ? ((val1 - totalInvested1) / totalInvested1) * 100.0 : 0.0;
    final double return2 = totalInvested2 > 0 ? ((val2 - totalInvested2) / totalInvested2) * 100.0 : 0.0;

    // CAGR
    final double yearsDiff = max(0.1, (currentDate.difference(config.startDate).inDays) / 365.25);
    final double cagr1 = totalInvested1 > 0 && val1 > 0 ? (pow(val1 / totalInvested1, 1 / yearsDiff) - 1) * 100.0 : 0.0;
    final double cagr2 = totalInvested2 > 0 && val2 > 0 ? (pow(val2 / totalInvested2, 1 / yearsDiff) - 1) * 100.0 : 0.0;

    final isFinal = activeIdx == s1.monthlyPositions.length - 1;
    final labelPatrimonio = isFinal ? 'Patrimônio Final' : 'Patrimônio na Data';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(isLight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DESEMPENHO DO PORTFÓLIO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary(isLight),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          
          _buildTableItem(labelPatrimonio, nf.format(val1), nf.format(val2), isLight, highlightRight: val2 > val1),
          _buildTableItem('Saldo em Caixa', nf.format(pos1.cash), nf.format(pos2.cash), isLight, isNeutral: true),
          _buildTableItem('Dinheiro Separado para Aporte', nf.format(totalInvested1), nf.format(totalInvested2), isLight, isNeutral: true),
          
          _buildTableItem('Dividendos Recebidos', nf.format(totalDividends1), nf.format(totalDividends2), isLight, highlightRight: totalDividends2 > totalDividends1, showDivider: false),
          _buildSubTableItem('↳ Dividendos de ${config.stockTicker}', nf.format(stockDividends1), nf.format(stockDividends2), isLight, highlightRight: stockDividends2 > stockDividends1),
          _buildSubTableItem('↳ Dividendos de ${config.fiiTicker}', nf.format(fiiDividends1), nf.format(fiiDividends2), isLight, highlightRight: fiiDividends2 > fiiDividends1),
          const Divider(height: 12),

          _buildTableItem('Dividendos Reinvestidos', nf.format(config.considerarReinvestimento ? totalDividends1 : 0.0), nf.format(config.considerarReinvestimento ? totalDividends2 : 0.0), isLight, highlightRight: totalDividends2 > totalDividends1 && config.considerarReinvestimento),
          _buildTableItem('Total Alocado em Ativos', nf.format(totalAllocated1), nf.format(totalAllocated2), isLight, highlightRight: totalAllocated2 > totalAllocated1),
          
          _buildTableItem('Retorno Total', '${return1.toStringAsFixed(4)}%', '${return2.toStringAsFixed(4)}%', isLight, highlightRight: return2 > return1),
          _buildTableItem('CAGR (Rentabilidade a.a.)', '${cagr1.toStringAsFixed(4)}%', '${cagr2.toStringAsFixed(4)}%', isLight, highlightRight: cagr2 > cagr1),
        ],
      ),
    );
  }

  Widget _buildTableItem(String label, String v1, String v2, bool isLight, {bool highlightRight = false, bool isNeutral = false, bool showDivider = true}) {
    final rightColor = isNeutral 
        ? AppColors.textPrimary(isLight)
        : (highlightRight ? const Color(0xFF00B37E) : const Color(0xFFEF4444));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(isLight))),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(v1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight))),
              const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
              Text(v2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: rightColor)),
            ],
          ),
          if (showDivider) const Divider(height: 12),
        ],
      ),
    );
  }

  Widget _buildSubTableItem(String label, String v1, String v2, bool isLight, {bool highlightRight = false, bool isNeutral = false}) {
    final rightColor = isNeutral 
        ? AppColors.textSecondary(isLight)
        : (highlightRight ? const Color(0xFF00B37E) : const Color(0xFFEF4444));

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 4.0, bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary(isLight),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                v1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary(isLight),
                ),
              ),
              const Icon(Icons.arrow_right, size: 12, color: Colors.grey),
              Text(
                v2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: rightColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsSummary(
    BacktestScenarioResult s1,
    BacktestScenarioResult s2,
    int activeIdx,
    bool isLight,
  ) {
    // Current positions at activeIdx
    final pos1 = s1.monthlyPositions[activeIdx];
    final pos2 = s2.monthlyPositions[activeIdx];

    final isFinal = activeIdx == s1.monthlyPositions.length - 1;
    final labelSuffix = isFinal ? 'no encerramento da simulação.' : 'no ponto selecionado.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cenário 1
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface(isLight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceBorder(isLight)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'COMPOSIÇÃO DE ATIVOS (CENÁRIO 1 - APENAS AÇÕES)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary(isLight),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '*Saldo de cotas da Carteira de Ações $labelSuffix',
                style: TextStyle(fontSize: 9, color: AppColors.textMuted(isLight)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCompositionTile(
                      icon: Icons.ssid_chart,
                      label: 'Ações Acumuladas',
                      shares: '${_formatShares(pos1.stockShares)} cotas',
                      sub: 'Buy & Hold regular',
                      isLight: isLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCompositionTile(
                      icon: Icons.business,
                      label: 'FIIs Acumulados',
                      shares: '${_formatShares(pos1.fiiShares)} cotas',
                      sub: 'Não comprado no Cenário 1',
                      isLight: isLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Cenário 2
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface(isLight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceBorder(isLight)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'COMPOSIÇÃO DE ATIVOS (CENÁRIO 2 - DIVERSIFICADO)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary(isLight),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '*Saldo de cotas da Carteira Diversificada $labelSuffix',
                style: TextStyle(fontSize: 9, color: AppColors.textMuted(isLight)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCompositionTile(
                      icon: Icons.ssid_chart,
                      label: 'Ações Acumuladas',
                      shares: '${_formatShares(pos2.stockShares)} cotas',
                      sub: 'Compradas via critério',
                      isLight: isLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCompositionTile(
                      icon: Icons.business,
                      label: 'FIIs Acumulados',
                      shares: '${_formatShares(pos2.fiiShares)} cotas',
                      sub: 'Comprados em momentos caros',
                      isLight: isLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompositionTile({
    required IconData icon,
    required String label,
    required String shares,
    required String sub,
    required bool isLight,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBackground(isLight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(isLight))),
          const SizedBox(height: 2),
          Text(shares, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight))),
          const SizedBox(height: 1),
          Text(sub, style: TextStyle(fontSize: 9, color: AppColors.textMuted(isLight))),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(BacktestConfig config, bool isLight) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(isLight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CONFIGURAÇÃO DA SIMULAÇÃO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary(isLight),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('Ação Selecionada', config.stockTicker, isLight),
          _buildDetailRow('FII Selecionado', config.fiiTicker, isLight),
          _buildDetailRow('Valuation de Escolha', config.valuationMethod.label, isLight),
          if (config.valuationMethod == ValuationMethod.graham)
            _buildDetailRow('Margem de Segurança', '${config.safetyMargin}%', isLight),
          _buildDetailRow('Reinvestimento de Dividendos', config.considerarReinvestimento ? 'Ativo' : 'Inativo', isLight),
          _buildDetailRow('Dia do Aporte Mensal', 'Todo dia ${config.diaCompra}', isLight),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isLight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(isLight))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight))),
        ],
      ),
    );
  }

  String _formatShares(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    // Remove trailing zeros after decimal point, keeping up to 4 decimal places
    String formatted = value.toStringAsFixed(4);
    while (formatted.endsWith('0')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    if (formatted.endsWith('.')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }
}

/// Widget Interativo que envolve o Gráfico com Suporte a Hover e Gestos (Toques)
class _GlassChartWithTooltip extends StatelessWidget {
  final BacktestScenarioResult s1Result;
  final BacktestScenarioResult s2Result;
  final BacktestConfig config;
  final List<double> s1;
  final List<double> s2;
  final List<String> dates;
  final bool isLight;
  final int? selectedIndex;
  final int? lockedIndex;
  final ValueChanged<int?> onIndexChanged;
  final ValueChanged<int?> onLockedIndexChanged;

  const _GlassChartWithTooltip({
    required this.s1Result,
    required this.s2Result,
    required this.config,
    required this.s1,
    required this.s2,
    required this.dates,
    required this.isLight,
    required this.selectedIndex,
    required this.lockedIndex,
    required this.onIndexChanged,
    required this.onLockedIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final isLight = this.isLight;

    // Precalculate purchase indices for Scenario 1 and 2
    final List<int> s1PurchaseIndices = [];
    for (int i = 0; i < s1Result.operations.length; i++) {
      final op = s1Result.operations[i];
      if (op.quantityBought > 0 && op.assetBought != null) {
        for (int j = 0; j < s1Result.monthlyPositions.length; j++) {
          final pos = s1Result.monthlyPositions[j];
          if (pos.date.year == op.operationDate.year &&
              pos.date.month == op.operationDate.month &&
              pos.date.day == op.operationDate.day) {
            s1PurchaseIndices.add(j);
            break;
          }
        }
      }
    }

    final List<int> s2StockPurchaseIndices = [];
    final List<int> s2FiiPurchaseIndices = [];
    for (int i = 0; i < s2Result.operations.length; i++) {
      final op = s2Result.operations[i];
      if (op.quantityBought > 0 && op.assetBought != null) {
        for (int j = 0; j < s2Result.monthlyPositions.length; j++) {
          final pos = s2Result.monthlyPositions[j];
          if (pos.date.year == op.operationDate.year &&
              pos.date.month == op.operationDate.month &&
              pos.date.day == op.operationDate.day) {
            if (op.assetBought == 'STOCK') {
              s2StockPurchaseIndices.add(j);
            } else if (op.assetBought == 'FII') {
              s2FiiPurchaseIndices.add(j);
            }
            break;
          }
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double paddingLeft = 60.0;
        const double paddingRight = 10.0;
        const double paddingTop = 10.0;
        const double paddingBottom = 30.0;

        final double width = constraints.maxWidth - paddingLeft - paddingRight;
        final double height = constraints.maxHeight - paddingTop - paddingBottom;

        final double maxVal = s1.isEmpty ? 0 : s1.reduce(max);
        final double minVal = s1.isEmpty ? 0 : s1.reduce(min);
        final double globalMax = s2.isEmpty ? maxVal : max(maxVal, s2.reduce(max));
        final double globalMin = s2.isEmpty ? minVal : min(minVal, s2.reduce(min));

        final double valRange = (globalMax - globalMin) > 0 ? (globalMax - globalMin) : 1.0;
        final double yScaler = height / (valRange * 1.1);

        // Helper to find nearest purchase dot if click or hover is close to it
        int? findNearestPurchaseIndex(Offset localPosition, double width) {
          const double maxDistance = 25.0; // snapping radius in pixels
          int? bestIndex;
          double bestDistance = double.infinity;

          // Helper to check Scenario 1 purchase dots
          for (final idx in s1PurchaseIndices) {
            if (idx >= s1.length) continue;
            final double x = paddingLeft + (idx * (width / (dates.length - 1)));
            final double y = paddingTop + height - ((s1[idx] - globalMin) * yScaler);
            final double dist = (localPosition - Offset(x, y)).distance;
            if (dist < maxDistance && dist < bestDistance) {
              bestDistance = dist;
              bestIndex = idx;
            }
          }

          // Helper to check Scenario 2 stock purchase dots
          for (final idx in s2StockPurchaseIndices) {
            if (idx >= s2.length) continue;
            final double x = paddingLeft + (idx * (width / (dates.length - 1)));
            final double y = paddingTop + height - ((s2[idx] - globalMin) * yScaler);
            final double dist = (localPosition - Offset(x, y)).distance;
            if (dist < maxDistance && dist < bestDistance) {
              bestDistance = dist;
              bestIndex = idx;
            }
          }

          // Helper to check Scenario 2 fii purchase dots
          for (final idx in s2FiiPurchaseIndices) {
            if (idx >= s2.length) continue;
            final double x = paddingLeft + (idx * (width / (dates.length - 1)));
            final double y = paddingTop + height - ((s2[idx] - globalMin) * yScaler);
            final double dist = (localPosition - Offset(x, y)).distance;
            if (dist < maxDistance && dist < bestDistance) {
              bestDistance = dist;
              bestIndex = idx;
            }
          }

          return bestIndex;
        }

        void updateHoverSelection(Offset localPosition) {
          if (width <= 0 || dates.isEmpty) return;
          final int? purchaseIdx = findNearestPurchaseIndex(localPosition, width);
          int idx;
          if (purchaseIdx != null) {
            idx = purchaseIdx;
          } else {
            final double pct = (localPosition.dx - paddingLeft) / width;
            idx = (pct * (dates.length - 1)).round().clamp(0, dates.length - 1);
          }
          if (selectedIndex != idx) {
            onIndexChanged(idx);
          }
        }

        void handleTap(Offset localPosition) {
          if (width <= 0 || dates.isEmpty) return;
          final int? purchaseIdx = findNearestPurchaseIndex(localPosition, width);
          int idx;
          if (purchaseIdx != null) {
            idx = purchaseIdx;
          } else {
            final double pct = (localPosition.dx - paddingLeft) / width;
            idx = (pct * (dates.length - 1)).round().clamp(0, dates.length - 1);
          }
          onLockedIndexChanged(idx);
        }

        final int? displayIndex = selectedIndex ?? lockedIndex;

        return Stack(
          children: [
            MouseRegion(
              onHover: (event) => updateHoverSelection(event.localPosition),
              onExit: (_) {
                onIndexChanged(null);
              },
              child: GestureDetector(
                onTapDown: (details) => handleTap(details.localPosition),
                onPanUpdate: (details) => updateHoverSelection(details.localPosition),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _PortfolioChartPainter(
                    s1: s1,
                    s2: s2,
                    dates: dates,
                    isLight: isLight,
                    selectedIndex: selectedIndex,
                    lockedIndex: lockedIndex,
                    s1PurchaseIndices: s1PurchaseIndices,
                    s2StockPurchaseIndices: s2StockPurchaseIndices,
                    s2FiiPurchaseIndices: s2FiiPurchaseIndices,
                  ),
                ),
              ),
            ),

            // Tooltip Flutuante Inteligente (Lado Alternado baseada no cursor)
            if (displayIndex != null && displayIndex < s1Result.monthlyPositions.length) ...[
              Builder(
                builder: (context) {
                  final idx = displayIndex;
                  final pos1 = s1Result.monthlyPositions[idx];
                  final pos2 = s2Result.monthlyPositions[idx];
                  final date = dates[idx];

                  // Localizar se houve compra neste dia no Cenário 2 (Valuation)
                  final currentDate = pos2.date;
                  MonthlyOperation? op;
                  for (final o in s2Result.operations) {
                    if (o.operationDate.year == currentDate.year &&
                        o.operationDate.month == currentDate.month &&
                        o.operationDate.day == currentDate.day) {
                      op = o;
                      break;
                    }
                  }

                  // Verifica em qual metade do gráfico o cursor está para posicionar o card do lado oposto
                  final bool isOnRightHalf = idx >= dates.length / 2;

                  return Positioned(
                    top: 10,
                    left: isOnRightHalf ? 10 : null,
                    right: !isOnRightHalf ? 10 : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          width: op != null ? 240 : 175,
                          decoration: BoxDecoration(
                            color: isLight 
                                ? Colors.white.withValues(alpha: 0.9) 
                                : const Color(0xEC1A2744),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 16,
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Data: $date',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary(isLight),
                                    ),
                                  ),
                                  if (lockedIndex == idx)
                                    Icon(
                                      Icons.lock,
                                      size: 10,
                                      color: AppColors.primary,
                                    ),
                                ],
                              ),
                              const Divider(height: 10),
                              
                              _buildTooltipRow('Apenas Ações:', nf.format(pos1.getAssetValue()), isLight, color: isLight ? Colors.black54 : Colors.white70),
                              _buildTooltipRow('Ações+FIIs:', nf.format(pos2.getAssetValue()), isLight, color: AppColors.primaryLight, isBold: true),
                              
                              const Divider(height: 10),
                              
                              _buildTooltipRow('Preço Ação:', nf.format(pos1.stockPrice), isLight, fontSize: 9, color: Colors.grey),
                              _buildTooltipRow('Preço FII:', nf.format(pos1.fiiPrice), isLight, fontSize: 9, color: Colors.grey),

                              if (op != null) ...[
                                const Divider(height: 10),
                                Text(
                                  'COMPRA REALIZADA:',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _buildTooltipRow(
                                  'Ativo comprado:',
                                  op.assetBought != null 
                                      ? '${op.assetBought == "STOCK" ? config.stockTicker : config.fiiTicker} (${op.quantityBought.toInt()} cotas)'
                                      : 'Nenhum (Saldo Insuficiente)',
                                  isLight,
                                  fontSize: 9.5,
                                  color: op.assetBought == 'STOCK' ? const Color(0xFF00B37E) : const Color(0xFFF59E0B),
                                  isBold: true,
                                ),
                                if (op.valuationFormulaValue != null && op.valuationFormulaValue! > 0)
                                  _buildTooltipRow(
                                    config.valuationMethod == ValuationMethod.peterLynch
                                        ? 'Ind. Peter Lynch:'
                                        : 'Preço Justo:',
                                    config.valuationMethod == ValuationMethod.peterLynch
                                        ? op.valuationFormulaValue!.toStringAsFixed(2)
                                        : nf.format(op.valuationFormulaValue!),
                                    isLight,
                                    fontSize: 9.5,
                                    color: AppColors.primaryLight,
                                  ),
                                const SizedBox(height: 6),
                                Text(
                                  op.purchaseReason ?? '',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    color: isLight ? Colors.black87 : Colors.white70,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTooltipRow(
    String label,
    String value,
    bool isLight, {
    double fontSize = 9.5,
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: fontSize, color: AppColors.textSecondary(isLight))),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppColors.textPrimary(isLight),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter de Gráfico com Suporte a Desenho de Indicadores de Seleção/Hover
class _PortfolioChartPainter extends CustomPainter {
  final List<double> s1;
  final List<double> s2;
  final List<String> dates;
  final bool isLight;
  final int? selectedIndex;
  final int? lockedIndex;
  final List<int> s1PurchaseIndices;
  final List<int> s2StockPurchaseIndices;
  final List<int> s2FiiPurchaseIndices;

  _PortfolioChartPainter({
    required this.s1,
    required this.s2,
    required this.dates,
    required this.isLight,
    this.selectedIndex,
    this.lockedIndex,
    required this.s1PurchaseIndices,
    required this.s2StockPurchaseIndices,
    required this.s2FiiPurchaseIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (s1.isEmpty || s2.isEmpty) return;

    // Achar máximos e mínimos globais para escala
    double maxVal = s1.reduce(max);
    maxVal = max(maxVal, s2.reduce(max));
    double minVal = s1.reduce(min);
    minVal = min(minVal, s2.reduce(min));

    // Margens e área útil
    const double paddingLeft = 60.0;
    const double paddingRight = 10.0;
    const double paddingTop = 10.0;
    const double paddingBottom = 30.0;

    final double width = size.width - paddingLeft - paddingRight;
    final double height = size.height - paddingTop - paddingBottom;

    final double valRange = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;
    final double yScaler = height / (valRange * 1.1); // 10% folga no topo

    // Desenhar Grid e Eixo Y
    final Paint gridPaint = Paint()
      ..color = isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);

    const int gridRows = 4;
    for (int i = 0; i <= gridRows; i++) {
      final double y = paddingTop + height - (i * (height / gridRows));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      // Label do Eixo Y
      final double val = minVal + (i * (valRange * 1.1 / gridRows));
      textPainter.text = TextSpan(
        text: _formatCompactCurrency(val),
        style: TextStyle(
          fontSize: 9,
          color: isLight ? Colors.black54 : Colors.white54,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2));
    }

    // Desenhar Eixo X (Datas)
    final int xTicks = min(5, dates.length);
    if (xTicks > 1) {
      for (int i = 0; i < xTicks; i++) {
        final int index = ((dates.length - 1) * (i / (xTicks - 1))).round();
        final double x = paddingLeft + (index * (width / (dates.length - 1)));

        textPainter.text = TextSpan(
          text: dates[index],
          style: TextStyle(
            fontSize: 9,
            color: isLight ? Colors.black54 : Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - paddingBottom + 8));
      }
    }

    // Gerar pontos das duas curvas
    final List<Offset> s1Points = [];
    final List<Offset> s2Points = [];

    for (int i = 0; i < s1.length; i++) {
      final double x = paddingLeft + (i * (width / (s1.length - 1)));
      final double y1 = paddingTop + height - ((s1[i] - minVal) * yScaler);
      final double y2 = paddingTop + height - ((s2[i] - minVal) * yScaler);

      s1Points.add(Offset(x, y1));
      s2Points.add(Offset(x, y2));
    }

    // Desenhar Área Preenchida Suave sob o Cenário 2 (Valuation)
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
          AppColors.primary.withValues(alpha: 0.18),
          AppColors.primary.withValues(alpha: 0.00),
        ],
      ).createShader(Rect.fromLTWH(paddingLeft, paddingTop, width, height));
    canvas.drawPath(fillPath, fillPaint);

    // Desenhar Linha do Cenário 1 (Apenas Ações)
    final Path path1 = Path();
    path1.moveTo(s1Points.first.dx, s1Points.first.dy);
    for (int i = 1; i < s1Points.length; i++) {
      path1.lineTo(s1Points[i].dx, s1Points[i].dy);
    }
    final Paint linePaint1 = Paint()
      ..color = isLight ? Colors.black26 : Colors.white30
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path1, linePaint1);

    // Desenhar Linha do Cenário 2 (Valuation) com Gradiente
    final Path path2 = Path();
    path2.moveTo(s2Points.first.dx, s2Points.first.dy);
    for (int i = 1; i < s2Points.length; i++) {
      path2.lineTo(s2Points[i].dx, s2Points[i].dy);
    }
    final Paint linePaint2 = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.primary,
          AppColors.primaryLight,
        ],
      ).createShader(Rect.fromLTWH(paddingLeft, paddingTop, width, height))
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path2, linePaint2);

    // --- DESENHAR PONTOS DE COMPRA (INTERATIVOS) ---
    final Paint markerBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 1. Cenário 1: Buy & Hold (Aportes Mensais regulares)
    final Paint s1MarkerPaint = Paint()
      ..color = isLight ? const Color(0xFF94A3B8) : const Color(0xFF64748B)
      ..style = PaintingStyle.fill;
    for (final idx in s1PurchaseIndices) {
      if (idx < s1Points.length) {
        final pt = s1Points[idx];
        canvas.drawCircle(pt, 4.0, s1MarkerPaint);
        canvas.drawCircle(pt, 4.0, markerBorderPaint);
      }
    }

    // 2. Cenário 2: Compra de Ação (Valuation Batido)
    final Paint s2StockMarkerPaint = Paint()
      ..color = const Color(0xFF00CC8F) // Vibrant emerald green for stock buy
      ..style = PaintingStyle.fill;
    for (final idx in s2StockPurchaseIndices) {
      if (idx < s2Points.length) {
        final pt = s2Points[idx];
        canvas.drawCircle(pt, 4.5, s2StockMarkerPaint);
        canvas.drawCircle(pt, 4.5, markerBorderPaint);
      }
    }

    // 3. Cenário 2: Compra de FII (Safe Haven)
    final Paint s2FiiMarkerPaint = Paint()
      ..color = const Color(0xFFF59E0B) // Vibrant gold/orange for FII buy
      ..style = PaintingStyle.fill;
    for (final idx in s2FiiPurchaseIndices) {
      if (idx < s2Points.length) {
        final pt = s2Points[idx];
        canvas.drawCircle(pt, 4.5, s2FiiMarkerPaint);
        canvas.drawCircle(pt, 4.5, markerBorderPaint);
      }
    }

    // --- DESENHAR DESTAQUE DO PONTO BLOQUEADO/SELECIONADO (LOCKED INDEX) ---
    if (lockedIndex != null && lockedIndex! < s1Points.length) {
      final Offset pt1 = s1Points[lockedIndex!];
      final Offset pt2 = s2Points[lockedIndex!];

      // Cenário 1 Locked Glow Ring
      canvas.drawCircle(
        pt1,
        8.0,
        Paint()
          ..color = (isLight ? Colors.black26 : Colors.white30).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // Cenário 2 Locked Glow Ring
      canvas.drawCircle(
        pt2,
        9.0,
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // --- DESENHAR LINHAS E PONTOS DO HOVER/SELEÇÃO INTERATIVA ---
    final int? activeHighlightIdx = selectedIndex ?? lockedIndex;
    if (activeHighlightIdx != null && activeHighlightIdx < s1Points.length) {
      final Offset pt1 = s1Points[activeHighlightIdx];
      final Offset pt2 = s2Points[activeHighlightIdx];

      // Desenhar Linha Vertical Tracejada de Seleção
      final Paint dashedPaint = Paint()
        ..color = isLight ? Colors.black26 : Colors.white30
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      
      double startY = paddingTop;
      final double endY = size.height - paddingBottom;
      const double dashHeight = 5.0;
      const double dashSpace = 3.0;
      while (startY < endY) {
        canvas.drawLine(Offset(pt1.dx, startY), Offset(pt1.dx, startY + dashHeight), dashedPaint);
        startY += dashHeight + dashSpace;
      }

      // Desenhar Pontos de Interseção
      // Cenário 1 (Apenas Ações)
      canvas.drawCircle(pt1, 5.5, Paint()..color = isLight ? Colors.black45 : Colors.white60);
      canvas.drawCircle(pt1, 3.5, Paint()..color = Colors.white);

      // Cenário 2 (Valuation)
      canvas.drawCircle(pt2, 6.5, Paint()..color = AppColors.primary);
      canvas.drawCircle(pt2, 3.5, Paint()..color = Colors.white);
    }
  }

  String _formatCompactCurrency(double val) {
    if (val >= 1000000) {
      return 'R\$ ${(val / 1000000).toStringAsFixed(1)}M';
    } else if (val >= 1000) {
      return 'R\$ ${(val / 100).round() / 10}k';
    }
    return 'R\$ ${val.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(covariant _PortfolioChartPainter oldDelegate) => true;
}
