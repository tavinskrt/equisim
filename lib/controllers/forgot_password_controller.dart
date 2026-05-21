import 'package:flutter/material.dart';

class ForgotPasswordController extends ChangeNotifier {
  String username = '';

  void setUsername(String value) {
    username = value;
    notifyListeners();
  }

  Future<bool> sendRecoveryLink() async {
    if (username.trim().isEmpty) return false;
    
    // Simula uma requisição de rede
    await Future.delayed(const Duration(seconds: 1));
    debugPrint('Link de recuperação enviado para o usuário: $username');
    return true;
  }
}
