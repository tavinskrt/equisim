import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../controllers/forgot_password_controller.dart';

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

class _ForgotPasswordScreenContent extends StatelessWidget {
  const _ForgotPasswordScreenContent();

  void _submit(BuildContext context, ForgotPasswordController controller) async {
    FocusScope.of(context).unfocus();
    final success = await controller.sendRecoveryLink();
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link de recuperação enviado para o e-mail cadastrado do usuário ${controller.username}'),
          backgroundColor: const Color(0xFF00B37E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<ForgotPasswordController>(context);

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
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios, size: 14, color: Colors.white54),
                          label: const Text(
                            'Voltar ao login',
                            style: TextStyle(
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
                            padding: const EdgeInsets.only(top: 36, left: 28, right: 28, bottom: 32),
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
                                /// Ícone
                                Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      color: const Color(0xFF00B37E).withValues(alpha: 0.15),
                                      border: Border.all(color: const Color(0xFF00B37E).withValues(alpha: 0.3)),
                                    ),
                                    child: const Icon(Icons.lock_reset, color: Color(0xFF00B37E), size: 32),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                /// Título
                                const Text(
                                  'Recuperar senha',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Digite seu usuário cadastrado e enviaremos um link de recuperação para o e-mail associado.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.5),
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                /// Campo do usuário
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
                                TextField(
                                  onChanged: controller.setUsername,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  keyboardType: TextInputType.text,
                                  decoration: InputDecoration(
                                    hintText: 'seu_usuario',
                                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                                    prefixIcon: Icon(Icons.person_outline, color: Colors.white.withValues(alpha: 0.3), size: 20),
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
                                const SizedBox(height: 20),

                                /// Botão de envio
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
                                    onPressed: () => _submit(context, controller),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
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

                                /// Info
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00B37E).withValues(alpha: 0.08),
                                    border: Border.all(color: const Color(0xFF00B37E).withValues(alpha: 0.18)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(Icons.info_outline, color: Color(0xFF00B37E), size: 16),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'O link de recuperação expira em 30 minutos e só pode ser usado uma vez.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white.withValues(alpha: 0.45),
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
}
