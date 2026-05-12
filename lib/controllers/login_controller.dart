import 'package:flutter/material.dart';

class LoginController extends ChangeNotifier {
  String email = '';
  String password = '';
  bool showPassword = false;

  void setEmail(String value) {
    email = value;
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
    debugPrint('Tentativa de login com o e-mail: $email');
  }

}
