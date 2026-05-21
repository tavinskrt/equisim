import 'package:flutter/material.dart';

class SignUpController extends ChangeNotifier {
  int step = 1;
  String name = '';
  String username = '';
  String email = '';
  String password = '';
  String confirm = '';
  bool showPassword = false;
  bool agreed = false;

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
    email = value;
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

  Future<bool> createAccount() async {
    if (!canSubmit) return false;
    
    // Simula uma requisição de rede
    await Future.delayed(const Duration(seconds: 1));
    debugPrint('Conta criada com sucesso para: $username');
    return true;
  }
}
