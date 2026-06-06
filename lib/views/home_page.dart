import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/home_controller.dart';
import '../controllers/backtest_controller.dart';
import '../controllers/theme_controller.dart';
import '../models/backtest.dart';
import '../utils/app_colors.dart';
import 'login_page.dart';
import 'backtest_results_page.dart';
import 'profile_page.dart';
import 'backtest_history_page.dart';

/// Tela inicial que abriga o formulário de simulação de investimentos.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeController(),
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  const _HomeScreenContent();

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> {
  bool _dropdownOpen = false;
  late final TextEditingController _aporteController;
  late final TextEditingController _margemController;
  late final TextEditingController _dcfDiscountRateController;
  late final TextEditingController _dcfGrowthRateController;
  late final TextEditingController _dcfPerpetualGrowthController;
  late final TextEditingController _stockController;
  late final TextEditingController _fiiController;
  
  bool _initialized = false;
  late HomeController _homeController;

  bool _showStockSuggestions = false;
  bool _showFiiSuggestions = false;
  bool _isExecuting = false;

  // Lista dos ativos brasileiros mais populares para autocomplete local imediato
  final List<String> _popularStocks = [
    'PETR4', 'VALE3', 'ITUB4', 'BBDC4', 'BBAS3', 'ABEV3', 'WEGE3', 'ITSA4', 
    'BOVA11', 'SANB11', 'MGLU3', 'ELET3', 'B3SA3', 'RENT3', 'EQTL3'
  ];

  final List<String> _popularFiis = [
    'MXRF11', 'HGLG11', 'XPLG11', 'KNIP11', 'KNCR11', 'HGRU11', 'XPML11', 
    'VISC11', 'BTLG11', 'JSRE11', 'IRDM11', 'CPTS11', 'HGBS11', 'VILG11', 'BCFF11'
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _homeController = Provider.of<HomeController>(context, listen: false);
      _aporteController = TextEditingController(text: _homeController.aporte);
      _margemController = TextEditingController(text: _homeController.margem);
      _dcfDiscountRateController = TextEditingController(text: _homeController.dcfDiscountRate);
      _dcfGrowthRateController = TextEditingController(text: _homeController.dcfGrowthRate);
      _dcfPerpetualGrowthController = TextEditingController(text: _homeController.dcfPerpetualGrowth);
      _stockController = TextEditingController(text: _homeController.stockTicker);
      _fiiController = TextEditingController(text: _homeController.fiiTicker);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _aporteController.dispose();
    _margemController.dispose();
    _dcfDiscountRateController.dispose();
    _dcfGrowthRateController.dispose();
    _dcfPerpetualGrowthController.dispose();
    _stockController.dispose();
    _fiiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<HomeController>(context);
    final backtestController = Provider.of<BacktestController>(context);

    // Sincroniza dinamicamente as alterações de estado nos controllers locais
    final currentAporte = controller.aporte;
    if (_aporteController.text != currentAporte) {
      _aporteController.value = TextEditingValue(
        text: currentAporte,
        selection: TextSelection.collapsed(offset: currentAporte.length),
      );
    }

    final currentMargem = controller.margem;
    if (_margemController.text != currentMargem) {
      _margemController.value = TextEditingValue(
        text: currentMargem,
        selection: TextSelection.collapsed(offset: currentMargem.length),
      );
    }

    final currentDcfDiscountRate = controller.dcfDiscountRate;
    if (_dcfDiscountRateController.text != currentDcfDiscountRate) {
      _dcfDiscountRateController.value = TextEditingValue(
        text: currentDcfDiscountRate,
        selection: TextSelection.collapsed(offset: currentDcfDiscountRate.length),
      );
    }

    final currentDcfGrowthRate = controller.dcfGrowthRate;
    if (_dcfGrowthRateController.text != currentDcfGrowthRate) {
      _dcfGrowthRateController.value = TextEditingValue(
        text: currentDcfGrowthRate,
        selection: TextSelection.collapsed(offset: currentDcfGrowthRate.length),
      );
    }

    final currentDcfPerpetualGrowth = controller.dcfPerpetualGrowth;
    if (_dcfPerpetualGrowthController.text != currentDcfPerpetualGrowth) {
      _dcfPerpetualGrowthController.value = TextEditingValue(
        text: currentDcfPerpetualGrowth,
        selection: TextSelection.collapsed(offset: currentDcfPerpetualGrowth.length),
      );
    }

    final currentStock = controller.stockTicker;
    if (_stockController.text != currentStock) {
      _stockController.value = TextEditingValue(
        text: currentStock,
        selection: TextSelection.collapsed(offset: currentStock.length),
      );
    }

    final currentFii = controller.fiiTicker;
    if (_fiiController.text != currentFii) {
      _fiiController.value = TextEditingValue(
        text: currentFii,
        selection: TextSelection.collapsed(offset: currentFii.length),
      );
    }

    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'usuario@email.com';
    final userName = (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!
        : 'Usuário';

    // Exibe aviso reativo sobre renomeação automática de ativos (ex: VVAR3 para BHIA3)
    if (controller.renamedMessage != null) {
      final msg = controller.renamedMessage!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      msg,
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2563EB),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      });
      controller.clearRenamedMessage();
    }

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          setState(() {
            _dropdownOpen = false;
            _showStockSuggestions = false;
            _showFiiSuggestions = false;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(isLight),
          ),
          child: Stack(
            children: [
              // Elementos decorativos no plano de fundo
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

              // Layout principal da tela
              Column(
                children: [
                  // Barra de cabeçalho superior translúcida (Glassmorphism)
                  ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.only(top: 52, left: 20, right: 20, bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundStart(isLight).withValues(alpha: 0.6),
                          border: Border(bottom: BorderSide(color: AppColors.surfaceBorder(isLight))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    gradient: AppColors.brandGradient,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.show_chart, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Equisim',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(isLight),
                                        height: 1.1,
                                      ),
                                    ),
                                    Text(
                                      'NOVA SIMULAÇÃO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            
                            // Avatar de perfil e controle de menu
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _dropdownOpen = !_dropdownOpen;
                                });
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _dropdownOpen
                                      ? AppColors.primary.withValues(alpha: 0.25)
                                      : AppColors.primary.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: _dropdownOpen
                                        ? AppColors.primary
                                        : AppColors.primary.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(Icons.person_outline, color: AppColors.primary, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Área rolável de inputs do formulário
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Seleção de Ativos (Ações e FIIs)
                          _SectionCard(
                            icon: Icons.ssid_chart,
                            title: 'Ativos',
                            subtitle: 'Selecione uma Ação e um Fundo Imobiliário',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AÇÃO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary(isLight),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildAutocompleteField(
                                  key: const ValueKey('stock_ticker_field'),
                                  controller: _stockController,
                                  placeholder: 'Ex.: PETR4',
                                  onChange: controller.setStockTicker,
                                  popularSuggestions: _popularStocks,
                                  allSuggestions: controller.allStocks,
                                  showSuggestions: _showStockSuggestions,
                                  onFocus: () {
                                    setState(() {
                                      _showStockSuggestions = true;
                                      _showFiiSuggestions = false;
                                    });
                                  },
                                  isLight: isLight,
                                  errorText: controller.stockError,
                                ),
                                
                                const SizedBox(height: 16),
                                
                                Text(
                                  'FUNDO IMOBILIÁRIO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary(isLight),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildAutocompleteField(
                                  key: const ValueKey('fii_ticker_field'),
                                  controller: _fiiController,
                                  placeholder: 'Ex.: HGLG11',
                                  onChange: controller.setFiiTicker,
                                  popularSuggestions: _popularFiis,
                                  allSuggestions: controller.allFiis,
                                  showSuggestions: _showFiiSuggestions,
                                  onFocus: () {
                                    setState(() {
                                      _showFiiSuggestions = true;
                                      _showStockSuggestions = false;
                                    });
                                  },
                                  isLight: isLight,
                                  errorText: controller.fiiError,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 2. Seleção de Intervalo Histórico
                          _SectionCard(
                            icon: Icons.calendar_month_outlined,
                            title: 'Período',
                            subtitle: 'Janela histórica de análise (máximo 10 anos)',
                            child: Row(
                              children: [
                                Expanded(
                                  child: _DatePickerField(
                                    label: 'Data inicial',
                                    selectedDate: controller.startDate,
                                    onSelect: controller.setStartDate,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DatePickerField(
                                    label: 'Data final',
                                    selectedDate: controller.endDate,
                                    onSelect: controller.setEndDate,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 3. Seleção de Aporte e Dia de Compra
                          _SectionCard(
                            icon: Icons.attach_money,
                            title: 'Aporte mensal',
                            subtitle: 'Valor investido e dia de compra',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VALOR DO APORTE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary(isLight),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: AppColors.inputBackground(isLight),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                            ),
                                            child: Row(
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 14, right: 8),
                                                  child: Text(
                                                    'R\$',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.textMuted(isLight),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    keyboardType: TextInputType.number,
                                                    onChanged: controller.setAporte,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.textPrimary(isLight),
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText: '0,00',
                                                      hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                                      border: InputBorder.none,
                                                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                                                    ),
                                                    controller: _aporteController,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'DIA DA COMPRA',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary(isLight),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: AppColors.inputBackground(isLight),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<int>(
                                                value: controller.diaCompra,
                                                icon: Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary(isLight)),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.textPrimary(isLight),
                                                ),
                                                dropdownColor: AppColors.surface(isLight),
                                                onChanged: (int? value) {
                                                  if (value != null) {
                                                    controller.setDiaCompra(value);
                                                  }
                                                },
                                                items: List.generate(28, (index) => index + 1)
                                                    .map<DropdownMenuItem<int>>((int value) {
                                                  return DropdownMenuItem<int>(
                                                    value: value,
                                                    child: Text('Dia $value'),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                
                                // Controle de reinvestimento automático de dividendos
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Reinvestir dividendos',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary(isLight),
                                          ),
                                        ),
                                        Text(
                                          'Utilizar proventos para novos aportes',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary(isLight),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Transform.scale(
                                      scale: 0.85,
                                      child: Switch(
                                        value: controller.considerarReinvestimento,
                                        activeThumbColor: AppColors.primary,
                                        onChanged: controller.setConsiderarReinvestimento,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 4. Seleção da Estratégia de Valuation
                          _SectionCard(
                            icon: Icons.pie_chart_outline,
                            title: 'Método de Valuation',
                            subtitle: 'Critério de avaliação intrínseca',
                            child: GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 7,
                              crossAxisSpacing: 7,
                              childAspectRatio: 2.5,
                              children: [
                                _ValuationButton(
                                  id: 'graham', label: 'Graham', desc: 'P/L e P/VP',
                                  selected: controller.valuation == 'graham',
                                  onTap: () => controller.setValuation('graham'),
                                ),
                                _ValuationButton(
                                  id: 'bazin', label: 'Bazin', desc: 'Dividend Yield',
                                  selected: controller.valuation == 'bazin',
                                  onTap: () => controller.setValuation('bazin'),
                                ),
                                _ValuationButton(
                                  id: 'lynch', label: 'Peter Lynch', desc: 'PEG Ratio',
                                  selected: controller.valuation == 'lynch',
                                  onTap: () => controller.setValuation('lynch'),
                                ),
                                _ValuationButton(
                                  id: 'dcf', label: 'DCF Simplificado', desc: 'Fluxo Descontado',
                                  selected: controller.valuation == 'dcf',
                                  onTap: () => controller.setValuation('dcf'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 5. Parâmetros da Simulação (Margem de Segurança)
                          if (controller.valuation == 'graham')
                            _SectionCard(
                              icon: Icons.tune,
                              title: 'Parâmetros',
                              subtitle: 'Configurações da simulação',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Margem de Segurança',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary(isLight),
                                        ),
                                      ),
                                      Text(
                                        'Desconto mínimo',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textSecondary(isLight),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBackground(isLight),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            keyboardType: TextInputType.number,
                                            onChanged: controller.setMargem,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary(isLight),
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Ex.: 25',
                                              hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                                            ),
                                            controller: _margemController,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(right: 14),
                                          child: Text(
                                            '%',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textMuted(isLight),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  if (controller.margem.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Stack(
                                      children: [
                                        Container(
                                          height: 4,
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceBorder(isLight),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: (int.tryParse(controller.margem) ?? 0).clamp(0, 100) / 100.0,
                                          child: Container(
                                            height: 4,
                                            decoration: BoxDecoration(
                                              gradient: AppColors.brandGradient,
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('0%', style: TextStyle(fontSize: 10, color: AppColors.textMuted(isLight))),
                                        Text(
                                          '${controller.margem}% selecionado',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text('100%', style: TextStyle(fontSize: 10, color: AppColors.textMuted(isLight))),
                                      ],
                                    ),
                                  ],
                                  
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline, color: AppColors.textMuted(isLight), size: 14),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'A ação será comprada somente se seu preço atual estiver pelo menos este percentual abaixo do valor intrínseco calculado por Graham. Caso contrário, compra-se FII.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary(isLight),
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                          if (controller.valuation == 'dcf')
                            _SectionCard(
                              icon: Icons.tune,
                              title: 'Parâmetros do DCF',
                              subtitle: 'Configurações de fluxo e desconto',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Margem de Segurança
                                  Text(
                                    'MARGEM DE SEGURANÇA',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary(isLight),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBackground(isLight),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            keyboardType: TextInputType.number,
                                            onChanged: controller.setMargem,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary(isLight),
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Ex.: 20',
                                              hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                            ),
                                            controller: _margemController,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(right: 12),
                                          child: Text(
                                            '%',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textMuted(isLight),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Taxa de Desconto (Ke)
                                  Text(
                                    'TAXA DE DESCONTO (Ke)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary(isLight),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBackground(isLight),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            keyboardType: TextInputType.number,
                                            onChanged: controller.setDcfDiscountRate,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary(isLight),
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Ex.: 12',
                                              hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                            ),
                                            controller: _dcfDiscountRateController,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(right: 12),
                                          child: Text(
                                            '%',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textMuted(isLight),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Crescimento de Curto Prazo (g)
                                  Text(
                                    'CRESCIMENTO CURTO PRAZO (g)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary(isLight),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBackground(isLight),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            keyboardType: TextInputType.number,
                                            onChanged: controller.setDcfGrowthRate,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary(isLight),
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Ex.: 8',
                                              hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                            ),
                                            controller: _dcfGrowthRateController,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(right: 12),
                                          child: Text(
                                            '%',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textMuted(isLight),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Crescimento na Perpetuidade (gp)
                                  Text(
                                    'CRESCIMENTO PERPÉTUO (gp)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary(isLight),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBackground(isLight),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            keyboardType: TextInputType.number,
                                            onChanged: controller.setDcfPerpetualGrowth,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary(isLight),
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Ex.: 4',
                                              hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                                            ),
                                            controller: _dcfPerpetualGrowthController,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(right: 12),
                                          child: Text(
                                            '%',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textMuted(isLight),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Anos de Projeção
                                  Text(
                                    'ANOS DE PROJEÇÃO (N)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary(isLight),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBackground(isLight),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        value: controller.dcfProjectionYears,
                                        icon: Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary(isLight)),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary(isLight),
                                        ),
                                        dropdownColor: AppColors.surface(isLight),
                                        onChanged: (int? value) {
                                          if (value != null) {
                                            controller.setDcfProjectionYears(value);
                                          }
                                        },
                                        items: [3, 5, 8, 10, 12, 15]
                                            .map<DropdownMenuItem<int>>((int value) {
                                          return DropdownMenuItem<int>(
                                            value: value,
                                            child: Text('$value anos'),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          // Botão de Execução do Backtest
                          Container(
                            width: double.infinity,
                            height: 54,
                            margin: const EdgeInsets.only(top: 14),
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: (backtestController.isLoading || _isExecuting)
                                  ? null
                                  : () async {
                                      final error = controller.getValidationError();
                                      if (error != null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(error),
                                            backgroundColor: const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }

                                      setState(() {
                                        _isExecuting = true;
                                      });

                                      try {
                                        ValuationMethod method = ValuationMethod.graham;
                                        if (controller.valuation == 'bazin') {
                                          method = ValuationMethod.bazin;
                                        } else if (controller.valuation == 'lynch') {
                                          method = ValuationMethod.peterLynch;
                                        } else if (controller.valuation == 'dcf') {
                                          method = ValuationMethod.dcf;
                                        }

                                        final config = BacktestConfig(
                                          stockTicker: controller.stockTicker,
                                          fiiTicker: controller.fiiTicker,
                                          startDate: controller.startDate!,
                                          endDate: controller.endDate!,
                                          monthlyInvestment: controller.doubleAporte,
                                          valuationMethod: method,
                                          safetyMargin: controller.doubleMargem,
                                          dcfDiscountRate: controller.doubleDcfDiscountRate,
                                          dcfGrowthRate: controller.doubleDcfGrowthRate,
                                          dcfPerpetualGrowth: controller.doubleDcfPerpetualGrowth,
                                          dcfProjectionYears: controller.dcfProjectionYears,
                                          diaCompra: controller.diaCompra,
                                          considerarReinvestimento: controller.considerarReinvestimento,
                                        );

                                        final success = await backtestController.executeBacktest(config);
                                        if (success && context.mounted) {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => const BacktestResultsPage()),
                                          );
                                        } else if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Erro ao executar a simulação. Verifique as credenciais ou internet.'),
                                              backgroundColor: Color(0xFFEF4444),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() {
                                            _isExecuting = false;
                                          });
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: (backtestController.isLoading || _isExecuting)
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_arrow, color: Colors.white, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Executar Simulação',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Menu suspenso de ações rápidas do perfil (Dropdown Overlay)
              if (_dropdownOpen)
                Positioned(
                  top: 96,
                  right: 16,
                  child: Container(
                    width: 210,
                    decoration: BoxDecoration(
                      color: AppColors.surface(isLight),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                      boxShadow: [
                        BoxShadow(
                          color: isLight ? const Color(0x1F0B1E4B) : Colors.black38,
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Identificação do Usuário
                        Padding(
                          padding: const EdgeInsets.only(top: 14, left: 16, right: 16, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(isLight),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                userEmail,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(isLight),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: AppColors.divider(isLight)),
                        
                        // Link: Meu perfil
                        InkWell(
                          onTap: () {
                            setState(() {
                              _dropdownOpen = false;
                            });
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ProfilePage()),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                    color: AppColors.inputBackground(isLight),
                                  ),
                                  child: Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary(isLight)),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Meu perfil',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary(isLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(height: 1, color: AppColors.divider(isLight)),

                        // Link: Histórico
                        InkWell(
                          onTap: () {
                            setState(() {
                              _dropdownOpen = false;
                            });
                            // Carrega o histórico antes de navegar
                            Provider.of<BacktestController>(context, listen: false).fetchHistory();
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => BacktestHistoryPage(homeController: controller)),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                    color: AppColors.inputBackground(isLight),
                                  ),
                                  child: Icon(Icons.history, size: 14, color: AppColors.textSecondary(isLight)),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Histórico',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary(isLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(height: 1, color: AppColors.divider(isLight)),
                        
                        // Switch do Tema Visual (Modo Claro)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8, top: 4, bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(7),
                                  color: AppColors.inputBackground(isLight),
                                ),
                                child: Icon(
                                  isLight ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
                                  size: 14,
                                  color: AppColors.textSecondary(isLight),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(
                                    'Modo claro',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(isLight),
                                    ),
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.8,
                                  child: Switch(
                                    value: isLight,
                                    activeThumbColor: AppColors.primary,
                                    onChanged: (val) async {
                                      await themeController.toggleTheme(user?.uid);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(height: 1, color: AppColors.divider(isLight)),
                          
                          // Opção de Logout
                          InkWell(
                            onTap: () async {
                              setState(() {
                                _dropdownOpen = false;
                              });
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const LoginPage()),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      color: AppColors.danger.withValues(alpha: 0.08),
                                    ),
                                    child: const Icon(Icons.logout, size: 14, color: AppColors.danger),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Sair',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
    );
  }

  /// Constrói o componente autocomplete do formulário
  Widget _buildAutocompleteField({
    required Key key,
    required TextEditingController controller,
    required String placeholder,
    required Function(String) onChange,
    required List<String> popularSuggestions,
    required List<String> allSuggestions,
    required bool showSuggestions,
    required VoidCallback onFocus,
    required bool isLight,
    String? errorText,
  }) {
    final query = controller.text.toUpperCase().trim();
    final searchList = allSuggestions.isNotEmpty ? allSuggestions : popularSuggestions;
    
    final List<String> filtered = query.isEmpty 
        ? popularSuggestions.take(5).toList() 
        : searchList.where((s) => s.startsWith(query)).take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              onFocus();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.inputBackground(isLight),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceBorder(isLight)),
            ),
            child: TextField(
              key: key,
              controller: controller,
              onChanged: (v) {
                onChange(v);
                setState(() {});
              },
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(isLight),
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
        
        // Caixa suspensa de listagem do autocomplete
        if (showSuggestions && filtered.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: isLight 
                  ? Colors.white.withValues(alpha: 0.96) 
                  : const Color(0xDC1A2744),
              border: Border.all(color: AppColors.surfaceBorder(isLight)),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, idx) {
                  final item = filtered[idx];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        onChange(item);
                        setState(() {
                          _showStockSuggestions = false;
                          _showFiiSuggestions = false;
                        });
                        FocusScope.of(context).unfocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(isLight),
                              ),
                            ),
                            Icon(
                              Icons.north_west,
                              size: 12,
                              color: AppColors.textMuted(isLight),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],

        if (errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Card de seção para agrupar inputs
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({required this.icon, required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final isLight = Provider.of<ThemeController>(context).isLightMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(isLight),
        border: Border.all(color: AppColors.surfaceBorder(isLight)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: const Color(0xFF0B1E4B).withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(isLight),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary(isLight),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Campo seletor de data (DatePicker)
class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? selectedDate;
  final Function(DateTime) onSelect;

  const _DatePickerField({required this.label, required this.selectedDate, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isLight = Provider.of<ThemeController>(context).isLightMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(isLight),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: selectedDate ?? DateTime(2023, 1, 1),
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (date != null) onSelect(date);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.inputBackground(isLight),
              border: Border.all(color: AppColors.surfaceBorder(isLight)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              selectedDate != null ? DateFormat('dd/MM/yyyy').format(selectedDate!) : 'Selecionar',
              style: TextStyle(
                fontSize: 12,
                color: selectedDate != null ? AppColors.textPrimary(isLight) : AppColors.textMuted(isLight),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botão seletor das estratégias de valuation
class _ValuationButton extends StatelessWidget {
  final String id;
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _ValuationButton({required this.id, required this.label, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLight = Provider.of<ThemeController>(context).isLightMode;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface(isLight),
          border: Border.all(
            color: selected ? AppColors.primary.withValues(alpha: 0.5) : AppColors.surfaceBorder(isLight),
            width: selected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: selected ? AppColors.primaryLight : AppColors.textPrimary(isLight),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary(isLight)),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
