import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controlador responsável pelo fluxo de alteração de senha do usuário.
/// 
/// Ele faz a correspondência com a lógica definida no componente `ChangePassword.tsx`,
/// contendo a validação de força da nova senha, o checklist de critérios de segurança,
/// a reautenticação necessária e a transição para a tela de sucesso.
class ChangePasswordController extends ChangeNotifier {
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';

  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  bool _isLoading = false;
  bool _success = false;
  String? _errorMessage;

  // Getters para a interface
  String get currentPassword => _currentPassword;
  String get newPassword => _newPassword;
  String get confirmPassword => _confirmPassword;
  bool get showCurrentPassword => _showCurrentPassword;
  bool get showNewPassword => _showNewPassword;
  bool get showConfirmPassword => _showConfirmPassword;
  bool get isLoading => _isLoading;
  bool get success => _success;
  String? get errorMessage => _errorMessage;

  /// Atualiza a senha atual no formulário.
  void setCurrentPassword(String value) {
    _currentPassword = value;
    notifyListeners();
  }

  /// Atualiza a nova senha no formulário.
  void setNewPassword(String value) {
    _newPassword = value;
    notifyListeners();
  }

  /// Atualiza a confirmação da nova senha no formulário.
  void setConfirmPassword(String value) {
    _confirmPassword = value;
    notifyListeners();
  }

  /// Alterna a visibilidade do campo de senha atual.
  void toggleShowCurrentPassword() {
    _showCurrentPassword = !_showCurrentPassword;
    notifyListeners();
  }

  /// Alterna a visibilidade do campo de nova senha.
  void toggleShowNewPassword() {
    _showNewPassword = !_showNewPassword;
    notifyListeners();
  }

  /// Alterna a visibilidade do campo de confirmação da nova senha.
  void toggleShowConfirmPassword() {
    _showConfirmPassword = !_showConfirmPassword;
    notifyListeners();
  }

  /// Define o estado de sucesso da operação e limpa o formulário caso seja redefinido para false.
  void setSuccess(bool value) {
    _success = value;
    if (!value) {
      _currentPassword = '';
      _newPassword = '';
      _confirmPassword = '';
      _errorMessage = null;
    }
    notifyListeners();
  }

  /// Calcula dinamicamente o nível de segurança da nova senha digitada.
  /// 
  /// Segue a lógica e cores da função `strength` do componente React:
  /// - Vazio: nível 0, transparente
  /// - Menor que 6 caracteres: nível 1, "Fraca", vermelho `#EF4444`
  /// - Menor que 10 caracteres ou sem números: nível 2, "Média", laranja `#F59E0B`
  /// - Sem caracteres especiais: nível 3, "Boa", azul `#3B82F6`
  /// - Tudo atendido: nível 4, "Forte", verde `#00B37E`
  Map<String, dynamic> get passwordStrength {
    final pass = _newPassword;
    if (pass.isEmpty) {
      return {'level': 0, 'label': '', 'color': Colors.transparent};
    }
    if (pass.length < 6) {
      return {'level': 1, 'label': 'Fraca', 'color': const Color(0xFFEF4444)};
    }

    final hasDigit = pass.contains(RegExp(r'[0-9]'));
    if (pass.length < 10 || !hasDigit) {
      return {'level': 2, 'label': 'Média', 'color': const Color(0xFFF59E0B)};
    }

    final hasSpecial = pass.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    if (!hasSpecial) {
      return {'level': 3, 'label': 'Boa', 'color': const Color(0xFF3B82F6)};
    }

    return {'level': 4, 'label': 'Forte', 'color': const Color(0xFF00B37E)};
  }

  // Métodos de checagem do checklist de requisitos
  bool get metLength => _newPassword.length >= 8;
  bool get metNumber => _newPassword.contains(RegExp(r'[0-9]'));
  bool get metUppercase => _newPassword.contains(RegExp(r'[A-Z]'));
  bool get metSymbol => _newPassword.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  /// Checa se a confirmação coincide com a nova senha digitada.
  bool get passwordsMatch => _confirmPassword.isNotEmpty && _newPassword == _confirmPassword;

  /// Retorna se o formulário está preenchido e atende aos critérios mínimos de envio.
  bool get canSubmit {
    final str = passwordStrength;
    final level = str['level'] as int;
    return _currentPassword.length >= 6 && level >= 2 && passwordsMatch;
  }

  /// Processa a reautenticação do usuário e altera sua senha no Firebase Auth.
  Future<bool> changePassword() async {
    if (!canSubmit) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _errorMessage = 'Usuário não está autenticado no momento.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final email = user.email;
      if (email == null) {
        _errorMessage = 'E-mail do usuário não pôde ser localizado.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Reautentica o usuário com a senha atual (exigência do Firebase para troca de dados sensíveis)
      final credential = EmailAuthProvider.credential(email: email, password: _currentPassword);
      await user.reauthenticateWithCredential(credential);

      // Altera a senha
      await user.updatePassword(_newPassword);

      _isLoading = false;
      _success = true;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      if (e.code == 'wrong-password') {
        _errorMessage = 'A senha atual fornecida está incorreta.';
      } else if (e.code == 'requires-recent-login') {
        _errorMessage = 'Para realizar esta ação sensível, é necessário fazer login novamente.';
      } else if (e.code == 'weak-password') {
        _errorMessage = 'A nova senha informada é considerada muito fraca pelo servidor.';
      } else {
        _errorMessage = 'Erro do Firebase: ${e.message}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Ocorreu um erro inesperado: $e';
      notifyListeners();
      return false;
    }
  }
}
