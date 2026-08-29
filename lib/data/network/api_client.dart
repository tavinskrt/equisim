import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equisim_core/equisim_core.dart';

import '../config/api_config.dart';
import 'interceptors.dart';

/// Desserializador de respostas grandes.
///
/// Injetável porque a estratégia certa depende do hospedeiro: o aplicativo
/// manda para outra isolate a fim de não derrubar quadros; o executor de
/// validação, que não tem interface, decodifica em linha.
typedef HeavyJsonDecoder = Future<dynamic> Function(String body);

Future<dynamic> _decodeInline(String body) async => jsonDecode(body);

/// Cliente HTTP das APIs externas.
///
/// As respostas chegam como texto e são desserializadas **fora da isolate de
/// interface**: um histórico de 10 anos para 10 ativos traz ~25 mil pontos, e
/// `jsonDecode` desse volume na thread principal derruba frames. Medição da
/// Fase 0 mostrou que este é o único gargalo real de CPU do sistema — o motor
/// financeiro roda em 0,14 ms, a rede leva 3,5 s e o parse fica no meio.
class ApiClient {
  final Dio _dio;

  /// Configuração de acesso — URLs base e credencial resolvida.
  final ApiConfig config;

  final HeavyJsonDecoder _decodeHeavy;

  ApiClient._(this._dio, this.config, this._decodeHeavy);

  /// Monta o cliente com a cadeia de interceptors do projeto.
  ///
  /// A ordem dos interceptors importa e é fixa: autenticação, limitação de
  /// taxa, repetição e, por último, log — de modo que o log registre a
  /// requisição como ela de fato saiu.
  ///
  /// - [config]: URLs e credencial.
  /// - [dio]: instância própria, para teste com adaptador de fixture. Sem ela,
  ///   cria uma com 20 s de conexão e 40 s de recepção, em `ResponseType.plain`
  ///   — o texto é desserializado por [HeavyJsonDecoder], não pelo Dio.
  /// - [heavyDecoder]: estratégia para payloads grandes. Padrão em linha; o
  ///   aplicativo injeta uma que usa outra isolate.
  /// - [logSink], [logRequests]: destino e chave do log sanitizado.
  ///
  /// `validateStatus` aceita tudo abaixo de 500: erros de cliente viram
  /// [Failure] tipada em [getJson] em vez de exceção.
  factory ApiClient(
    ApiConfig config, {
    Dio? dio,
    HeavyJsonDecoder? heavyDecoder,
    LogSink? logSink,
    bool logRequests = false,
  }) {
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
      SanitizedLogInterceptor(enabled: logRequests, sink: logSink),
    ]);

    return ApiClient._(client, config, heavyDecoder ?? _decodeInline);
  }

  /// A instância Dio subjacente, para quem precisa de acesso direto ao
  /// transporte. Escape hatch: usar isto contorna o tratamento de falha de
  /// [getJson].
  Dio get raw => _dio;

  /// GET que devolve JSON já desserializado.
  ///
  /// [heavy] indica payloads grandes, que vão para outra isolate. Em `compute`
  /// o alvo web executa em linha (não há threads), o que é aceitável: lá o
  /// gargalo é a rede, não o parse.
  ///
  /// - [url]: URL absoluta.
  /// - [query]: parâmetros de consulta.
  /// - [heavy]: encaminha a desserialização para [HeavyJsonDecoder].
  ///
  /// **Nunca lança** por falha de rede ou de protocolo: tudo vira [Failure].
  /// `401`/`403` viram [InvalidInput]; `404`/`422` e resposta vazia viram
  /// [InsufficientData]; `429` vira [DataQualityFailure] — a repetição
  /// automática já se esgotou nesse ponto; JSON malformado e demais status
  /// viram [ComputationFailure]. Tempo esgotado e ausência de conexão viram
  /// [InsufficientData], porque são condições transitórias e não defeito do
  /// dado.
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

      final decoded = heavy ? await _decodeHeavy(body) : jsonDecode(body);
      return Ok(decoded);
    } on DioException catch (e) {
      return Err(_failureForDio(e));
    } on FormatException catch (e) {
      return Err(ComputationFailure('Resposta não é JSON válido: ${e.message}'));
    }
  }

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

  /// Fecha o transporte, cancelando requisições em voo.
  void close() => _dio.close(force: true);
}
