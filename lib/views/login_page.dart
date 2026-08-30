import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../presentation/theme/fin_theme.dart';
import '../controllers/login_controller.dart';
import '../presentation/shell/app_shell.dart';

/// Tela responsável pela autenticação e login de usuários na plataforma.
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

    // Sincroniza os controllers do formulário local com os estados do Provider
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
          gradient: context.fin.canvasGradient,
        ),
        child: Stack(
          children: [
            // Efeitos de círculos de fundo
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.fin.brand.withValues(alpha: 0.08),
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
                  color: context.fin.brand.withValues(alpha: 0.06),
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
                  color: context.fin.textPrimary.withValues(alpha: 0.03),
                ),
              ),
            ),
            
            // Área de conteúdo principal
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
                              color: context.fin.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: context.fin.border),
                              boxShadow: [
                                BoxShadow(
                                  color: context.fin.shadow,
                                  blurRadius: 64,
                                  offset: Offset(0, 24),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Cabeçalho de Logotipo da Aplicação
                                Column(
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        gradient: context.fin.brandGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: context.fin.brand.withValues(alpha: 0.4),
                                            blurRadius: 24,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Icon(Icons.show_chart, color: context.fin.textOnBrand, size: 32),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Equisim',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: context.fin.textPrimary,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Comparador de Carteiras',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.fin.textSecondary,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),

                                // Boas-vindas e identificação de seção
                                Text(
                                  'Bem-vindo de volta!',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: context.fin.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Acesse sua conta para continuar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.fin.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Campo de entrada do e-mail
                                Text(
                                  'E-mail',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.fin.textSecondary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                TextField(
                                  key: const ValueKey('login_email_field'),
                                  controller: _emailController,
                                  onChanged: controller.setEmail,
                                  style: TextStyle(color: context.fin.textPrimary, fontSize: 14),
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    hintText: 'seu_email@exemplo.com',
                                    hintStyle: TextStyle(color: context.fin.textTertiary),
                                    prefixIcon: Icon(Icons.email_outlined, color: context.fin.textTertiary, size: 20),
                                    filled: true,
                                    fillColor: context.fin.surfaceSunken,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: context.fin.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: context.fin.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: context.fin.brand.withValues(alpha: 0.6)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Campo de entrada da senha
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Senha',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.fin.textSecondary,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pushNamed(context, '/forgot-password');
                                      },
                                      child: Text(
                                        'Esqueci a senha',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: context.fin.brand,
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
                                  style: TextStyle(color: context.fin.textPrimary, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    hintStyle: TextStyle(color: context.fin.textTertiary),
                                    prefixIcon: Icon(Icons.lock_outline, color: context.fin.textTertiary, size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        controller.showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        color: context.fin.textTertiary,
                                        size: 20,
                                      ),
                                      onPressed: controller.toggleShowPassword,
                                    ),
                                    filled: true,
                                    fillColor: context.fin.surfaceSunken,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: context.fin.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: context.fin.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: context.fin.brand.withValues(alpha: 0.6)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Botão para acionar a autenticação
                                Container(
                                  width: double.infinity,
                                  height: 50,
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
                                    onPressed: controller.isLoading ? null : () async {
                                      final error = await controller.login(context);
                                      if (error != null && context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(error), backgroundColor: context.fin.negative),
                                        );
                                      } else if (context.mounted) {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (context) => const AppShell()),
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
                                      ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: context.fin.textOnBrand, strokeWidth: 2))
                                      : Text(
                                          'Entrar',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: context.fin.textOnBrand,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Link para redirecionamento ao cadastro
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Não tem uma conta? ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.fin.textSecondary,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pushNamed(context, '/sign-up');
                                      },
                                      child: Text(
                                        'Criar conta',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: context.fin.brand,
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
                      
                      // Rodapé institucional
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 12, color: context.fin.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Conexão segura · Dados criptografados',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: context.fin.textTertiary,
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
