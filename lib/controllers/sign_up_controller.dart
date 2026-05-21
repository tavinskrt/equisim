import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  void setStep(int value) {
    step = value;
    notifyListeners();
  }

  void setName(String value) {
    name = value;
    notifyListeners();
  }

  void setUsername(String value) {
    username = value;
    notifyListeners();
  }

  void setEmail(String value) {
    email = value.trim();
    notifyListeners();
  }

  void setPassword(String value) {
    password = value;
    notifyListeners();
  }

  void setConfirm(String value) {
    confirm = value;
    notifyListeners();
  }

  void toggleShowPassword() {
    showPassword = !showPassword;
    notifyListeners();
  }

  void toggleAgreed() {
    agreed = !agreed;
    notifyListeners();
  }

  Map<String, dynamic> get passwordStrength {
    if (password.isEmpty) return {'level': 0, 'label': '', 'color': Colors.transparent};
    if (password.length < 6) return {'level': 1, 'label': 'Fraca', 'color': const Color(0xFFEF4444)};
    if (password.length < 10 || !password.contains(RegExp(r'[0-9]'))) {
      return {'level': 2, 'label': 'Média', 'color': const Color(0xFFF59E0B)};
    }
    return {'level': 3, 'label': 'Forte', 'color': const Color(0xFF00B37E)};
  }

  bool get canProceedToStep2 => name.trim().isNotEmpty && username.trim().isNotEmpty && email.trim().isNotEmpty;
  bool get canSubmit => agreed && password.isNotEmpty && confirm == password;

  Future<String?> createAccount() async {
    if (!canSubmit) return 'Preencha todos os campos corretamente.';
    
    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Salva o username no perfil do Firebase
      await userCredential.user?.updateDisplayName(username);
      
      isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();
      if (e.code == 'weak-password') {
        return 'A senha fornecida é muito fraca.';
      } else if (e.code == 'email-already-in-use') {
        return 'Já existe uma conta com esse e-mail.';
      } else if (e.code == 'invalid-email') {
        return 'O e-mail fornecido é inválido.';
      }
      return 'Erro: ${e.message}';
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return 'Erro inesperado: $e';
    }
  }
}
