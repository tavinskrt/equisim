import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../utils/app_colors.dart';
import '../controllers/theme_controller.dart';
import '../controllers/login_controller.dart';
import 'home_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginController(),
      child: const _LoginScreenContent(),
    );
  }
}

class _LoginScreenContent extends StatefulWidget {
  const _LoginScreenContent();

  @override
  State<_LoginScreenContent> createState() => _LoginScreenContentState();
}

class _LoginScreenContentState extends State<_LoginScreenContent> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late LoginController _loginController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _loginController = Provider.of<LoginController>(context, listen: false);
      _emailController = TextEditingController(text: _loginController.email);
      _passwordController = TextEditingController(text: _loginController.password);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<LoginController>(context);
    final themeController = Provider.of<ThemeController>(context);
    final isLight = themeController.isLightMode;

    // Sincronizar de forma reativa os valores digitados no controller do Provider
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

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(isLight),
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
            Positioned(
              top: MediaQuery.of(context).size.height * 0.38,
              left: -50,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textPrimary(isLight).withValues(alpha: 0.03),
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
                                /// Logo
                                Column(
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        gradient: AppColors.brandGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(alpha: 0.4),
                                            blurRadius: 24,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.show_chart, color: Colors.white, size: 32),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Equisim',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(isLight),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Comparador de Carteiras',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary(isLight),
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),

                                /// Bem-vindo de volta
                                Text(
                                  'Bem-vindo de volta!',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary(isLight),
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Acesse sua conta',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary(isLight),
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                /// Campo do usuário
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
                                  key: const ValueKey('login_email_field'),
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
                                const SizedBox(height: 14),

                                /// Campo da senha
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Senha',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary(isLight),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pushNamed(context, '/forgot-password');
                                      },
                                      child: const Text(
                                        'Esqueci a senha',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                TextField(
                                  key: const ValueKey('login_password_field'),
                                  controller: _passwordController,
                                  onChanged: controller.setPassword,
                                  obscureText: !controller.showPassword,
                                  style: TextStyle(color: AppColors.textPrimary(isLight), fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
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
                                const SizedBox(height: 20),

                                /// Botão de login
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
                                    onPressed: controller.isLoading ? null : () async {
                                      final error = await controller.login(context);
                                      if (error != null && context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(error), backgroundColor: const Color(0xFFEF4444)),
                                        );
                                      } else if (context.mounted) {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (context) => const HomePage()),
                                        );
                                      }
                                    },
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
                                          'Entrar',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                /// Criar conta
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Não tem uma conta? ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary(isLight),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pushNamed(context, '/sign-up');
                                      },
                                      child: const Text(
                                        'Criar conta',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
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

