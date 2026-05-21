import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/backtest.dart';
import '../controllers/backtest_controller.dart';
import '../utils/date_utils.dart';

/// Widget para entrada de parâmetros do backtest
class BacktestInputPage extends StatefulWidget {
  const BacktestInputPage({super.key});

  @override
  State<BacktestInputPage> createState() => _BacktestInputPageState();
}

class _BacktestInputPageState extends State<BacktestInputPage> {
  late TextEditingController _stockTickerController;
  late TextEditingController _fiiTickerController;
  late TextEditingController _monthlyInvestmentController;
  late TextEditingController _safetyMarginController;
  late TextEditingController _desiredRateController;

  DateTime _startDate = BrazilianDateUtils.tenYearsAgo(DateTime.now());
  DateTime _endDate = DateTime.now();
  ValuationMethod _selectedValuationMethod = ValuationMethod.graham;

  @override
  void initState() {
    super.initState();
    _stockTickerController = TextEditingController();
    _fiiTickerController = TextEditingController();
    _monthlyInvestmentController = TextEditingController(text: '1000');
    _safetyMarginController = TextEditingController(text: '20');
    _desiredRateController = TextEditingController(text: '6');
  }

  @override
  void dispose() {
    _stockTickerController.dispose();
    _fiiTickerController.dispose();
    _monthlyInvestmentController.dispose();
    _safetyMarginController.dispose();
    _desiredRateController.dispose();
    super.dispose();
  }

  DateTime get _maxAllowedStartDate => BrazilianDateUtils.tenYearsAgo(DateTime.now());

  void _applyDynamicDateBounds() {
    final now = DateTime.now();
    final maxStartDate = _maxAllowedStartDate;

    if (_endDate.isAfter(now)) {
      _endDate = now;
    }
    if (_endDate.isBefore(maxStartDate)) {
      _endDate = maxStartDate;
    }
    if (_startDate.isBefore(maxStartDate)) {
      _startDate = maxStartDate;
    }
    if (_startDate.isAfter(_endDate)) {
      _startDate = _endDate;
    }
  }

  /// Valida os inputs do usuário
  bool _validateInputs() {
    final errors = <String>[];

    if (_stockTickerController.text.isEmpty) {
      errors.add('Ticker da ação é obrigatório');
    }

    if (_fiiTickerController.text.isEmpty) {
      errors.add('Ticker do FII é obrigatório');
    }

    if (_monthlyInvestmentController.text.isEmpty ||
        double.tryParse(_monthlyInvestmentController.text) == null ||
        double.parse(_monthlyInvestmentController.text) <= 0) {
      errors.add('Aporte mensal deve ser maior que 0');
    }

    if (_startDate.isAfter(_endDate)) {
      errors.add('Data inicial deve ser antes da data final');
    }

    if (_startDate.isBefore(_maxAllowedStartDate)) {
      errors.add('Data inicial não pode ser anterior a 10 anos atrás');
    }

    if (_endDate.isBefore(_maxAllowedStartDate)) {
      errors.add('Data final deve estar dentro dos últimos 10 anos');
    }

    if (errors.isNotEmpty) {
      _showErrorDialog(errors.join('\n'));
      return false;
    }

    return true;
  }

