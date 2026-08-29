import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/audit_bus.dart';
import '../../audit/audit_routes.dart';
import '../../utils/app_colors.dart';
import '../../views/login_page.dart';
import '../../views/profile_page.dart';
import '../audit/logs_page.dart';
import '../backtest/backtest_page.dart';
import '../goals/goal_page.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../study/study_page.dart';

/// Casca principal do aplicativo, com as três frentes de trabalho.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _menuOpen = false;

  static const _tabs = [
    (icon: Icons.dashboard_outlined, label: 'Carteiras'),
    (icon: Icons.flag_outlined, label: 'Meta'),
    (icon: Icons.insights_outlined, label: 'Análise'),
  ];

  @override
  Widget build(BuildContext context) {
    final isLight = ref.watch(isLightModeProvider);

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(isLight),
                  Expanded(
                    child: IndexedStack(
                      index: _index,
                      children: const [
                        StudyPage(),
                        GoalPage(),
                        BacktestPage(),
                      ],
                    ),
                  ),
                ],
              ),
              if (_menuOpen) _buildMenu(isLight),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildNavBar(isLight),
    );
  }

  /// Abre o painel de auditoria.
  ///
  /// No navegador vai para uma **guia nova**, que é o ponto do requisito: o
  /// orientador acompanha a apuração numa tela enquanto o sistema é operado na
  /// outra. Nas plataformas sem segunda janela o painel é empilhado sobre a
  /// própria aplicação, pela rota registrada em `MaterialApp.routes`.
  void _openAuditPanel() {
    if (AuditRoutes.openInNewWindow()) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogsPage()),
    );
  }

  Widget _buildHeader(bool isLight) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: AppColors.backgroundStart(isLight).withValues(alpha: 0.6),
            border: Border(
              bottom: BorderSide(color: AppColors.surfaceBorder(isLight)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: AppColors.brandGradient,
                    ),
                    child:
                        const Icon(Icons.show_chart, color: Colors.white, size: 17),
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
                          height: 1.1,
                          color: AppColors.textPrimary(isLight),
                        ),
                      ),
                      Text(
                        _tabs[_index].label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.5,
                          color: AppColors.textSecondary(isLight),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (auditEnabled) ...[
                    _AuditButton(isLight: isLight, onTap: _openAuditPanel),
                    const SizedBox(width: 10),
                  ],
                  GestureDetector(
                    onTap: () => setState(() => _menuOpen = !_menuOpen),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.15),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.person_outline,
                          color: AppColors.primary, size: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar(bool isLight) {
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF0D1E45),
        border: Border(top: BorderSide(color: AppColors.surfaceBorder(isLight))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() {
                    _index = i;
                    _menuOpen = false;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _tabs[i].icon,
                          size: 20,
                          color: i == _index
                              ? AppColors.primary
                              : AppColors.textMuted(isLight),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _tabs[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                i == _index ? FontWeight.bold : FontWeight.normal,
                            color: i == _index
                                ? AppColors.primary
                                : AppColors.textMuted(isLight),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(bool isLight) {
    return Positioned(
      top: 62,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          // Largura ditada pelo item mais longo ('Abrir Painel de Logs de
          // Cálculo'): com 208 o texto media 213 px contra 178 disponíveis e
          // o Row estourava em 35 px. O `Expanded` abaixo é a rede de
          // segurança para métricas de fonte diferentes em outra plataforma.
          width: 256,
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
              _menuItem(
                icon: Icons.person_outline,
                label: 'Meu perfil',
                isLight: isLight,
                onTap: () {
                  setState(() => _menuOpen = false);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
              ),
              Divider(height: 1, color: AppColors.divider(isLight)),
              _menuItem(
                icon: isLight
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                label: isLight ? 'Modo escuro' : 'Modo claro',
                isLight: isLight,
                onTap: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  await ref
                      .read(themeControllerProvider)
                      .toggleTheme(user?.uid);
                  ref.read(isLightModeProvider.notifier).state =
                      ref.read(themeControllerProvider).isLightMode;
                },
              ),
              if (auditEnabled) ...[
                Divider(height: 1, color: AppColors.divider(isLight)),
                _menuItem(
                  icon: Icons.terminal,
                  label: 'Abrir Painel de Logs de Cálculo',
                  isLight: isLight,
                  onTap: () {
                    setState(() => _menuOpen = false);
                    _openAuditPanel();
                  },
                ),
              ],
              Divider(height: 1, color: AppColors.divider(isLight)),
              _menuItem(
                icon: Icons.logout,
                label: 'Sair',
                isLight: isLight,
                danger: true,
                onTap: () async {
                  setState(() => _menuOpen = false);
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

  Widget _menuItem({
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
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Atalho para a janela paralela de auditoria.
///
/// Só aparece com a auditoria ligada — em depuração, por padrão. Não é um
/// recurso do produto: é o instrumento de demonstração da apuração, e ficaria
/// deslocado numa build entregue a um usuário final.
class _AuditButton extends StatelessWidget {
  const _AuditButton({required this.isLight, required this.onTap});

  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Abrir Painel de Logs de Cálculo',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppColors.warning.withValues(alpha: 0.14),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.terminal,
                size: 14,
                color: isLight ? AppColors.warning : AppColors.warningDark,
              ),
              const SizedBox(width: 6),
              Text(
                'LOGS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: isLight ? AppColors.warning : AppColors.warningDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
