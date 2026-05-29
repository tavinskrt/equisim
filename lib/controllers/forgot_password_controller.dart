import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controlador responsável pelo fluxo de recuperação de senha dos usuários.
class ForgotPasswordController extends ChangeNotifier {
  String email = '';
  bool isLoading = false;

  /// Atualiza o e-mail digitado no fluxo de recuperação.
  void setEmail(String value) {
    email = value.trim();
    notifyListeners();
  }

  /// Dispara a solicitação do link de redefinição de senha via Firebase Auth.
  Future<String?> sendRecoveryLink() async {
    if (email.isEmpty) return 'Preencha o campo de e-mail.';
    
    isLoading = true;
    notifyListeners();

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      isLoading = false;
      notifyListeners();
      return null; // Retorna null indicando envio com sucesso
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();
      if (e.code == 'user-not-found') {
        return 'Nenhum usuário correspondente a este e-mail foi encontrado.';
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
