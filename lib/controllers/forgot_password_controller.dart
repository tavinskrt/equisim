import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordController extends ChangeNotifier {
  String email = '';
  bool isLoading = false;

  void setEmail(String value) {
    email = value.trim();
    notifyListeners();
  }

  Future<String?> sendRecoveryLink() async {
    if (email.isEmpty) return 'Preencha o e-mail.';
    
    isLoading = true;
    notifyListeners();

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      isLoading = false;
      notifyListeners();
      return null; // Sucesso
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();
      if (e.code == 'user-not-found') {
        return 'Nenhum usuário encontrado para esse e-mail.';
      } else if (e.code == 'invalid-email') {
        return 'O formato do e-mail é inválido.';
      }
      return 'Erro: ${e.message}';
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return 'Erro inesperado: $e';
    }
  }
}
