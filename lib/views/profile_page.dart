import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../presentation/shared/ui_kit.dart';
import '../presentation/theme/fin_space.dart';
import '../presentation/theme/fin_theme.dart';
import '../controllers/profile_controller.dart';
import 'change_password_page.dart';
import 'login_page.dart';

/// Tela de exibição e edição de dados cadastrais do perfil do usuário.
///
/// Transcreve o visual e o comportamento do componente React `MyProfile.tsx`,
/// implementando edição in-line, exclusão de conta e removendo e-mail verificado e 2FA.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileController(),
      child: const _ProfileScreenContent(),
    );
  }
}

class _ProfileScreenContent extends StatefulWidget {
  const _ProfileScreenContent();

  @override
  State<_ProfileScreenContent> createState() => _ProfileScreenContentState();
}

class _ProfileScreenContentState extends State<_ProfileScreenContent> {
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late ProfileController _profileController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _profileController = Provider.of<ProfileController>(
        context,
        listen: false,
      );
      _usernameController = TextEditingController(
        text: _profileController.username,
      );
      _emailController = TextEditingController(text: _profileController.email);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Calcula as iniciais do nome do usuário para exibição no avatar
  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// Salva as edições locais e exibe feedbacks visuais na tela
  void _save(BuildContext context, ProfileController controller) async {
    FocusScope.of(context).unfocus();
    final success = await controller.saveChanges();
    if (context.mounted && !success && controller.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage!),
          backgroundColor: context.fin.negative,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Exibe um diálogo de confirmação antes de excluir a conta definitivamente
  void _confirmDeleteAccount(
    BuildContext context,
    ProfileController controller,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: context.fin.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.fin.border),
            ),
            title: Text(
              'Excluir Conta',
              style: context.finType.titleSm.copyWith(
                color: context.fin.textPrimary,
              ),
            ),
            content: Text(
              'Esta ação é definitiva e removerá todos os seus dados de simulações. Deseja mesmo prosseguir?',
              style: context.finType.bodyMd.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: context.finType.bodyMd.copyWith(
                    color: context.fin.textTertiary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context); // Fecha diálogo
                  final error = await controller.deleteAccount();
                  if (context.mounted) {
                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(error),
                          backgroundColor: context.fin.negative,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sua conta foi excluída com sucesso.'),
                          backgroundColor: context.fin.brand,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.fin.negative,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Excluir',
                  style: context.finType.bodyMd.copyWith(
                    color: context.fin.textOnBrand,
                    fontWeight: FontWeight.bold,
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
    final controller = Provider.of<ProfileController>(context);

    // Sincroniza estados do Provider com os text controllers locais
    if (_usernameController.text != controller.username) {
      _usernameController.value = TextEditingValue(
        text: controller.username,
        selection: TextSelection.collapsed(offset: controller.username.length),
      );
    }

    if (_emailController.text != controller.email) {
      _emailController.value = TextEditingValue(
        text: controller.email,
        selection: TextSelection.collapsed(offset: controller.email.length),
      );
    }

    final initials = _getInitials(controller.username);

    return Scaffold(
      // `ScreenBackground` no lugar do gradiente com os dois círculos
      // reconstruídos aqui: eram cópia literal do componente compartilhado, e
      // qualquer ajuste no fundo precisava ser feito nos dois lugares.
      body: ScreenBackground(
        child: Column(
          children: [
            AppHeader(
              title: 'Meu Perfil',
              subtitle: 'Informações da conta',
              leading: GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.fin.surfaceSunken,
                        border: Border.all(color: context.fin.border),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: context.fin.textSecondary,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Body rolável
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 24,
                  left: 16,
                  right: 16,
                  bottom: 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar Section
                    _AvatarSection(controller: controller, initials: initials),
                    const SizedBox(height: 24),

                    // Dados pessoais Card (Nome de usuário e E-mail in-line)
                    _PersonalDataCard(
                      controller: controller,
                      usernameController: _usernameController,
                      emailController: _emailController,
                    ),
                    const SizedBox(height: 12),

                    // Save changes button (apenas visível ao editar)
                    _SaveButton(controller: controller, onSave: _save),

                    // Success Toast temporário
                    _SuccessToast(controller: controller),

                    // Segurança Card (Trocar Senha, sem 2FA)
                    _SecurityCard(controller: controller),
                    const SizedBox(height: 12),

                    // Sessão Atual Card
                    _SessionCard(controller: controller),
                    const SizedBox(height: 16),

                    // Excluir conta Button
                    _DeleteAccountButton(
                      controller: controller,
                      onConfirm: _confirmDeleteAccount,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  final ProfileController controller;

  /// Iniciais exibidas no avatar, derivadas do nome.
  final String initials;

  const _AvatarSection({required this.controller, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // As paradas são tokens já tematizados: o ternário por `isLight`
                // que havia aqui escolhia entre duas listas que variam
                // sozinhas, então era redundante.
                gradient: LinearGradient(
                  colors: [
                    context.fin.brandSurface,
                    context.fin.positiveSurface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: context.fin.brand.withValues(alpha: 0.5),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.fin.shadow,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initials,
                  style: context.finType.displayLg.copyWith(
                    color: context.fin.positive,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ),
            // Câmera Edit button
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'A alteração de foto de perfil estará disponível em breve!',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: context.fin.brandGradient,
                    border: Border.all(color: context.fin.canvas, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: context.fin.brand.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: context.fin.textOnBrand,
                    size: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          controller.username,
          style: context.finType.titleLg.copyWith(
            color: context.fin.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          controller.email,
          style: context.finType.bodySm.copyWith(
            color: context.fin.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        // Member badge
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          decoration: BoxDecoration(
            color: context.fin.brand.withValues(alpha: 0.1),
            border: Border.all(
              color: context.fin.brand.withValues(alpha: 0.25),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.fin.positive,
                ),
              ),
              const SizedBox(width: 6),
              // `Expanded`: o rotulo em caixa alta nao encolhe, e sob
              // escala 2,0x a linha do cabecalho estourava em 320 dp.
              Expanded(
                child: Text(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  'Membro ativo',
                  style: context.finType.caption.copyWith(
                    color: context.fin.positive,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonalDataCard extends StatelessWidget {
  final ProfileController controller;

  /// Controladores de texto locais, mantidos pelo State da tela.
  final TextEditingController usernameController;
  final TextEditingController emailController;

  const _PersonalDataCard({
    required this.controller,
    required this.usernameController,
    required this.emailController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.fin.surface,
        border: Border.all(color: context.fin.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.fin.shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header do cartão
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.person_outline, color: context.fin.brand, size: 13),
                const SizedBox(width: 8),
                // `Expanded`: o rotulo em caixa alta nao encolhe, e sob
                // escala 2,0x a linha do cabecalho estourava em 320 dp.
                Expanded(
                  child: Text(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    'DADOS PESSOAIS',
                    style: context.finType.caption.copyWith(
                      color: context.fin.textSecondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: context.fin.divider, height: 1),

          // Nome de usuário row
          Padding(
            padding: const EdgeInsets.all(16),
            child: controller.editingName
                ? Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.fin.surfaceSunken,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: context.fin.brand.withValues(alpha: 0.5),
                            ),
                          ),
                          child: TextField(
                            controller: usernameController,
                            onChanged: controller.setUsername,
                            autofocus: true,
                            style: context.finType.bodyMd.copyWith(
                              color: context.fin.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => controller.setEditingName(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: context.fin.surfaceSunken,
                            border: Border.all(color: context.fin.border),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '✕',
                            style: context.finType.bodySm.copyWith(
                              color: context.fin.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // `Expanded`: sem ele a coluna impõe a largura
                      // intrínseca e a linha estoura em 320 dp já em 1,3x.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NOME DE USUÁRIO',
                              style: context.finType.caption.copyWith(
                                color: context.fin.textSecondary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              controller.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.finType.bodyMd.copyWith(
                                color: context.fin.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => controller.setEditingName(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: context.fin.brand.withValues(alpha: 0.1),
                            border: Border.all(
                              color: context.fin.brand.withValues(alpha: 0.25),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Editar',
                            style: context.finType.caption.copyWith(
                              color: context.fin.positive,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Divider(color: context.fin.divider, height: 1),

          // Email row (sem selo verificado)
          Padding(
            padding: const EdgeInsets.all(16),
            child: controller.editingEmail
                ? Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.fin.surfaceSunken,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: context.fin.brand.withValues(alpha: 0.5),
                            ),
                          ),
                          child: TextField(
                            controller: emailController,
                            onChanged: controller.setEmail,
                            autofocus: true,
                            style: context.finType.bodyMd.copyWith(
                              color: context.fin.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => controller.setEditingEmail(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: context.fin.surfaceSunken,
                            border: Border.all(color: context.fin.border),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '✕',
                            style: context.finType.bodySm.copyWith(
                              color: context.fin.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // `Expanded`: sem ele a coluna impõe a largura
                      // intrínseca e a linha estoura em 320 dp já em 1,3x.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'E-MAIL',
                              style: context.finType.caption.copyWith(
                                color: context.fin.textSecondary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              controller.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.finType.bodyMd.copyWith(
                                color: context.fin.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => controller.setEditingEmail(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: context.fin.brand.withValues(alpha: 0.1),
                            border: Border.all(
                              color: context.fin.brand.withValues(alpha: 0.25),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Editar',
                            style: context.finType.caption.copyWith(
                              color: context.fin.positive,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  final ProfileController controller;

  const _SecurityCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.fin.surface,
        border: Border.all(color: context.fin.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.fin.shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.security_outlined,
                  color: context.fin.brand,
                  size: 13,
                ),
                const SizedBox(width: 8),
                Text(
                  'SEGURANÇA',
                  style: context.finType.caption.copyWith(
                    color: context.fin.textSecondary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: context.fin.divider, height: 1),

          // Trocar senha row
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChangePasswordPage(),
                  ),
                );
              },
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: context.fin.brand.withValues(alpha: 0.12),
                        border: Border.all(
                          color: context.fin.brand.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        Icons.lock_outline,
                        color: context.fin.brand,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trocar senha',
                            style: context.finType.bodyMd.copyWith(
                              color: context.fin.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Altere sua senha de acesso',
                            style: context.finType.caption.copyWith(
                              color: context.fin.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_outlined,
                      size: 12,
                      color: context.fin.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ProfileController controller;

  const _SessionCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.fin.surface,
        border: Border.all(color: context.fin.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.fin.shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_outlined,
                  color: context.fin.brand,
                  size: 13,
                ),
                const SizedBox(width: 8),
                // `Expanded`: o rotulo em caixa alta nao encolhe, e sob
                // escala 2,0x a linha do cabecalho estourava em 320 dp.
                Expanded(
                  child: Text(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    'SESSÃO ATUAL',
                    style: context.finType.caption.copyWith(
                      color: context.fin.textSecondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: context.fin.divider, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: context.fin.surfaceSunken,
                  ),
                  child: Icon(
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? Icons.phone_iphone
                        : Icons.phone_android,
                    color: context.fin.textSecondary,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Theme.of(context).platform == TargetPlatform.iOS
                            ? 'iPhone · iOS'
                            : 'Smartphone · Android',
                        style: context.finType.bodySm.copyWith(
                          color: context.fin.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'São Paulo, BR · Agora',
                        style: context.finType.caption.copyWith(
                          color: context.fin.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.fin.positive,
                    boxShadow: [
                      BoxShadow(color: context.fin.positive, blurRadius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountButton extends StatelessWidget {
  final ProfileController controller;

  /// Confirmação de exclusão, que mora no State por abrir diálogo.
  final void Function(BuildContext, ProfileController) onConfirm;

  const _DeleteAccountButton({
    required this.controller,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => onConfirm(context, controller),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: context.fin.negative.withValues(alpha: 0.18)),
        backgroundColor: context.fin.negative.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.delete_outline, color: context.fin.negative, size: 14),
      label: Text(
        'Excluir conta',
        style: context.finType.bodySm.copyWith(
          color: context.fin.negative,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final ProfileController controller;

  /// Persistência, que mora no State por depender dos campos de texto locais.
  final void Function(BuildContext, ProfileController) onSave;

  const _SaveButton({required this.controller, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (!(controller.editingName || controller.editingEmail)) {
      return const SizedBox.shrink();
    } {
        
      }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: context.fin.brandGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: context.fin.brand.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: controller.isLoading
                ? null
                : () => onSave(context, controller),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: controller.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: context.fin.textOnBrand,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Salvar alterações',
                    style: context.finType.bodyMd.copyWith(
                      color: context.fin.textOnBrand,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const Gap.md(),
      ],
    );
  }
}

class _SuccessToast extends StatelessWidget {
  final ProfileController controller;

  const _SuccessToast({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!(controller.savedSuccess)) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: context.fin.brand.withValues(alpha: 0.12),
            border: Border.all(color: context.fin.brand.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: context.fin.positive,
                size: 16,
              ),
              const SizedBox(width: 10),
              Text(
                'Informações salvas com sucesso!',
                style: context.finType.bodySm.copyWith(
                  color: context.fin.positive,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Gap.md(),
      ],
    );
  }
}