  /// Inicia o backtest
  Future<void> _runBacktest() async {
    _applyDynamicDateBounds();
    if (!_validateInputs()) return;

    final config = BacktestConfig(
      stockTicker: _stockTickerController.text.toUpperCase(),
      fiiTicker: _fiiTickerController.text.toUpperCase(),
      startDate: _startDate,
      endDate: _endDate,
      monthlyInvestment: double.parse(_monthlyInvestmentController.text),
      valuationMethod: _selectedValuationMethod,
      safetyMargin: double.parse(_safetyMarginController.text),
      desiredRate: double.parse(_desiredRateController.text) / 100,
    );

    if (!mounted) return;

    final controller = context.read<BacktestController>();
    final success = await controller.executeBacktest(config);

    if (success && mounted) {
      // Navega para tela de resultados
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const BacktestResultsPage(),
        ),
      );
    }
  }

  /// Exibe diálogo de erro
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro de Validação'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Abre seletor de data
  Future<void> _selectDate(bool isStartDate) async {
    _applyDynamicDateBounds();
    final maxStartDate = _maxAllowedStartDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _startDate : _endDate,
      firstDate: maxStartDate,
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Backtest'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Seção: Ativos
              _buildSectionTitle('📈 Ativos'),
              const SizedBox(height: 12),
              _buildTickerField(
                label: 'Ticker da Ação',
                hint: 'ex: PETR4',
                controller: _stockTickerController,
              ),
              const SizedBox(height: 12),
              _buildTickerField(
                label: 'Ticker do FII',
                hint: 'ex: HGLG11',
                controller: _fiiTickerController,
              ),
              const SizedBox(height: 24),

              // Seção: Período
              _buildSectionTitle('📅 Período'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDateField(
                      label: 'Data Inicial',
                      date: _startDate,
                      onTap: () => _selectDate(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDateField(
                      label: 'Data Final',
                      date: _endDate,
                      onTap: () => _selectDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Seção: Investimento
              _buildSectionTitle('💰 Investimento'),
              const SizedBox(height: 12),
              _buildNumberField(
                label: 'Aporte Mensal (R\$)',
                controller: _monthlyInvestmentController,
                prefix: 'R\$ ',
              ),
              const SizedBox(height: 24),

              // Seção: Valuation
              _buildSectionTitle('📊 Método de Valuation'),
              const SizedBox(height: 12),
              _buildValuationMethodSelector(),
              const SizedBox(height: 24),

              // Seção: Parâmetros Avançados
              _buildSectionTitle('⚙️ Parâmetros Avançados'),
              const SizedBox(height: 12),
              _buildNumberField(
                label: 'Margem de Segurança (%)',
                controller: _safetyMarginController,
                suffix: '%',
              ),
              const SizedBox(height: 12),
              _buildNumberField(
                label: 'Taxa Desejada (Bazin) (%)',
                controller: _desiredRateController,
                suffix: '%',
              ),
              const SizedBox(height: 32),

              // Botão de Ação
              Consumer<BacktestController>(
                builder: (context, controller, _) {
                  return ElevatedButton.icon(
                    onPressed: controller.isLoading ? null : _runBacktest,
                    icon: controller.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(controller.isLoading ? 'Processando...' : 'Executar Backtest'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Constrói título de seção
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// Constrói campo de ticker
  Widget _buildTickerField({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.trending_up),
      ),
      textCapitalization: TextCapitalization.characters,
    );
  }

  /// Constrói campo de data
  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(date),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói campo numérico
  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    String? prefix,
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixText: prefix,
        suffixText: suffix,
      ),
    );
  }

  /// Constrói seletor de método de valuation
  Widget _buildValuationMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final method in ValuationMethod.values)
          RadioListTile<ValuationMethod>(
            title: Text(method.label),
            value: method,
            groupValue: _selectedValuationMethod,
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedValuationMethod = value);
              }
            },
          ),
      ],
    );
  }

  /// Formata data no padrão brasileiro
  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }
}

/// Página de resultados do backtest (placeholder)
class BacktestResultsPage extends StatelessWidget {
  const BacktestResultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados do Backtest'),
      ),
      body: Consumer<BacktestController>(
        builder: (context, controller, _) {
          final result = controller.lastResult;

          if (result == null) {
            return const Center(
              child: Text('Nenhum resultado disponível'),
            );
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildResultCard(
                    title: 'CENÁRIO 1: Buy and Hold',
                    scenario: result.scenario1,
                    isWinner: result.scenario1.finalValue > result.scenario2.finalValue,
                  ),
                  const SizedBox(height: 16),
                  _buildResultCard(
                    title: 'CENÁRIO 2: Valuation Inteligente',
                    scenario: result.scenario2,
                    isWinner: result.scenario2.finalValue > result.scenario1.finalValue,
                  ),
                  const SizedBox(height: 24),
                  _buildComparisonCard(result),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Voltar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Constrói card de resultado de cenário
  Widget _buildResultCard({
    required String title,
    required BacktestScenarioResult scenario,
    required bool isWinner,
  }) {
    return Card(
      elevation: isWinner ? 8 : 2,
      color: isWinner ? Colors.green.shade50 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isWinner)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'VENCEDOR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetricRow(
              'Valor Final',
              'R\$ ${scenario.finalValue.toStringAsFixed(2)}',
            ),
            _buildMetricRow(
              'Retorno Total',
              '${scenario.totalReturn.toStringAsFixed(2)}%',
            ),
            _buildMetricRow(
              'CAGR',
              '${scenario.cagr.toStringAsFixed(2)}%',
            ),
            _buildMetricRow(
              'Dividendos',
              'R\$ ${scenario.totalDividends.toStringAsFixed(2)}',
            ),
            _buildMetricRow(
              'Ações',
              '${scenario.finalStockShares}',
            ),
            _buildMetricRow(
              'FIIs',
              '${scenario.finalFiiShares}',
            ),
            _buildMetricRow(
              'Caixa Final',
              'R\$ ${scenario.finalCash.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói card de comparação
  Widget _buildComparisonCard(BacktestResult result) {
    final winner = result.getWinner();
    final difference = result.getAbsoluteDifference();
    final percentageDiff = result.getPercentageDifference();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚖️ COMPARAÇÃO',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    'Vencedor: ${winner.scenarioName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMetricRow(
                    'Diferença Absoluta',
                    'R\$ ${difference.toStringAsFixed(2)}',
                  ),
                  _buildMetricRow(
                    'Diferença Percentual',
                    '${percentageDiff.toStringAsFixed(2)}%',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói linha de métrica
  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
