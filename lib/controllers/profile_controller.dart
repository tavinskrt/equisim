import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Controlador responsável por gerenciar as informações do perfil do usuário,
/// controle de edição in-line de campos e exclusão de conta no Firebase Auth.
/// 
/// Corresponde ao estado gerenciado no componente `MyProfile.tsx`.
class ProfileController extends ChangeNotifier {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  String _username = '';
  String _email = '';
  bool _editingName = false;
  bool _editingEmail = false;
  bool _isLoading = false;
  bool _savedSuccess = false;
  String? _errorMessage;

  /// Inicializa o controlador carregando os dados do usuário autenticado.
  ProfileController() {
    _initializeFields();
  }

  void _initializeFields() {
    if (_currentUser != null) {
      _username = _currentUser.displayName ?? '';
      _email = _currentUser.email ?? '';
    }
  }

  // Getters para a interface
  String get username => _username;
  String get email => _email;
  bool get editingName => _editingName;
  bool get editingEmail => _editingEmail;
  bool get isLoading => _isLoading;
  bool get savedSuccess => _savedSuccess;
  String? get errorMessage => _errorMessage;

  /// Atualiza o nome de usuário localmente.
  void setUsername(String value) {
    _username = value;
    notifyListeners();
  }

  /// Atualiza o e-mail localmente.
  void setEmail(String value) {
    _email = value.trim();
    notifyListeners();
  }

  /// Habilita ou desabilita o modo de edição do nome.
  /// 
  /// Se desabilitado, reverte o valor local para o displayName original do usuário.
  void setEditingName(bool value) {
    _editingName = value;
    if (!value) {
      _username = _currentUser?.displayName ?? '';
    }
    notifyListeners();
  }

  /// Habilita ou desabilita o modo de edição do e-mail.
  /// 
  /// Se desabilitado, reverte o valor local para o e-mail original do usuário.
  void setEditingEmail(bool value) {
    _editingEmail = value;
    if (!value) {
      _email = _currentUser?.email ?? '';
    }
    notifyListeners();
  }

  /// Salva as edições do formulário no Firebase Auth.
  /// 
  /// Retorna [true] se bem-sucedido ou [false] se ocorrer alguma validação ou falha.
  Future<bool> saveChanges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _errorMessage = 'Usuário não autenticado no sistema.';
      notifyListeners();
      return false;
    }

    if (_username.trim().isEmpty) {
      _errorMessage = 'O nome de usuário não pode estar vazio.';
      notifyListeners();
      return false;
    }

    if (_email.trim().isEmpty) {
      _errorMessage = 'O e-mail não pode estar vazio.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _savedSuccess = false;
    notifyListeners();

    try {
      // 1. Atualiza o display name se foi modificado
      if (_username != user.displayName) {
        await user.updateDisplayName(_username);
      }

      // 2. Atualiza o e-mail com verificação se foi modificado
      if (_email != user.email) {
        await user.verifyBeforeUpdateEmail(_email);
      }

      // Recarrega as informações do usuário atualizadas
      await user.reload();

      _editingName = false;
      _editingEmail = false;
      _isLoading = false;
      _savedSuccess = true;
      notifyListeners();

      // Esconde o toast de sucesso após 2.5 segundos (equivalente a setTimeout no React)
      Future.delayed(const Duration(milliseconds: 2500), () {
        _savedSuccess = false;
        notifyListeners();
      });

      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      if (e.code == 'requires-recent-login') {
        _errorMessage = 'Esta ação é sensível e exige login recente. Por segurança, faça logout e entre novamente para alterar seu e-mail.';
      } else if (e.code == 'email-already-in-use') {
        _errorMessage = 'Este endereço de e-mail já está em uso por outro usuário.';
      } else if (e.code == 'invalid-email') {
        _errorMessage = 'O formato de e-mail informado é inválido.';
      } else {
        _errorMessage = 'Falha no Firebase Auth: ${e.message}';
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

  /// Exclui a conta do usuário atual do Firebase Auth.
  /// 
  /// Retorna uma mensagem de erro caso falhe, ou [null] em caso de sucesso.
  Future<String?> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'Usuário não autenticado.';
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await user.delete();
      _isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e.code == 'requires-recent-login') {
        return 'Esta operação é sensível e exige autenticação recente. Faça logout e entre novamente para excluir sua conta.';
      }
      return 'Erro ao excluir conta: ${e.message}';
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Ocorreu um erro inesperado: $e';
    }
  }
}
