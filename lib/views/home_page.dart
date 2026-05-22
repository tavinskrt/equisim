import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/home_controller.dart';
import '../controllers/theme_controller.dart';
import '../utils/app_colors.dart';
import 'login_page.dart';

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
  final List<TextEditingController> _acoesControllers = [];
  final List<TextEditingController> _fiisControllers = [];
  late HomeController _homeController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _homeController = Provider.of<HomeController>(context, listen: false);
      _aporteController = TextEditingController(text: _homeController.aporte);
      _margemController = TextEditingController(text: _homeController.margem);
      
      for (var ticker in _homeController.acoes) {
        _acoesControllers.add(TextEditingController(text: ticker));
      }
      for (var ticker in _homeController.fiis) {
        _fiisControllers.add(TextEditingController(text: ticker));
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _aporteController.dispose();
    _margemController.dispose();
    for (var c in _acoesControllers) {
      c.dispose();
    }
    for (var c in _fiisControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<HomeController>(context);

    // Sincronizar tamanho das listas de controllers com o estado do HomeController
    while (_acoesControllers.length < controller.acoes.length) {
      _acoesControllers.add(TextEditingController(text: controller.acoes[_acoesControllers.length]));
    }
    while (_acoesControllers.length > controller.acoes.length) {
      _acoesControllers.removeLast().dispose();
    }
    while (_fiisControllers.length < controller.fiis.length) {
      _fiisControllers.add(TextEditingController(text: controller.fiis[_fiisControllers.length]));
    }
    while (_fiisControllers.length > controller.fiis.length) {
      _fiisControllers.removeLast().dispose();
    }

    // Sincronizar o conteúdo digitado e formatado
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

    for (int i = 0; i < controller.acoes.length; i++) {
      if (_acoesControllers[i].text != controller.acoes[i]) {
        _acoesControllers[i].value = TextEditingValue(
          text: controller.acoes[i],
          selection: TextSelection.collapsed(offset: controller.acoes[i].length),
        );
      }
    }

    for (int i = 0; i < controller.fiis.length; i++) {
      if (_fiisControllers[i].text != controller.fiis[i]) {
        _fiisControllers[i].value = TextEditingValue(
          text: controller.fiis[i],
          selection: TextSelection.collapsed(offset: controller.fiis[i].length),
        );
      }
    }

    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'usuario@email.com';

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          if (_dropdownOpen) {
            setState(() {
              _dropdownOpen = false;
            });
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(isLight),
          ),
          child: Stack(
            children: [
              /// Decorações geométricas de fundo
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

              /// Conteúdo Principal
              Column(
                children: [
                  /// Header Fixado
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
                            
                            // Avatar
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

                  /// Corpo expansível
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          /// 1. ATIVOS
                          _SectionCard(
                            icon: Icons.ssid_chart,
                            title: 'Ativos',
                            subtitle: 'Tickers para comparação',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AÇÕES',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary(isLight),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...List.generate(controller.acoes.length, (index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: _TickerInput(
                                      controller: _acoesControllers[index],
                                      placeholder: 'Ex.: PETR4',
                                      onChange: (v) => controller.updateAcao(index, v),
                                      onRemove: controller.acoes.length > 1 ? () {
                                        _acoesControllers.removeAt(index).dispose();
                                        controller.removeAcao(index);
                                      } : null,
                                    ),
                                  );
                                }),
                                if (controller.acoes.length < 6)
                                  _AddButton(label: 'Adicionar ação', onClick: controller.addAcao),
                                
                                Container(
                                  height: 1,
                                  color: AppColors.divider(isLight),
                                  margin: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                
                                Text(
                                  'FUNDOS IMOBILIÁRIOS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary(isLight),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...List.generate(controller.fiis.length, (index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: _TickerInput(
                                      controller: _fiisControllers[index],
                                      placeholder: 'Ex.: HGLG11',
                                      onChange: (v) => controller.updateFii(index, v),
                                      onRemove: controller.fiis.length > 1 ? () {
                                        _fiisControllers.removeAt(index).dispose();
                                        controller.removeFii(index);
                                      } : null,
                                    ),
                                  );
                                }),
                                if (controller.fiis.length < 6)
                                  _AddButton(label: 'Adicionar FII', onClick: controller.addFii),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          /// 2. PERÍODO
                          _SectionCard(
                            icon: Icons.calendar_month_outlined,
                            title: 'Período',
                            subtitle: 'Janela histórica de análise',
                            child: Row(
                              children: [
                                Expanded(
                                  child: _DatePickerField(
                                    label: 'Data inicial',
                                    selectedDate: controller.startDate,
                                    onSelect: (date) => controller.setStartDate(date),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _DatePickerField(
                                    label: 'Data final',
                                    selectedDate: controller.endDate,
                                    onSelect: (date) => controller.setEndDate(date),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          /// 3. APORTE
                          _SectionCard(
                            icon: Icons.attach_money,
                            title: 'Aporte mensal',
                            subtitle: 'Valor investido por mês',
                            child: Container(
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
                          ),
                          const SizedBox(height: 10),

                          /// 4. MÉTODO DE VALUATION
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
                                  id: 'dcf', label: 'DCF Simplificado', desc: 'Fluxo de Caixa',
                                  selected: controller.valuation == 'dcf',
                                  onTap: () => controller.setValuation('dcf'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          /// 5. PARÂMETROS
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
                                        'O ativo será considerado comprável somente se seu preço atual estiver pelo menos este percentual abaixo do valor intrínseco calculado.',
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
                          
                          /// EXECUTAR
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
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Ação de Executar Simulação
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                              label: const Text(
                                'Executar Simulação',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Dropdown Menu Overlay
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
                        // User Info
                        Padding(
                          padding: const EdgeInsets.only(top: 14, left: 16, right: 16, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Usuário',
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
                        // Meu perfil
                        InkWell(
                          onTap: () {
                            setState(() {
                              _dropdownOpen = false;
                            });
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
                        // Modo claro
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
                        // Sair
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
}

/// Componentes Auxiliares
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
              Column(
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
                      fontSize: 11,
                      color: AppColors.textSecondary(isLight),
                    ),
                  ),
                ],
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

class _TickerInput extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final Function(String) onChange;
  final VoidCallback? onRemove;

  const _TickerInput({required this.controller, required this.placeholder, required this.onChange, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isLight = Provider.of<ThemeController>(context).isLightMode;

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.inputBackground(isLight),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceBorder(isLight)),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChange,
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
        if (onRemove != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.close, color: AppColors.danger, size: 16),
            ),
          ),
        ],
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onClick;

  const _AddButton({required this.label, required this.onClick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClick,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: AppColors.primary, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
              initialDate: selectedDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
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
