import 'package:flutter/material.dart';

class LoginController extends ChangeNotifier {
  String username = '';
  String password = '';
  bool showPassword = false;

  void setUsername(String value) {
    username = value;
    notifyListeners();
  }

  void setPassword(String value) {
    password = value;
    notifyListeners();
  }

  void toggleShowPassword() {
    showPassword = !showPassword;
    notifyListeners();
  }

  Future<void> login() async {
    debugPrint('Tentativa de login com o usuário: $username');
  }

}
