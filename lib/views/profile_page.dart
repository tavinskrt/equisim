import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../utils/app_colors.dart';
import '../controllers/theme_controller.dart';
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
      _profileController = Provider.of<ProfileController>(context, listen: false);
      _usernameController = TextEditingController(text: _profileController.username);
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
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Exibe um diálogo de confirmação antes de excluir a conta definitivamente
  void _confirmDeleteAccount(BuildContext context, ProfileController controller) {
    final isLight = Provider.of<ThemeController>(context, listen: false).isLightMode;

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
              'Excluir Conta',
              style: TextStyle(color: AppColors.textPrimary(isLight), fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Esta ação é definitiva e removerá todos os seus dados de simulações. Deseja mesmo prosseguir?',
              style: TextStyle(color: AppColors.textSecondary(isLight), fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: isLight ? AppColors.textSecondary(true) : Colors.white38),
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
                          backgroundColor: AppColors.danger,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sua conta foi excluída com sucesso.'),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (route) => false,
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Excluir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

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
      body: Container(
        width: double.infinity,
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
                // Header (fiel ao React)
                ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.only(top: 52, left: 16, right: 20, bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundStart(isLight).withValues(alpha: 0.6),
                        border: Border(bottom: BorderSide(color: AppColors.surfaceBorder(isLight))),
                      ),
                      child: Row(
                        children: [
                          // Botão voltar redondo
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.06),
                                border: Border.all(color: isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Icon(Icons.arrow_back_ios_new, color: isLight ? AppColors.textPrimary(true) : Colors.white60, size: 14),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Meu Perfil',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(isLight),
                                  height: 1.2,
                                ),
                              ),
                              Text(
                                'INFORMAÇÕES DA CONTA',
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
                    ),
                  ),
                ),

                // Body rolável
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Avatar Section
                        Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: isLight
                                        ? const LinearGradient(
                                            colors: [Color(0xFFE6F7F3), Color(0xFFC2F0E5)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : const LinearGradient(
                                            colors: [Color(0xFF0B3D6B), Color(0xFF0D3D2F)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.5),
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isLight ? const Color(0xFF0B1E4B).withValues(alpha: 0.08) : Colors.black38,
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: isLight ? AppColors.primary : const Color(0xFF00CC8F),
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
                                          content: Text('A alteração de foto de perfil estará disponível em breve!'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: AppColors.brandGradient,
                                        border: Border.all(color: AppColors.backgroundStart(isLight), width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.4),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              controller.username,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(isLight),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              controller.email,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(isLight),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Member badge
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
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
                                      color: isLight ? AppColors.primary : const Color(0xFF00CC8F),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Membro ativo',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isLight ? AppColors.primary : const Color(0xFF00CC8F),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Dados pessoais Card (Nome de usuário e E-mail in-line)
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface(isLight),
                            border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isLight
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF0B1E4B).withValues(alpha: 0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Header do cartão
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person_outline, color: AppColors.primary, size: 13),
                                    const SizedBox(width: 8),
                                    Text(
                                      'DADOS PESSOAIS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(color: AppColors.divider(isLight), height: 1),

                              // Nome de usuário row
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: controller.editingName
                                    ? Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.inputBackground(isLight),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                                              ),
                                              child: TextField(
                                                controller: _usernameController,
                                                onChanged: controller.setUsername,
                                                autofocus: true,
                                                style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14, fontWeight: FontWeight.bold),
                                                decoration: const InputDecoration(
                                                  border: InputBorder.none,
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => controller.setEditingName(false),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: AppColors.inputBackground(isLight),
                                                border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              child: Text('✕', style: TextStyle(color: AppColors.textSecondary(isLight), fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'NOME DE USUÁRIO',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textSecondary(isLight),
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                controller.username,
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                                              ),
                                            ],
                                          ),
                                          GestureDetector(
                                            onTap: () => controller.setEditingName(true),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.1),
                                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'Editar',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              Divider(color: AppColors.divider(isLight), height: 1),

                              // Email row (sem selo verificado)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: controller.editingEmail
                                    ? Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.inputBackground(isLight),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                                              ),
                                              child: TextField(
                                                controller: _emailController,
                                                onChanged: controller.setEmail,
                                                autofocus: true,
                                                style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14, fontWeight: FontWeight.bold),
                                                decoration: const InputDecoration(
                                                  border: InputBorder.none,
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => controller.setEditingEmail(false),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: AppColors.inputBackground(isLight),
                                                border: Border.all(color: AppColors.surfaceBorder(isLight)),
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              child: Text('✕', style: TextStyle(color: AppColors.textSecondary(isLight), fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'E-MAIL',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textSecondary(isLight),
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                controller.email,
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                                              ),
                                            ],
                                          ),
                                          GestureDetector(
                                            onTap: () => controller.setEditingEmail(true),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.1),
                                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'Editar',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Save changes button (apenas visível ao editar)
                        if (controller.editingName || controller.editingEmail) ...[
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                )
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: controller.isLoading ? null : () => _save(context, controller),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: controller.isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text(
                                      'Salvar alterações',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Success Toast temporário
                        if (controller.savedSuccess) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, color: isLight ? AppColors.primary : const Color(0xFF00CC8F), size: 16),
                                const SizedBox(width: 10),
                                Text(
                                  'Informações salvas com sucesso!',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isLight ? AppColors.primary : const Color(0xFF00CC8F)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Segurança Card (Trocar Senha, sem 2FA)
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface(isLight),
                            border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isLight
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF0B1E4B).withValues(alpha: 0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.security_outlined, color: AppColors.primary, size: 13),
                                    const SizedBox(width: 8),
                                    Text(
                                      'SEGURANÇA',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(color: AppColors.divider(isLight), height: 1),
                              
                              // Trocar senha row
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const ChangePasswordPage()),
                                    );
                                  },
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                                          ),
                                          child: const Icon(Icons.lock_outline, color: AppColors.primary, size: 15),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Trocar senha',
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Altere sua senha de acesso',
                                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary(isLight)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.arrow_forward_ios_outlined, size: 12, color: AppColors.textSecondary(isLight)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Sessão Atual Card
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface(isLight),
                            border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isLight
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF0B1E4B).withValues(alpha: 0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_outlined, color: AppColors.primary, size: 13),
                                    const SizedBox(width: 8),
                                    Text(
                                      'SESSÃO ATUAL',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(color: AppColors.divider(isLight), height: 1),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: AppColors.inputBackground(isLight),
                                      ),
                                      child: Icon(
                                        Theme.of(context).platform == TargetPlatform.iOS
                                            ? Icons.phone_iphone
                                            : Icons.phone_android,
                                        color: AppColors.textSecondary(isLight),
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
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary(isLight)),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'São Paulo, BR · Agora',
                                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(isLight)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isLight ? AppColors.primary : const Color(0xFF00CC8F),
                                        boxShadow: [
                                          BoxShadow(
                                            color: isLight ? AppColors.primary : const Color(0xFF00CC8F),
                                            blurRadius: 6,
                                          )
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Excluir conta Button
                        OutlinedButton.icon(
                          onPressed: () => _confirmDeleteAccount(context, controller),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0x2EEF4444)),
                            backgroundColor: const Color(0x0FEF4444),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 14),
                          label: const Text(
                            'Excluir conta',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.danger),
                          ),
                        ),
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
}
