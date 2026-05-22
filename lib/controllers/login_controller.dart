import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'theme_controller.dart';

class LoginController extends ChangeNotifier {
  String email = '';
  String password = '';
  bool showPassword = false;
  bool isLoading = false;

  void setEmail(String value) {
    email = value.trim();
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

  Future<String?> login(BuildContext context) async {
    if (email.isEmpty || password.isEmpty) {
      return 'Preencha todos os campos.';
    }

    isLoading = true;
    notifyListeners();

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Sync theme se o widget ainda estiver montado
      if (context.mounted && userCredential.user != null) {
        // Obter ThemeController (sem dar throw)
        final themeController = Provider.of<ThemeController>(context, listen: false);
        await themeController.syncWithFirebase(userCredential.user!.uid);
      }

      isLoading = false;
      notifyListeners();
      return null; // Sucesso
    } on FirebaseAuthException catch (e) {
      isLoading = false;
      notifyListeners();
      if (e.code == 'user-not-found') {
        return 'Nenhum usuário encontrado para esse e-mail.';
      } else if (e.code == 'wrong-password') {
        return 'Senha incorreta fornecida para esse usuário.';
      } else if (e.code == 'invalid-credential') {
        return 'Credenciais inválidas.';
      } else if (e.code == 'invalid-email') {
        return 'O formato do e-mail é inválido.';
      }
      return 'Erro na autenticação: ${e.message}';
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return 'Erro inesperado: $e';
    }
  }
}
