import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/fin_space.dart';
import '../../audit/audit_bus.dart';
import '../../audit/audit_routes.dart';
import '../../views/login_page.dart';
import '../../views/profile_page.dart';
import '../audit/logs_page.dart';
import '../backtest/backtest_page.dart';
import '../goals/goal_page.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../theme/fin_theme.dart';
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
                      children: const [StudyPage(), GoalPage(), BacktestPage()],
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
          padding: const EdgeInsets.fromLTRB(
            FinSpace.lg,
            FinSpace.md,
            FinSpace.lg,
            FinSpace.md,
          ),
          decoration: BoxDecoration(
            color: context.fin.canvas.withValues(alpha: 0.6),
            border: Border(bottom: BorderSide(color: context.fin.border)),
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
                      gradient: context.fin.brandGradient,
                    ),
                    child: Icon(
                      Icons.show_chart,
                      // Sobre o preenchimento de marca, e este o token que
                      // garante leitura nos dois temas.
                      color: context.fin.textOnBrand,
                      size: 17,
                    ),
                  ),
                  const Gap.sm(axis: Axis.horizontal),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Equisim',
                        style: context.finType.bodyMd.copyWith(
                          color: context.fin.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _tabs[_index].label.toUpperCase(),
                        style: context.finType.caption.copyWith(
                          color: context.fin.textSecondary,
                          letterSpacing: 0.5,
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
                    const Gap.sm(axis: Axis.horizontal),
                  ],
                  GestureDetector(
                    onTap: () => setState(() => _menuOpen = !_menuOpen),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.fin.brand.withValues(alpha: 0.15),
                        border: Border.all(
                          color: context.fin.brand.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: context.fin.brand,
                        size: 16,
                      ),
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
        color: context.fin.surfaceRaised,
        border: Border(top: BorderSide(color: context.fin.border)),
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
                    padding: const EdgeInsets.symmetric(vertical: FinSpace.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _tabs[i].icon,
                          size: 20,
                          color: i == _index
                              ? context.fin.brand
                              : context.fin.textTertiary,
                        ),
                        const Gap.xs(),
                        Text(
                          _tabs[i].label,
                          style: context.finType.caption.copyWith(
                            color: i == _index
                                ? context.fin.brand
                                : context.fin.textTertiary,
                            fontWeight: i == _index
                                ? FontWeight.bold
                                : FontWeight.normal,
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
            color: context.fin.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.fin.border),
            boxShadow: [
              BoxShadow(
                color: context.fin.shadow,
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
              Divider(height: 1, color: context.fin.divider),
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
                  ref.read(isLightModeProvider.notifier).definir(ref
                      .read(themeControllerProvider)
                      .isLightMode);
                },
              ),
              if (auditEnabled) ...[
                Divider(height: 1, color: context.fin.divider),
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
              Divider(height: 1, color: context.fin.divider),
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
    final color = danger ? context.fin.negative : context.fin.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FinSpace.md,
          vertical: FinSpace.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const Gap.sm(axis: Axis.horizontal),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.finType.bodySm.copyWith(color: color),
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
          padding: const EdgeInsets.symmetric(
            horizontal: FinSpace.sm,
            vertical: FinSpace.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: context.fin.caution.withValues(alpha: 0.14),
            border: Border.all(
              color: context.fin.caution.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.terminal,
                size: 14,
                color: isLight ? context.fin.caution : context.fin.caution,
              ),
              const Gap.xs(axis: Axis.horizontal),
              Text(
                'LOGS',
                style: context.finType.caption.copyWith(
                  color: isLight ? context.fin.caution : context.fin.caution,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
