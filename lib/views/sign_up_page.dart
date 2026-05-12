import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../controllers/sign_up_controller.dart';

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

class _SignUpScreenContent extends StatelessWidget {
  const _SignUpScreenContent();

  void _submit(BuildContext context, SignUpController controller) async {
    FocusScope.of(context).unfocus();
    final success = await controller.createAccount();
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta criada com sucesso!'),
          backgroundColor: Color(0xFF00B37E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context); // Voltar ao login após sucesso
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<SignUpController>(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B1E4B),
              Color(0xFF0F2C6A),
              Color(0xFF0D3D2F),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            /// Decorações geométricas de fundo
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00B37E).withValues(alpha: 0.08),
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
                  color: const Color(0xFF00B37E).withValues(alpha: 0.06),
                ),
              ),
            ),

            /// Conteúdo principal
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      /// Botão de Voltar
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
                          icon: const Icon(Icons.arrow_back_ios, size: 14, color: Colors.white54),
                          label: Text(
                            controller.step > 1 ? 'Voltar' : 'Já tenho conta',
                            style: const TextStyle(
                              color: Colors.white54,
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

                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(top: 32, left: 28, right: 28, bottom: 28),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 64,
                                  offset: Offset(0, 24),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                /// Header: Logo + Título
                                Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [Color(0xFF00B37E), Color(0xFF00CC8F)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00B37E).withValues(alpha: 0.35),
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
                                        const Text(
                                          'Equisim',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          'Criar nova conta',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white.withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                /// Indicador de Etapas
                                Row(
                                  children: [
                                    _buildStepIndicator(1, controller.step),
                                    Expanded(
                                      child: Container(
                                        height: 1.5,
                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                        color: controller.step > 1 
                                            ? const Color(0xFF00B37E) 
                                            : Colors.white.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    _buildStepIndicator(2, controller.step),
                                    const SizedBox(width: 8),
                                    Text(
                                      controller.step == 1 ? 'Dados pessoais' : 'Senha e segurança',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                /// Conteúdo da Etapa
                                controller.step == 1 
                                    ? _buildStep1(context, controller) 
                                    : _buildStep2(context, controller),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      /// Rodapé
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 12, color: Colors.white.withValues(alpha: 0.25)),
                          const SizedBox(width: 6),
                          Text(
                            'Conexão segura · Dados criptografados',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.25),
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

  Widget _buildStepIndicator(int stepIndex, int currentStep) {
    bool isCompletedOrCurrent = currentStep >= stepIndex;
    bool isCompleted = currentStep > stepIndex;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isCompletedOrCurrent
            ? const LinearGradient(colors: [Color(0xFF00B37E), Color(0xFF00CC8F)])
            : null,
        color: !isCompletedOrCurrent ? Colors.white.withValues(alpha: 0.08) : null,
        border: Border.all(
          color: isCompletedOrCurrent ? Colors.transparent : Colors.white.withValues(alpha: 0.2),
        ),
        boxShadow: isCompletedOrCurrent
            ? [BoxShadow(color: const Color(0xFF00B37E).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
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
                  color: isCompletedOrCurrent ? Colors.white : Colors.white.withValues(alpha: 0.4),
                ),
              ),
      ),
    );
  }

  Widget _buildStep1(BuildContext context, SignUpController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seus dados',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Preencha as informações abaixo para criar sua conta.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),

        /// Nome completo
        Text(
          'Nome completo',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        _buildTextField(
          onChanged: controller.setName,
          hintText: 'Seu nome',
          icon: Icons.badge_outlined,
          initialValue: controller.name,
        ),
        const SizedBox(height: 14),

        /// Usuário
        Text(
          'Usuário',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        _buildTextField(
          onChanged: controller.setUsername,
          hintText: 'seu_usuario',
          icon: Icons.person_outline,
          initialValue: controller.username,
        ),
        const SizedBox(height: 14),

        /// E-mail
        Text(
          'E-mail',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        _buildTextField(
          onChanged: controller.setEmail,
          hintText: 'email@exemplo.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          initialValue: controller.email,
        ),
        const SizedBox(height: 22),

        /// Continuar
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00B37E), Color(0xFF00CC8F)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00B37E).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
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
            child: const Text(
              'Continuar',
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
    );
  }

  Widget _buildStep2(BuildContext context, SignUpController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Crie sua senha',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use uma senha forte para proteger sua conta.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),

        /// Senha
        Text(
          'Senha',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          onChanged: controller.setPassword,
          obscureText: !controller.showPassword,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Mínimo 8 caracteres',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.lock_outline, color: Colors.white.withValues(alpha: 0.3), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                controller.showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white.withValues(alpha: 0.35),
                size: 20,
              ),
              onPressed: controller.toggleShowPassword,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF00B37E).withValues(alpha: 0.6)),
            ),
          ),
        ),
        
        /// Força da senha
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
                    color: isActive ? strength['color'] : Colors.white.withValues(alpha: 0.1),
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

        /// Confirmar senha
        Text(
          'Confirmar senha',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          onChanged: controller.setConfirm,
          obscureText: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Repita sua senha',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.lock_outline, color: Colors.white.withValues(alpha: 0.3), size: 20),
            suffixIcon: controller.confirm.isNotEmpty
                ? Icon(
                    controller.confirm == controller.password ? Icons.check : Icons.close,
                    color: controller.confirm == controller.password ? const Color(0xFF00B37E) : const Color(0xFFEF4444),
                    size: 20,
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: controller.confirm.isNotEmpty 
                  ? (controller.confirm == controller.password ? const Color(0xFF00B37E).withValues(alpha: 0.5) : const Color(0xFFEF4444).withValues(alpha: 0.5)) 
                  : Colors.white.withValues(alpha: 0.12)
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: controller.confirm.isNotEmpty 
                  ? (controller.confirm == controller.password ? const Color(0xFF00B37E).withValues(alpha: 0.5) : const Color(0xFFEF4444).withValues(alpha: 0.5)) 
                  : Colors.white.withValues(alpha: 0.12)
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF00B37E).withValues(alpha: 0.6)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        /// Termos
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
                  border: controller.agreed ? null : Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                  gradient: controller.agreed ? const LinearGradient(colors: [Color(0xFF00B37E), Color(0xFF00CC8F)]) : null,
                  boxShadow: controller.agreed ? [BoxShadow(color: const Color(0xFF00B37E).withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))] : null,
                ),
                child: controller.agreed ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Concordo com os ',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45), height: 1.6),
                  children: const [
                    TextSpan(text: 'Termos de Uso', style: TextStyle(color: Color(0xFF00B37E), fontWeight: FontWeight.w600)),
                    TextSpan(text: ' e a '),
                    TextSpan(text: 'Política de Privacidade', style: TextStyle(color: Color(0xFF00B37E), fontWeight: FontWeight.w600)),
                    TextSpan(text: ' do Equisim.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        /// Botão Criar Conta
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: controller.canSubmit 
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF00B37E), Color(0xFF00CC8F)])
                : null,
            color: !controller.canSubmit ? Colors.white.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: controller.canSubmit ? [
              BoxShadow(color: const Color(0xFF00B37E).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6)),
            ] : null,
          ),
          child: ElevatedButton(
            onPressed: controller.canSubmit ? () => _submit(context, controller) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Criar minha conta',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: controller.canSubmit ? Colors.white : Colors.white.withValues(alpha: 0.3),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required Function(String) onChanged,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? initialValue,
  }) {
    final textController = TextEditingController(text: initialValue);
    
    // Configura o cursor para o final quando inicializado
    if (initialValue != null) {
      textController.selection = TextSelection.fromPosition(TextPosition(offset: initialValue.length));
    }
    
    return TextField(
      controller: textController,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.3), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF00B37E).withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
