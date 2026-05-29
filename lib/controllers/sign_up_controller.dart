import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'theme_controller.dart';

/// Controlador que gerencia o fluxo de cadastro de novas contas da aplicação.
class SignUpController extends ChangeNotifier {
  int step = 1;
  String name = '';
  String username = '';
  String email = '';
  String password = '';
  String confirm = '';
  bool showPassword = false;
  bool agreed = false;
  bool isLoading = false;

  /// Define a etapa atual do formulário de cadastro.
  void setStep(int value) {
    step = value;
    notifyListeners();
  }

  /// Define o nome do usuário.
  void setName(String value) {
    name = value;
    notifyListeners();
  }

  /// Define o nome de usuário (username).
  void setUsername(String value) {
    username = value;
    notifyListeners();
  }

  /// Define e trata o e-mail inserido.
  void setEmail(String value) {
    email = value.trim();
    notifyListeners();
  }

  /// Define a senha inserida.
  void setPassword(String value) {
    password = value;
    notifyListeners();
  }

  /// Define a confirmação de senha inserida.
  void setConfirm(String value) {
    confirm = value;
    notifyListeners();
  }

  /// Alterna a visibilidade da senha na interface.
  void toggleShowPassword() {
    showPassword = !showPassword;
    notifyListeners();
  }

  /// Alterna o estado de aceitação dos termos de uso da plataforma.
  void toggleAgreed() {
    agreed = !agreed;
    notifyListeners();
  }

  /// Avalia dinamicamente o nível de segurança da senha digitada.
  Map<String, dynamic> get passwordStrength {
    if (password.isEmpty) return {'level': 0, 'label': '', 'color': Colors.transparent};
    if (password.length < 6) return {'level': 1, 'label': 'Fraca', 'color': const Color(0xFFEF4444)};
    if (password.length < 10 || !password.contains(RegExp(r'[0-9]'))) {
      return {'level': 2, 'label': 'Média', 'color': const Color(0xFFF59E0B)};
    }
    return {'level': 3, 'label': 'Forte', 'color': const Color(0xFF00B37E)};
  }

  /// Verifica se os campos da primeira etapa estão devidamente preenchidos.
  bool get canProceedToStep2 => name.trim().isNotEmpty && username.trim().isNotEmpty && email.trim().isNotEmpty;
  
  /// Verifica se os termos foram aceitos e se as senhas coincidem para permitir a submissão.
  bool get canSubmit => agreed && password.isNotEmpty && confirm == password;

  /// Registra uma nova conta de usuário via Firebase Auth e sincroniza as preferências iniciais de tema.
  Future<String?> createAccount(BuildContext context) async {
    if (!canSubmit) return 'Preencha todos os campos obrigatórios corretamente.';
    
    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Salva o nome de usuário (username) escolhido no perfil do usuário no Firebase
      await userCredential.user?.updateDisplayName(username);
      
      if (context.mounted && userCredential.user != null) {
        final themeController = Provider.of<ThemeController>(context, listen: false);
        // Salva a preferência inicial no Firestore
        await themeController.syncWithFirebase(userCredential.user!.uid);
      }

      isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();
      if (e.code == 'weak-password') {
        return 'A senha fornecida é considerada muito fraca pelo servidor.';
      } else if (e.code == 'email-already-in-use') {
        return 'Já existe uma conta ativa cadastrada com este e-mail.';
      } else if (e.code == 'invalid-email') {
        return 'O formato do e-mail inserido é inválido.';
      }
      return 'Erro no cadastro: ${e.message}';
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return 'Ocorreu um erro inesperado: $e';
    }
  }
}
