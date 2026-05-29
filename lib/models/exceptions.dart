/// Exceção base da aplicação Equisim.
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

/// Exceção lançada ao ocorrer uma falha de conexão de rede ou indisponibilidade de internet.
class NetworkException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  NetworkException({
    this.message = 'Erro de conexão com o servidor. Verifique sua conexão.',
    this.code = 'NETWORK_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Exceção de autenticação lançada em casos de credenciais inválidas ou chave de API não configurada.
class AuthenticationException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  AuthenticationException({
    this.message = 'Erro de autenticação. Verifique as configurações de chave da sua API.',
    this.code = 'AUTH_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Exceção disparada caso o recurso solicitado não seja encontrado (HTTP 404).
class NotFoundException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  NotFoundException({
    this.message = 'Recurso ou ticker de ativo não encontrado.',
    this.code = 'NOT_FOUND',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Exceção gerada devido a incoerências ou inconsistências nos dados de entrada.
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

/// Exceção genérica de falha interna ou indisponibilidade temporária do servidor.
class ServerException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  ServerException({
    this.message = 'Erro interno do servidor Bolsai. Tente novamente mais tarde.',
    this.code = 'SERVER_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Exceção lançada quando a requisição excede o tempo limite estabelecido de resposta.
class TimeoutException implements AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final dynamic originalError;

  TimeoutException({
    this.message = 'A requisição demorou muito tempo para responder. Tente novamente.',
    this.code = 'TIMEOUT_ERROR',
    this.originalError,
  });

  @override
  String toString() => message;
}
