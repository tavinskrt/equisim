import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../utils/app_colors.dart';
import '../controllers/theme_controller.dart';
import '../controllers/forgot_password_controller.dart';

/// Tela para solicitação de recuperação de senha da conta.
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ForgotPasswordController(),
      child: const _ForgotPasswordScreenContent(),
    );
  }
}

class _ForgotPasswordScreenContent extends StatefulWidget {
  const _ForgotPasswordScreenContent();

  @override
  State<_ForgotPasswordScreenContent> createState() => _ForgotPasswordScreenContentState();
}

class _ForgotPasswordScreenContentState extends State<_ForgotPasswordScreenContent> {
  late final TextEditingController _emailController;
  late ForgotPasswordController _forgotPasswordController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _forgotPasswordController = Provider.of<ForgotPasswordController>(context, listen: false);
      _emailController = TextEditingController(text: _forgotPasswordController.email);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Dispara a solicitação de redefinição de senha e exibe mensagens de feedback.
  void _submit(BuildContext context, ForgotPasswordController controller) async {
    FocusScope.of(context).unfocus();
    final error = await controller.sendRecoveryLink();
    if (context.mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: const Color(0xFFEF4444)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link de recuperação enviado para o e-mail: ${controller.email}'),
            backgroundColor: const Color(0xFF00B37E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ForgotPasswordController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    // Sincroniza de forma reativa os valores do controller com o campo de texto
    final currentEmail = controller.email;
    if (_emailController.text != currentEmail) {
      _emailController.value = TextEditingValue(
        text: currentEmail,
        selection: TextSelection.collapsed(offset: currentEmail.length),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(isLight),
        ),
        child: Stack(
          children: [
            // Efeitos de esferas geométricas no plano de fundo
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -100,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
              ),
            ),

            // Corpo principal da tela
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Botão superior de retorno à tela de login
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.arrow_back_ios, size: 14, color: AppColors.textSecondary(isLight)),
                          label: Text(
                            'Voltar',
                            style: TextStyle(
                              color: AppColors.textSecondary(isLight),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Card central em efeito vidro (Glassmorphism)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(top: 36, left: 28, right: 28, bottom: 32),
                            decoration: BoxDecoration(
                              color: AppColors.surface(isLight),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.surfaceBorder(isLight)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 64,
                                  offset: Offset(0, 24),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Ícone decorativo superior
                                Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                    ),
                                    child: const Icon(Icons.lock_reset, color: AppColors.primary, size: 32),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Título e subtítulo da página
                                Text(
                                  'Recuperar senha',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary(isLight),
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Digite seu e-mail cadastrado e enviaremos um link de recuperação para ele.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary(isLight),
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Campo de entrada do e-mail do usuário
                                Text(
                                  'E-mail',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary(isLight),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                TextField(
                                  key: const ValueKey('forgot_password_email_field'),
                                  controller: _emailController,
                                  onChanged: controller.setEmail,
                                  style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14),
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    hintText: 'seu_email@exemplo.com',
                                    hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
                                    prefixIcon: Icon(Icons.email_outlined, color: AppColors.textMuted(isLight), size: 20),
                                    filled: true,
                                    fillColor: AppColors.inputBackground(isLight),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.surfaceBorder(isLight)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Botão de envio da recuperação de senha
                                Container(
                                  width: double.infinity,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.brandGradient,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.4),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: controller.isLoading ? null : () => _submit(context, controller),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      disabledBackgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: controller.isLoading
                                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Text(
                                          'Enviar link de recuperação',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                  ),
                                ),

                                // Bloco informativo de segurança
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'O link de recuperação expira em 30 minutos e só pode ser usado uma vez.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary(isLight),
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Rodapé informativo de segurança
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 12, color: AppColors.textMuted(isLight)),
                          const SizedBox(width: 6),
                          Text(
                            'Conexão segura · Dados criptografados',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted(isLight),
                            ),
                          ),
                        ],
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
}
