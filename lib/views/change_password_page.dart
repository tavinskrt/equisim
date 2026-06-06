import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../utils/app_colors.dart';
import '../controllers/theme_controller.dart';
import '../controllers/change_password_controller.dart';

/// Tela responsável pela alteração de senha de acesso da conta do usuário.
/// 
/// Transcreve fielmente a interface e lógica de `ChangePassword.tsx`, incluindo
/// medidor de força da senha, requisitos dinâmicos e a tela de sucesso final.
class ChangePasswordPage extends StatelessWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChangePasswordController(),
      child: const _ChangePasswordScreenContent(),
    );
  }
}

class _ChangePasswordScreenContent extends StatefulWidget {
  const _ChangePasswordScreenContent();

  @override
  State<_ChangePasswordScreenContent> createState() => _ChangePasswordScreenContentState();
}

class _ChangePasswordScreenContentState extends State<_ChangePasswordScreenContent> {
  late final TextEditingController _currentController;
  late final TextEditingController _newController;
  late final TextEditingController _confirmController;

  final FocusNode _currentFocus = FocusNode();
  final FocusNode _newFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final controller = Provider.of<ChangePasswordController>(context, listen: false);
      _currentController = TextEditingController(text: controller.currentPassword);
      _newController = TextEditingController(text: controller.newPassword);
      _confirmController = TextEditingController(text: controller.confirmPassword);
      
