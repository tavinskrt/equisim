import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:math';
import 'package:intl/intl.dart';
import '../controllers/backtest_controller.dart';
import '../controllers/theme_controller.dart';
import '../controllers/home_controller.dart';
import '../utils/app_colors.dart';
import 'backtest_detail_page.dart';

/// Tela que exibe a listagem de simulações de backtest salvas no histórico do usuário.
class BacktestHistoryPage extends StatefulWidget {
  final HomeController? homeController;
  const BacktestHistoryPage({super.key, this.homeController});

  @override
  State<BacktestHistoryPage> createState() => _BacktestHistoryPageState();
}

class _BacktestHistoryPageState extends State<BacktestHistoryPage> {
  String _searchQuery = '';
  String _selectedFilter = 'todos'; // 'todos', 'buyHold', 'valuation'

  @override
  void initState() {
    super.initState();
    // Garante que o histórico esteja atualizado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BacktestController>(context, listen: false).fetchHistory();
    });
  }

  /// Calcula a rentabilidade do cenário vencedor para fins de métricas globais
  double _getWinnerReturn(Map<String, dynamic> bt) {
    final double retBh = (bt['totalReturnBuyHold'] ?? 0.0) as double;
    final double retVal = (bt['totalReturnValuation'] ?? 0.0) as double;
    return max(retBh, retVal);
  }

  /// Exibe diálogo de confirmação antes de excluir a simulação do histórico
  void _confirmDelete(BuildContext context, BacktestController controller, String backtestId, bool isLight) {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: isLight ? Colors.white : const Color(0xFF0D1E3A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isLight ? AppColors.surfaceBorder(true) : Colors.white10),
            ),
            title: Text(
              'Excluir Simulação',
              style: TextStyle(
                color: AppColors.textPrimary(isLight),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            content: Text(
              'Tem certeza que deseja remover esta simulação permanentemente do seu histórico?',
              style: TextStyle(
                color: AppColors.textSecondary(isLight),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: isLight ? AppColors.textSecondary(true) : Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context); // Fecha o diálogo
                  final success = await controller.deleteBacktest(backtestId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Simulação excluída com sucesso.'
                              : 'Erro ao tentar excluir simulação.',
                        ),
                        backgroundColor: success ? AppColors.primary : AppColors.danger,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text(
                  'Excluir',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final backtestController = Provider.of<BacktestController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    final history = backtestController.savedBacktests;

    // Filtra a lista de acordo com a busca e pílulas de filtro
    final filteredHistory = history.where((bt) {
      final String stock = (bt['stockTicker'] ?? '').toString().toLowerCase();
      final String fii = (bt['fiiTicker'] ?? '').toString().toLowerCase();
      final String methodLabel = (bt['valuationMethodLabel'] ?? '').toString().toLowerCase();
      final String query = _searchQuery.toLowerCase().trim();

      // Filtro de Busca
      final matchesSearch = query.isEmpty ||
          stock.contains(query) ||
          fii.contains(query) ||
          methodLabel.contains(query);

      if (!matchesSearch) return false;

      // Filtro de Pílulas
      final double retBh = (bt['totalReturnBuyHold'] ?? 0.0) as double;
      final double retVal = (bt['totalReturnValuation'] ?? 0.0) as double;

      if (_selectedFilter == 'buyHold') {
        return retBh >= retVal;
      } else if (_selectedFilter == 'valuation') {
        return retVal > retBh;
      }

      return true;
    }).toList();

    // Calcula estatísticas globais (Melhor retorno e Média de retorno) baseados no método vencedor
    double bestReturn = 0.0;
    double avgReturn = 0.0;

    if (history.isNotEmpty) {
      double total = 0.0;
      for (final bt in history) {
        final double winRet = _getWinnerReturn(bt);
        total += winRet;
        if (winRet > bestReturn) {
          bestReturn = winRet;
        }
      }
      avgReturn = total / history.length;
    }

    final numberFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(isLight),
        ),
        child: Stack(
          children: [
            // Efeitos de círculos de fundo
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
                // Header superior translúcido (Glassmorphism)
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    Text(
                                      'Histórico',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(isLight),
                                        height: 1.2,
                                      ),
                                    ),
                                    Text(
                                      '${history.length} backtests realizados',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Barra de busca
                          Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.inputBackground(isLight),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            ),
                            child: TextField(
                              textAlignVertical: TextAlignVertical.center,
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary(isLight),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Buscar ticker ou método...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted(isLight),
                                ),
                                border: InputBorder.none,
                                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 16,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.only(top: 10, bottom: 10, right: 10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Pílulas de filtro
                          Row(
                            children: [
                              _buildFilterPill(
                                label: 'Todos',
                                filterId: 'todos',
                                icon: Icons.filter_list,
                                isLight: isLight,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterPill(
                                label: 'Buy & Hold',
                                filterId: 'buyHold',
                                icon: Icons.lock_outline,
                                isLight: isLight,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterPill(
                                label: 'Valuation Inteligente',
                                filterId: 'valuation',
                                icon: Icons.psychology,
                                isLight: isLight,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Painel de métricas gerais (Melhor retorno e Média de retorno)
                Container(
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.015),
                    border: Border(bottom: BorderSide(color: AppColors.surfaceBorder(isLight))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: AppColors.surfaceBorder(isLight)),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${bestReturn >= 0 ? '+' : ''}${bestReturn.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'MELHOR RETORNO',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: AppColors.textSecondary(isLight),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Text(
                                '${avgReturn >= 0 ? '+' : ''}${avgReturn.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary(isLight),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'MÉDIA DE RETORNO',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: AppColors.textSecondary(isLight),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de simulações do histórico
                Expanded(
                  child: backtestController.loadingHistory
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        )
                      : filteredHistory.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.query_stats_outlined,
                                    size: 40,
                                    color: AppColors.textMuted(isLight),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nenhum resultado encontrado.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary(isLight),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filteredHistory.length,
                              itemBuilder: (context, index) {
                                final bt = filteredHistory[index];
                                final id = bt['id'] as String;

                                // Formata data
                                String formattedDate = '';
                                try {
                                  final execDate = DateTime.parse(bt['executionDate'] as String);
                                  formattedDate = DateFormat('dd/MM/yyyy').format(execDate);
                                } catch (e) {
                                  formattedDate = (bt['date'] ?? '').toString();
                                }

                                final double retBh = (bt['totalReturnBuyHold'] ?? 0.0) as double;
                                final double retVal = (bt['totalReturnValuation'] ?? 0.0) as double;
                                final double totalInvested = (bt['totalInvested'] ?? 0.0) as double;
                                final int period = (bt['periodMonths'] ?? 0) as int;
                                final String valuationMethod = (bt['valuationMethodLabel'] ?? '').toString();
                                final List<dynamic> tickers = [
                                  bt['stockTicker'] ?? '',
                                  bt['fiiTicker'] ?? ''
                                ];

                                // Determina o vencedor da simulação
                                final bool valuationWon = retVal > retBh;

                                // Coleta os pontos da curva de Valuation para o Sparkline
                                final List<double> sparklineData =
                                    List<double>.from(bt['monthlyValuesValuation'] ?? []);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  color: AppColors.surface(isLight),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(color: AppColors.surfaceBorder(isLight)),
                                  ),
                                  elevation: isLight ? 2 : 0,
                                  shadowColor: Colors.black.withValues(alpha: 0.05),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => BacktestDetailPage(backtestData: bt),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // Data + Badge Vencedor + Botão Excluir
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                formattedDate,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.textSecondary(isLight),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: valuationWon
                                                          ? AppColors.primary.withValues(alpha: 0.1)
                                                          : Colors.blue.withValues(alpha: 0.1),
                                                      border: Border.all(
                                                        color: valuationWon
                                                            ? AppColors.primary.withValues(alpha: 0.25)
                                                            : Colors.blue.withValues(alpha: 0.25),
                                                      ),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      valuationWon ? '▲ Valuation' : '▲ Buy & Hold',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: valuationWon
                                                            ? const Color(0xFF00CC8F)
                                                            : Colors.blue,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  IconButton(
                                                    icon: const Icon(Icons.copy_outlined, size: 16),
                                                    color: const Color.fromARGB(0, 58, 58, 58).withValues(alpha: 0.8),
                                                    constraints: const BoxConstraints(),
                                                    padding: EdgeInsets.zero,
                                                    tooltip: 'Copiar parâmetros',
                                                    onPressed: () {
                                                      if (widget.homeController != null) {
                                                        final hc = widget.homeController!;
                                                        hc.setStockTicker(bt['stockTicker'] ?? '');
                                                        hc.setFiiTicker(bt['fiiTicker'] ?? '');
                                                        
                                                        if (bt['startDate'] != null) {
                                                          final parsed = DateTime.tryParse(bt['startDate']);
                                                          if (parsed != null) hc.setStartDate(parsed);
                                                        }
                                                        if (bt['endDate'] != null) {
                                                          final parsed = DateTime.tryParse(bt['endDate']);
                                                          if (parsed != null) hc.setEndDate(parsed);
                                                        }
                                                        
                                                        final monthlyInvestment = (bt['monthlyInvestment'] ?? 0.0).toDouble();
                                                        final int cents = (monthlyInvestment * 100).round();
                                                        hc.setAporte(cents.toString());
                                                        
                                                        String valMethod = bt['valuationMethod'] ?? 'graham';
                                                        if (valMethod == 'peterLynch') {
                                                          valMethod = 'lynch';
                                                        }
                                                        hc.setValuation(valMethod);
                                                        
                                                        final safetyMargin = (bt['safetyMargin'] ?? 20.0).toDouble();
                                                        hc.setMargem(safetyMargin.toStringAsFixed(0));
                                                        
                                                        if (valMethod == 'dcf') {
                                                          hc.setDcfDiscountRate((bt['dcfDiscountRate'] ?? 12.0).toDouble().toStringAsFixed(0));
                                                          hc.setDcfGrowthRate((bt['dcfGrowthRate'] ?? 8.0).toDouble().toStringAsFixed(0));
                                                          hc.setDcfPerpetualGrowth((bt['dcfPerpetualGrowth'] ?? 4.0).toDouble().toStringAsFixed(0));
                                                          hc.setDcfProjectionYears((bt['dcfProjectionYears'] ?? 5).toInt());
                                                        }
                                                        
                                                        hc.setDiaCompra(bt['diaCompra'] ?? 5);
                                                        hc.setConsiderarReinvestimento(bt['considerarReinvestimento'] ?? true);
                                                      }
                                                      Navigator.pop(context); // Voltar para a tela inicial
                                                    },
                                                  ),
                                                  const SizedBox(width: 8),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline, size: 20),
                                                    color: AppColors.danger.withValues(alpha: 0.7),
                                                    constraints: const BoxConstraints(),
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () => _confirmDelete(
                                                      context,
                                                      backtestController,
                                                      id,
                                                      isLight,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),

                                          // Tickers + Sparkline
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // Tickers
                                                    Row(
                                                      children: tickers.map((t) {
                                                        if (t.toString().isEmpty) return const SizedBox.shrink();
                                                        return Container(
                                                          margin: const EdgeInsets.only(right: 6, bottom: 4),
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.primary.withValues(alpha: 0.08),
                                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            t,
                                                            style: const TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w800,
                                                              color: AppColors.primary,
                                                              letterSpacing: 0.3,
                                                            ),
                                                          ),
                                                        );
                                                      }).toList(),
                                                    ),
                                                    const SizedBox(height: 4),

                                                    // Atributos secundários
                                                    Row(
                                                      children: [
                                                        _buildAttributeTile('MÉTODO', valuationMethod, isLight),
                                                        const SizedBox(width: 14),
                                                        _buildAttributeTile('PERÍODO', '$period meses', isLight),
                                                        const SizedBox(width: 14),
                                                        _buildAttributeTile('APORTE', numberFormat.format(totalInvested), isLight),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Mini sparkline customizado
                                              SizedBox(
                                                width: 80,
                                                height: 28,
                                                child: CustomPaint(
                                                  painter: _MiniSparklinePainter(
                                                    data: sparklineData,
                                                    up: retVal >= 0,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // Sub-retornos (Buy & Hold vs Valuation Inteligente)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isLight
                                                  ? Colors.black.withValues(alpha: 0.02)
                                                  : Colors.white.withValues(alpha: 0.02),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'BUY & HOLD',
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        color: AppColors.textSecondary(isLight),
                                                        letterSpacing: 0.4,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${retBh >= 0 ? '+' : ''}${retBh.toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w800,
                                                        color: retBh >= 0
                                                            ? AppColors.textPrimary(isLight)
                                                            : AppColors.danger,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      'VALUATION INTELIGENTE',
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        color: AppColors.textSecondary(isLight),
                                                        letterSpacing: 0.4,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${retVal >= 0 ? '+' : ''}${retVal.toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w800,
                                                        color: retVal >= 0
                                                            ? const Color(0xFF00CC8F)
                                                            : AppColors.danger,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói um pilar menor de atributo secundário
  Widget _buildAttributeTile(String label, String value, bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: AppColors.textMuted(isLight),
            letterSpacing: 0.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(isLight),
          ),
        ),
      ],
    );
  }

  /// Constrói as pílulas de filtros superiores (Todos, Buy & Hold, Valuation)
  Widget _buildFilterPill({
    required String label,
    required String filterId,
    required IconData icon,
    required bool isLight,
  }) {
    final bool isSelected = _selectedFilter == filterId;

    Color badgeColor = Colors.transparent;
    Color textColor = AppColors.textSecondary(isLight);
    Color borderColor = isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.08);

    if (isSelected) {
      borderColor = Colors.transparent;
      if (filterId == 'buyHold') {
        badgeColor = Colors.blue.withValues(alpha: 0.15);
        textColor = Colors.blue;
      } else if (filterId == 'valuation') {
        badgeColor = AppColors.primary.withValues(alpha: 0.15);
        textColor = const Color(0xFF00CC8F);
      } else {
        badgeColor = isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.1);
        textColor = AppColors.textPrimary(isLight);
      }
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filterId;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: badgeColor,
          border: Border.all(color: isSelected ? Colors.transparent : borderColor),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: textColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter para desenhar o Sparkline fiel dos dados patrimoniais de simulação
class _MiniSparklinePainter extends CustomPainter {
  final List<double> data;
  final bool up;

  _MiniSparklinePainter({required this.data, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double maxVal = data.reduce(max);
    final double minVal = data.reduce(min);
    final double range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;

    final double width = size.width;
    final double height = size.height;

    final List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      final double x = (i / (data.length - 1)) * width;
      final double y = height - ((data[i] - minVal) / range) * height;
      points.add(Offset(x, y));
    }

    final Path path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final Color color = up ? const Color(0xFF00B37E) : const Color(0xFFEF4444);
    final Color fillColor = up ? const Color(0x2200B37E) : const Color(0x1CEF4444);

    // 1. Desenha a área preenchida abaixo da curva
    final Path fillPath = Path();
    fillPath.addPath(path, Offset.zero);
    fillPath.lineTo(width, height);
    fillPath.lineTo(0, height);
    fillPath.close();

    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 2. Desenha a linha da curva
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
