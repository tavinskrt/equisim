import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../utils/app_colors.dart';
import '../controllers/theme_controller.dart';
import '../controllers/sign_up_controller.dart';

/// Tela responsável pela criação de novas contas de usuário.
class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SignUpController(),
      child: const _SignUpScreenContent(),
    );
  }
}

class _SignUpScreenContent extends StatefulWidget {
  const _SignUpScreenContent();

  @override
  State<_SignUpScreenContent> createState() => _SignUpScreenContentState();
}

class _SignUpScreenContentState extends State<_SignUpScreenContent> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmController;
  late SignUpController _signUpController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _signUpController = Provider.of<SignUpController>(context, listen: false);
      _nameController = TextEditingController(text: _signUpController.name);
      _usernameController = TextEditingController(text: _signUpController.username);
      _emailController = TextEditingController(text: _signUpController.email);
      _passwordController = TextEditingController(text: _signUpController.password);
      _confirmController = TextEditingController(text: _signUpController.confirm);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Submete os dados de cadastro e fornece retorno visual de sucesso ou erro.
  void _submit(BuildContext context, SignUpController controller) async {
    FocusScope.of(context).unfocus();
    final error = await controller.createAccount(context);
    if (context.mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: const Color(0xFFEF4444)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta criada com sucesso!'),
            backgroundColor: Color(0xFF00B37E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<SignUpController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    // Sincroniza os dados de digitação locais com o estado centralizado do Provider
    final currentName = controller.name;
    if (_nameController.text != currentName) {
      _nameController.value = TextEditingValue(
        text: currentName,
        selection: TextSelection.collapsed(offset: currentName.length),
      );
    }

    final currentUsername = controller.username;
    if (_usernameController.text != currentUsername) {
      _usernameController.value = TextEditingValue(
        text: currentUsername,
        selection: TextSelection.collapsed(offset: currentUsername.length),
      );
    }

    final currentEmail = controller.email;
    if (_emailController.text != currentEmail) {
      _emailController.value = TextEditingValue(
        text: currentEmail,
        selection: TextSelection.collapsed(offset: currentEmail.length),
      );
    }

    final currentPassword = controller.password;
    if (_passwordController.text != currentPassword) {
      _passwordController.value = TextEditingValue(
        text: currentPassword,
        selection: TextSelection.collapsed(offset: currentPassword.length),
      );
    }

    final currentConfirm = controller.confirm;
    if (_confirmController.text != currentConfirm) {
      _confirmController.value = TextEditingValue(
        text: currentConfirm,
        selection: TextSelection.collapsed(offset: currentConfirm.length),
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
            // Efeitos visuais geométricos no fundo
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

            // Conteúdo principal
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Botão superior para retornar na navegação ou etapa
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            if (controller.step > 1) {
                              controller.setStep(controller.step - 1);
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          icon: Icon(Icons.arrow_back_ios, size: 14, color: AppColors.textSecondary(isLight)),
                          label: Text(
                            controller.step > 1 ? 'Voltar' : 'Já tenho conta',
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

                      // Card principal translúcido
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(top: 32, left: 28, right: 28, bottom: 28),
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
                                // Identidade visual e logotipo
                                Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: AppColors.brandGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.35),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.show_chart, color: Colors.white, size: 20),
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
                                          ),
                                        ),
                                        Text(
                                          'Criar nova conta',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary(isLight),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Indicadores visuais de etapa do cadastro
                                Row(
                                  children: [
                                    _buildStepIndicator(1, controller.step, isLight),
                                    Expanded(
                                      child: Container(
                                        height: 1.5,
                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                        color: controller.step > 1 
                                            ? AppColors.primary 
                                            : AppColors.surfaceBorder(isLight),
                                      ),
                                    ),
                                    _buildStepIndicator(2, controller.step, isLight),
                                    const SizedBox(width: 8),
                                    Text(
                                      controller.step == 1 ? 'Dados pessoais' : 'Senha e segurança',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textSecondary(isLight),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Exibição condicional da etapa ativa do formulário
                                controller.step == 1 
                                    ? _buildStep1(context, controller, isLight) 
                                    : _buildStep2(context, controller, isLight),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Rodapé
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

  /// Constrói a bolha indicadora do status de cada etapa
  Widget _buildStepIndicator(int stepIndex, int currentStep, bool isLight) {
    bool isCompletedOrCurrent = currentStep >= stepIndex;
    bool isCompleted = currentStep > stepIndex;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isCompletedOrCurrent
            ? AppColors.brandGradient
            : null,
        color: !isCompletedOrCurrent ? AppColors.inputBackground(isLight) : null,
        border: Border.all(
          color: isCompletedOrCurrent ? Colors.transparent : AppColors.surfaceBorder(isLight),
        ),
        boxShadow: isCompletedOrCurrent
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
            : null,
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check, color: Colors.white, size: 14)
            : Text(
                '$stepIndex',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isCompletedOrCurrent ? Colors.white : AppColors.textSecondary(isLight),
                ),
              ),
      ),
    );
  }

  /// Formulário da Etapa 1: Dados Pessoais
  Widget _buildStep1(BuildContext context, SignUpController controller, bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seus dados',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(isLight),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Preencha as informações abaixo para criar sua conta.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(isLight),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),

        // Campo de entrada: Nome completo
        Text(
          'Nome completo',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(isLight),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        _buildTextField(
          key: const ValueKey('signup_name_field'),
          controller: _nameController,
          onChanged: controller.setName,
          hintText: 'Seu nome',
          icon: Icons.badge_outlined,
          isLight: isLight,
        ),
        const SizedBox(height: 14),

        // Campo de entrada: Usuário
        Text(
          'Usuário',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(isLight),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        _buildTextField(
          key: const ValueKey('signup_username_field'),
          controller: _usernameController,
          onChanged: controller.setUsername,
          hintText: 'seu_usuario',
          icon: Icons.person_outline,
          isLight: isLight,
        ),
        const SizedBox(height: 14),

        // Campo de entrada: E-mail
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
        _buildTextField(
          key: const ValueKey('signup_email_field'),
          controller: _emailController,
          onChanged: controller.setEmail,
          hintText: 'email@exemplo.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          isLight: isLight,
        ),
        const SizedBox(height: 22),

        // Botão para avançar de etapa
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: controller.canProceedToStep2 ? AppColors.brandGradient : null,
            color: !controller.canProceedToStep2 ? AppColors.inputBackground(isLight) : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: controller.canProceedToStep2 ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ] : null,
          ),
          child: ElevatedButton(
            onPressed: controller.canProceedToStep2 ? () => controller.setStep(2) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Continuar',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: controller.canProceedToStep2 ? Colors.white : AppColors.textMuted(isLight),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Formulário da Etapa 2: Senha e Aceitação de Termos
  Widget _buildStep2(BuildContext context, SignUpController controller, bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Crie sua senha',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(isLight),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use uma senha forte para proteger sua conta.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(isLight),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),

        // Campo de entrada da senha
        Text(
          'Senha',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(isLight),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          key: const ValueKey('signup_password_field'),
          controller: _passwordController,
          onChanged: controller.setPassword,
          obscureText: !controller.showPassword,
          style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Mínimo 8 caracteres',
            hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
            prefixIcon: Icon(Icons.lock_outline, color: AppColors.textMuted(isLight), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                controller.showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textMuted(isLight),
                size: 20,
              ),
              onPressed: controller.toggleShowPassword,
            ),
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
        
        // Exibição do nível de segurança da senha
        if (controller.password.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: List.generate(3, (index) {
              final strength = controller.passwordStrength;
              final isActive = index < strength['level'];
              return Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: isActive ? strength['color'] : AppColors.surfaceBorder(isLight),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 5),
          Text(
            'Senha ${controller.passwordStrength['label']}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: controller.passwordStrength['color'],
            ),
          ),
        ],
        const SizedBox(height: 14),

        // Campo de confirmação de senha
        Text(
          'Confirmar senha',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(isLight),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          key: const ValueKey('signup_confirm_field'),
          controller: _confirmController,
          onChanged: controller.setConfirm,
          obscureText: true,
          style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Repita sua senha',
            hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
            prefixIcon: Icon(Icons.lock_outline, color: AppColors.textMuted(isLight), size: 20),
            suffixIcon: controller.confirm.isNotEmpty
                ? Icon(
                    controller.confirm == controller.password ? Icons.check : Icons.close,
                    color: controller.confirm == controller.password ? AppColors.primary : const Color(0xFFEF4444),
                    size: 20,
                  )
                : null,
            filled: true,
            fillColor: AppColors.inputBackground(isLight),
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: controller.confirm.isNotEmpty 
                  ? (controller.confirm == controller.password ? AppColors.primary.withValues(alpha: 0.5) : const Color(0xFFEF4444).withValues(alpha: 0.5)) 
                  : AppColors.surfaceBorder(isLight)
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: controller.confirm.isNotEmpty 
                  ? (controller.confirm == controller.password ? AppColors.primary.withValues(alpha: 0.5) : const Color(0xFFEF4444).withValues(alpha: 0.5)) 
                  : AppColors.surfaceBorder(isLight)
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Aceitação de termos e políticas de privacidade
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: controller.toggleAgreed,
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1, right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: controller.agreed ? null : Border.all(color: AppColors.surfaceBorder(isLight), width: 1.5),
                  gradient: controller.agreed ? AppColors.brandGradient : null,
                  boxShadow: controller.agreed ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))] : null,
                ),
                child: controller.agreed ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Concordo com os ',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(isLight), height: 1.6),
                  children: const [
                    TextSpan(text: 'Termos de Uso', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' e a '),
                    TextSpan(text: 'Política de Privacidade', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' do Equisim.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Botão de submissão do cadastro final
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: controller.canSubmit ? AppColors.brandGradient : null,
            color: !controller.canSubmit ? AppColors.inputBackground(isLight) : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: controller.canSubmit ? [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6)),
            ] : null,
          ),
          child: ElevatedButton(
            onPressed: (controller.canSubmit && !controller.isLoading) ? () => _submit(context, controller) : null,
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
              : Text(
                  'Criar minha conta',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: controller.canSubmit ? Colors.white : AppColors.textMuted(isLight),
                    letterSpacing: 0.2,
                  ),
                ),
          ),
        ),
      ],
    );
  }

  /// Helper genérico para estruturar campos de entrada TextField
  Widget _buildTextField({
    Key? key,
    required TextEditingController controller,
    required Function(String) onChanged,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    required bool isLight,
  }) {
    return TextField(
      key: key,
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14),
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textMuted(isLight)),
        prefixIcon: Icon(icon, color: AppColors.textMuted(isLight), size: 20),
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
    );
  }
}