      // Listeners de foco para reconstruir o widget e aplicar efeitos de estilo (glow/background)
      _currentFocus.addListener(() => setState(() {}));
      _newFocus.addListener(() => setState(() {}));
      _confirmFocus.addListener(() => setState(() {}));
      
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _currentFocus.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  /// Executa o salvamento da nova senha e gerencia o feedback visual.
  void _submit(BuildContext context, ChangePasswordController controller) async {
    FocusScope.of(context).unfocus();
    final success = await controller.changePassword();
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

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ChangePasswordController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    // Sincroniza estados do Provider com os text controllers locais
    if (_currentController.text != controller.currentPassword) {
      _currentController.value = TextEditingValue(
        text: controller.currentPassword,
        selection: TextSelection.collapsed(offset: controller.currentPassword.length),
      );
    }

    if (_newController.text != controller.newPassword) {
      _newController.value = TextEditingValue(
        text: controller.newPassword,
        selection: TextSelection.collapsed(offset: controller.newPassword.length),
      );
    }

    if (_confirmController.text != controller.confirmPassword) {
      _confirmController.value = TextEditingValue(
        text: controller.confirmPassword,
        selection: TextSelection.collapsed(offset: controller.confirmPassword.length),
      );
    }

    // Se a alteração de senha foi executada com sucesso, exibe a tela de sucesso (fiel ao React)
    if (controller.success) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(isLight),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 360),
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 28),
                    decoration: BoxDecoration(
                      color: AppColors.surface(isLight),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.surfaceBorder(isLight)),
                      boxShadow: [
                        BoxShadow(
                          color: isLight ? const Color(0xFF0B1E4B).withValues(alpha: 0.08) : Colors.black26,
                          blurRadius: 64,
                          offset: const Offset(0, 24),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Ícone verde de sucesso com gradiente
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.brandGradient,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x6600B37E),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.check, color: Colors.white, size: 32),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Senha alterada!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(isLight),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Sua senha foi atualizada com sucesso. Use-a no próximo acesso.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary(isLight),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Botão voltar
                        Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x6600B37E),
                                blurRadius: 20,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              controller.setSuccess(false);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Voltar ao perfil',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final strength = controller.passwordStrength;
    final level = strength['level'] as int;
    final color = strength['color'] as Color;
    final label = strength['label'] as String;

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
                // Header (fiel ao layout React)
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
                              child: Icon(
                                Icons.arrow_back_ios_new,
                                color: isLight ? AppColors.textPrimary(true) : Colors.white60,
                                size: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trocar Senha',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(isLight),
                                  height: 1.2,
                                ),
                              ),
                              Text(
                                'SEGURANÇA DA CONTA',
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
                    padding: const EdgeInsets.only(top: 28, left: 20, right: 20, bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Ícone do cadeado de segurança + Textos explicativos
                        Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(17),
                                color: AppColors.primary.withValues(alpha: 0.12),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                              ),
                              child: const Icon(Icons.lock_outline, color: AppColors.primary, size: 26),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Crie uma nova senha',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(isLight),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sua senha deve ter pelo menos 8 caracteres e combinar letras, números e símbolos.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(isLight),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Form Card (Cadeado e inputs)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.surface(isLight),
                            border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            borderRadius: BorderRadius.circular(20),
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
                              // Senha atual
                              _buildPasswordField(
                                label: 'Senha atual',
                                controller: _currentController,
                                focusNode: _currentFocus,
                                isObscured: !controller.showCurrentPassword,
                                onToggle: controller.toggleShowCurrentPassword,
                                onChanged: controller.setCurrentPassword,
                                isLight: isLight,
                                placeholder: '••••••••',
                              ),
                              const SizedBox(height: 14),
                              Divider(color: AppColors.divider(isLight), height: 1),
                              const SizedBox(height: 14),

                              // Nova senha
                              _buildPasswordField(
                                label: 'Nova senha',
                                controller: _newController,
                                focusNode: _newFocus,
                                isObscured: !controller.showNewPassword,
                                onToggle: controller.toggleShowNewPassword,
                                onChanged: controller.setNewPassword,
                                isLight: isLight,
                                placeholder: 'Mínimo 8 caracteres',
                              ),

                              // Medidor de força da senha
                              if (controller.newPassword.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: List.generate(4, (index) {
                                    final isActive = index < level;
                                    return Expanded(
                                      child: Container(
                                        height: 3,
                                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(2),
                                          color: isActive ? color : (isLight ? const Color(0xFFDDE3F0) : Colors.white.withValues(alpha: 0.1)),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Senha $label',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                    Text(
                                      '${controller.newPassword.length} caracteres',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted(isLight),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 14),
                              Divider(color: AppColors.divider(isLight), height: 1),
                              const SizedBox(height: 14),

                              // Confirmar nova senha
                              _buildPasswordField(
                                label: 'Confirmar nova senha',
                                controller: _confirmController,
                                focusNode: _confirmFocus,
                                isObscured: !controller.showConfirmPassword,
                                onToggle: controller.toggleShowConfirmPassword,
                                onChanged: controller.setConfirmPassword,
                                isLight: isLight,
                                placeholder: 'Repita a nova senha',
                              ),

                              // Validador se as senhas coincidem
                              if (controller.confirmPassword.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Row(
                                  children: [
                                    Icon(
                                      controller.passwordsMatch ? Icons.check : Icons.close,
                                      color: controller.passwordsMatch ? AppColors.primary : AppColors.danger,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      controller.passwordsMatch ? 'Senhas coincidem' : 'Senhas não coincidem',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: controller.passwordsMatch ? AppColors.primary : AppColors.danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Checklist de requisitos
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface(isLight),
                            border: Border.all(color: AppColors.surfaceBorder(isLight)),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isLight
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF0B1E4B).withValues(alpha: 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'REQUISITOS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary(isLight),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildRequirementRow('Mínimo 8 caracteres', controller.metLength),
                              const SizedBox(height: 7),
                              _buildRequirementRow('Pelo menos um número', controller.metNumber),
                              const SizedBox(height: 7),
                              _buildRequirementRow('Pelo menos uma letra maiúscula', controller.metUppercase),
                              const SizedBox(height: 7),
                              _buildRequirementRow(r'Pelo menos um caractere especial (!@#$…)', controller.metSymbol),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Botão de Confirmação (Gradient se puder enviar)
                        Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: controller.canSubmit ? AppColors.brandGradient : null,
                            color: !controller.canSubmit ? AppColors.inputBackground(isLight) : null,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: controller.canSubmit
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    )
                                  ]
                                : null,
                          ),
                          child: ElevatedButton(
                            onPressed: (controller.canSubmit && !controller.isLoading)
                                ? () => _submit(context, controller)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: controller.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 15,
                                        color: controller.canSubmit ? Colors.white : AppColors.textMuted(isLight),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Confirmar nova senha',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: controller.canSubmit ? Colors.white : AppColors.textMuted(isLight),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Link recuperar por e-mail
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/forgot-password');
                          },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: Text.rich(
                            TextSpan(
                              text: 'Esqueceu sua senha? ',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(isLight)),
                              children: const [
                                TextSpan(
                                  text: 'Recuperar por e-mail',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
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

  /// Constrói um campo de senha customizado com efeitos de foco
  Widget _buildPasswordField({
    required String label,
    String? sublabel,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isObscured,
    required VoidCallback onToggle,
    required Function(String) onChanged,
    required bool isLight,
    required String placeholder,
  }) {
    final hasFocus = focusNode.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(isLight),
                letterSpacing: 0.3,
              ),
            ),
            if (sublabel != null)
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted(isLight),
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: hasFocus ? AppColors.primary.withValues(alpha: 0.07) : AppColors.inputBackground(isLight),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFocus ? AppColors.primary.withValues(alpha: 0.6) : AppColors.surfaceBorder(isLight),
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            obscureText: isObscured,
            style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: hasFocus ? AppColors.primary.withValues(alpha: 0.8) : AppColors.textMuted(isLight),
                size: 15,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  isObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textMuted(isLight),
                  size: 16,
                ),
                onPressed: onToggle,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            ),
          ),
        ),
      ],
    );
  }

  /// Constrói uma linha do checklist de requisitos
  Widget _buildRequirementRow(String text, bool met) {
    final isLight = Provider.of<ThemeController>(context, listen: false).isLightMode;
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: met ? AppColors.primary.withValues(alpha: 0.15) : AppColors.inputBackground(isLight),
            border: Border.all(
              color: met ? AppColors.primary : AppColors.surfaceBorder(isLight),
              width: 1.5,
            ),
          ),
          child: met
              ? const Center(
                  child: Icon(Icons.check, color: AppColors.primary, size: 8),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: met ? AppColors.textPrimary(isLight) : AppColors.textMuted(isLight),
          ),
        ),
      ],
    );
  }
}
