import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'interceptors.dart';

/// Cliente HTTP das APIs externas.
///
/// As respostas chegam como texto e são desserializadas **fora da isolate de
/// interface**: um histórico de 10 anos para 10 ativos traz ~25 mil pontos, e
/// `jsonDecode` desse volume na thread principal derruba frames. Medição da
/// Fase 0 mostrou que este é o único gargalo real de CPU do sistema — o motor
/// financeiro roda em 0,14 ms, a rede leva 3,5 s e o parse fica no meio.
class ApiClient {
  final Dio _dio;
  final ApiConfig config;

  ApiClient._(this._dio, this.config);

  factory ApiClient(ApiConfig config, {Dio? dio}) {
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 40),
          // Texto puro: a desserialização é nossa, em outra isolate.
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ));

    client.interceptors.addAll([
      AuthInterceptor(config),
      ThrottleInterceptor(),
      RetryInterceptor(dio: client),
      SanitizedLogInterceptor(),
    ]);

    return ApiClient._(client, config);
  }

  Dio get raw => _dio;

  /// GET que devolve JSON já desserializado.
  ///
  /// [heavy] indica payloads grandes, que vão para outra isolate. Em `compute`
  /// o alvo web executa em linha (não há threads), o que é aceitável: lá o
  /// gargalo é a rede, não o parse.
  Future<Result<dynamic>> getJson(
    String url, {
    Map<String, dynamic>? query,
    bool heavy = false,
  }) async {
    try {
      final response = await _dio.get<String>(url, queryParameters: query);
      final status = response.statusCode ?? 0;
      final body = response.data ?? '';

      if (status != 200) {
        return Err(_failureFor(status, body));
      }
      if (body.isEmpty) {
        return const Err(InsufficientData('Resposta vazia da API.'));
      }

      final decoded =
          heavy ? await compute(_decode, body) : _decode(body);
      return Ok(decoded);
    } on DioException catch (e) {
      return Err(_failureForDio(e));
    } on FormatException catch (e) {
      return Err(ComputationFailure('Resposta não é JSON válido: ${e.message}'));
    }
  }

  static dynamic _decode(String body) => jsonDecode(body);

  Failure _failureFor(int status, String body) => switch (status) {
        401 || 403 => const InvalidInput(
            'Credencial da brapi inválida, ausente ou sem permissão para este '
            'recurso.',
          ),
        404 || 422 => const InsufficientData('Ativo não encontrado na fonte.'),
        429 => const DataQualityFailure(
            'Limite de requisições excedido. As tentativas automáticas se '
            'esgotaram; aguarde antes de repetir.',
          ),
        400 => InvalidInput('Requisição rejeitada pela API: ${_trim(body)}'),
        _ => ComputationFailure('HTTP $status: ${_trim(body)}'),
      };

  Failure _failureForDio(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          const InsufficientData(
            'A fonte de dados demorou demais para responder.',
          ),
        DioExceptionType.connectionError => const InsufficientData(
            'Sem conexão com a fonte de dados.',
          ),
        _ => ComputationFailure('Falha de rede: ${e.message ?? e.type.name}'),
      };

  static String _trim(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;

  void close() => _dio.close(force: true);
}
