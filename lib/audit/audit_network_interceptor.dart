import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equisim_core/equisim_core.dart';

import '../data/network/interceptors.dart';

/// Registra cada ida à API como um evento de auditoria.
///
/// É a metade "payload bruto" do painel: o cálculo mostra a fórmula, e este
/// interceptador mostra de onde vieram os números que entraram nela. Sem ele, a
/// auditoria provaria que a conta está certa sem provar que os insumos são os
/// que a fonte devolveu.
///
/// **Custo zero quando desligado**: tudo aqui é guardado por
/// [AuditRecorder.isActive], que é `false` enquanto ninguém estiver ouvindo.
///
/// **Nada de credencial**: a URL passa pelo mesmo higienizador do log de
/// diagnóstico e os cabeçalhos de autorização não entram no payload. O painel é
/// feito para ser projetado numa tela durante a apresentação.
class AuditNetworkInterceptor extends Interceptor {
  static const String _startKey = 'audit_started_at';
  static const String _idKey = 'audit_transaction_id';

  /// Teto do trecho de resposta guardado no evento.
  ///
  /// O histórico de dez anos de dez ativos passa de dois megabytes. Guardar
  /// isso por requisição encheria o anel de memória e a mensagem entre abas
  /// para mostrar algo que ninguém lê rolando. Respostas menores que o teto
  /// entram desserializadas, e aí o visualizador mostra a árvore de verdade.
  static const int bodyPreviewLimit = 4000;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (AuditRecorder.isActive) {
      options.extra[_startKey] = DateTime.now();
      options.extra[_idKey] = AuditIds.uuidV4();
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _emit(
      response.requestOptions,
      status: response.statusCode,
      body: response.data,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _emit(
      err.requestOptions,
      status: err.response?.statusCode,
      body: err.response?.data,
      error: err.message ?? err.type.name,
    );
    handler.next(err);
  }

  void _emit(
    RequestOptions options, {
    int? status,
    Object? body,
    String? error,
  }) {
    if (!AuditRecorder.isActive) return;

    final startedAt = options.extra[_startKey];
    if (startedAt is! DateTime) return;

    final id = options.extra[_idKey];
    final elapsed = DateTime.now().difference(startedAt);

    AuditRecorder.emit(AuditEvent(
      transactionId: id is String ? id : AuditIds.uuidV4(),
      timestamp: startedAt,
      endpoint: options.uri.path,
      inputPayload: {
        'method': options.method,
        'url': SanitizedLogInterceptor.sanitize(options.uri.toString()),
        'queryParameters': {
          for (final entry in options.queryParameters.entries)
            entry.key: entry.key.toLowerCase() == 'token'
                ? '****'
                : '${entry.value}',
        },
        'retryAttempt': options.extra['retry_attempt'] ?? 0,
      },
      outputPayload: {
        'statusCode': status,
        'error': ?error,
        ..._describeBody(body),
      },
      executionTimeMs: elapsed.inMilliseconds,
    ));
  }

  Map<String, dynamic> _describeBody(Object? body) {
    if (body == null) return {'body': null};
    if (body is! String) return {'body': body};

    if (body.length <= bodyPreviewLimit) {
      try {
        return {'sizeBytes': body.length, 'body': jsonDecode(body)};
      } catch (_) {
        return {'sizeBytes': body.length, 'body': body};
      }
    }
    return {
      'sizeBytes': body.length,
      'truncated': true,
      'bodyPreview':
          '${body.substring(0, bodyPreviewLimit)}… [truncado: a resposta '
              'completa tem ${body.length} caracteres]',
    };
  }
}
