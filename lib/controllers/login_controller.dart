import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'theme_controller.dart';

/// Controlador responsável por gerenciar a lógica de login e autenticação.
class LoginController extends ChangeNotifier {
  String email = '';
  String password = '';
  bool showPassword = false;
  bool isLoading = false;

  /// Atualiza o e-mail digitado no fluxo de autenticação.
  void setEmail(String value) {
    email = value.trim();
    notifyListeners();
  }

  /// Atualiza a senha digitada no fluxo de autenticação.
  void setPassword(String value) {
    password = value;
    notifyListeners();
  }

  /// Alterna a visibilidade da senha na interface.
  void toggleShowPassword() {
    showPassword = !showPassword;
    notifyListeners();
  }

  /// Realiza o login do usuário via Firebase Auth e sincroniza as preferências do usuário.
  Future<String?> login(BuildContext context) async {
    if (email.isEmpty || password.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }

    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Sincroniza as preferências de tema do usuário caso o widget ainda esteja montado
      if (context.mounted && userCredential.user != null) {
        final themeController = Provider.of<ThemeController>(context, listen: false);
        await themeController.syncWithFirebase(userCredential.user!.uid);
      }

      isLoading = false;
      notifyListeners();
      return null; // Retorna null indicando sucesso absoluto
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();
      if (e.code == 'user-not-found') {
        return 'Nenhum usuário correspondente a este e-mail foi encontrado.';
      } else if (e.code == 'wrong-password') {
        return 'A senha fornecida está incorreta.';
      } else if (e.code == 'invalid-credential') {
        return 'Credenciais de acesso inválidas.';
      } else if (e.code == 'invalid-email') {
        return 'O formato do e-mail inserido é inválido.';
      }
      return 'Erro na autenticação: ${e.message}';
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return 'Ocorreu um erro inesperado: $e';
    }
  }
}
