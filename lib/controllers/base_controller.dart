import 'package:flutter/material.dart';

/// Classe base abstrata para todos os controladores da aplicação.
/// Fornece o gerenciamento padronizado de estados de carregamento e erros.
abstract class BaseController extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Define o estado de processamento assíncrono (carregamento).
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Define uma mensagem ativa de erro para exibição na interface.
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Restaura o estado original, limpando quaisquer mensagens de erro ativas.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
