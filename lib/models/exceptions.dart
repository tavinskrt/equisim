/// Exceção base para a aplicação
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Erro de conexão com a API
class NetworkException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  NetworkException({
    this.message = 'Erro de conexão com a API',
    this.code = 'NETWORK_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Erro de autenticação (API KEY inválida, etc)
class AuthenticationException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  AuthenticationException({
    this.message = 'Erro de autenticação. Verifique sua API KEY',
    this.code = 'AUTH_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Erro 404 - Recurso não encontrado
class NotFoundException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  NotFoundException({
    this.message = 'Ticker não encontrado',
    this.code = 'NOT_FOUND',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Erro de validação de dados
class ValidationException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  ValidationException({
    required this.message,
    this.code = 'VALIDATION_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Erro genérico de servidor
class ServerException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  ServerException({
    this.message = 'Erro no servidor. Tente novamente mais tarde',
    this.code = 'SERVER_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Timeout na requisição
class TimeoutException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  TimeoutException({
    this.message = 'A requisição demorou muito tempo. Tente novamente',
    this.code = 'TIMEOUT_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}
