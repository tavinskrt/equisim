import 'package:flutter/material.dart';

/// Classe base para todos os controladores
/// Fornece gerenciamento de estado comum e notificação de mudanças
abstract class BaseController extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Define o estado de carregamento
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Define uma mensagem de erro
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Limpa o estado de erro
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
