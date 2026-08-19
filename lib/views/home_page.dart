import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/home_controller.dart';
import '../controllers/theme_controller.dart';
import '../utils/app_colors.dart';
import 'login_page.dart';
import 'profile_page.dart';

/// Tela inicial da aplicação.
///
/// FASE 0 — shell de transição. O formulário do escopo anterior (uma ação ×
/// um FII) foi removido junto com o motor de backtest correspondente. Esta
/// tela preserva a identidade visual, a sessão e a navegação, e confirma a
/// conectividade com a brapi enquanto o novo domínio é construído.
///
/// Será substituída na Fase 4 pela gestão de dupla carteira.
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

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<HomeController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: GestureDetector(
        onTap: () => setState(() => _dropdownOpen = false),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient(isLight)),
          child: Stack(
            children: [
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
                  _buildHeader(isLight),
                  Expanded(child: _buildBody(controller, isLight)),
                ],
              ),
              if (_dropdownOpen) _buildDropdown(themeController, user, isLight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isLight) {
    return ClipRRect(
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
                        'EM RECONSTRUÇÃO',
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
              GestureDetector(
                onTap: () => setState(() => _dropdownOpen = !_dropdownOpen),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: _dropdownOpen ? 0.25 : 0.15),
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
    );
  }

  Widget _buildBody(HomeController controller, bool isLight) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface(isLight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder(isLight)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.construction, color: AppColors.primary, size: 32),
                const SizedBox(height: 16),
                Text(
                  'Novo motor em construção',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(isLight),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'O simulador anterior foi descontinuado. A nova ferramenta de '
                  'dupla carteira com valuation por DCF e CAPM está sendo '
                  'desenvolvida.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary(isLight),
                  ),
                ),
                const SizedBox(height: 24),
                Divider(color: AppColors.divider(isLight)),
                const SizedBox(height: 16),
                _buildConnectionStatus(controller, isLight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Verificação viva de conectividade com a brapi — confirma que autenticação,
  /// variáveis de ambiente e camada de rede seguem operantes após a demolição.
  Widget _buildConnectionStatus(HomeController controller, bool isLight) {
    if (controller.isLoadingTickers) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Text(
            'Conectando à brapi...',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(isLight)),
          ),
        ],
      );
    }

    final bool ok = controller.loadError == null && controller.availableStocks.isNotEmpty;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 15,
              color: ok ? AppColors.primary : AppColors.danger,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                ok
                    ? 'brapi conectada · ${controller.availableStocks.length} ações disponíveis'
                    : (controller.loadError ?? 'Falha na conexão'),
                style: TextStyle(
                  fontSize: 12,
                  color: ok ? AppColors.textSecondary(isLight) : AppColors.danger,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: controller.loadTickers,
          icon: const Icon(Icons.refresh, size: 15),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          label: const Text('Testar novamente', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildDropdown(ThemeController themeController, User? user, bool isLight) {
    return Positioned(
      top: 96,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 210,
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xFF13224E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceBorder(isLight)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dropdownItem(
                icon: Icons.person_outline,
                label: 'Meu perfil',
                isLight: isLight,
                onTap: () {
                  setState(() => _dropdownOpen = false);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
              ),
              Divider(height: 1, color: AppColors.divider(isLight)),
              _dropdownItem(
                icon: isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                label: isLight ? 'Modo escuro' : 'Modo claro',
                isLight: isLight,
                onTap: () async {
                  await themeController.toggleTheme(user?.uid);
                },
              ),
              Divider(height: 1, color: AppColors.divider(isLight)),
              _dropdownItem(
                icon: Icons.logout,
                label: 'Sair',
                isLight: isLight,
                danger: true,
                onTap: () async {
                  setState(() => _dropdownOpen = false);
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownItem({
    required IconData icon,
    required String label,
    required bool isLight,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.textPrimary(isLight);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ),
    );
  }
}
