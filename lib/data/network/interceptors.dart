import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../config/api_config.dart';

/// Injeta a credencial quando o cliente fala direto com a brapi.
///
/// Em modo proxy nada é injetado: o token vive apenas no servidor.
///
/// A credencial vai **apenas para o host da brapi**. Mandá-la em toda
/// requisição entregaria o token da assinatura ao Banco Central — que não
/// pediu nada — e, no alvo web, quebraria a chamada: `Authorization` e
/// `Content-Type: application/json` não estão na lista segura do CORS, então
/// o navegador antecipa um `OPTIONS` de verificação. Verificado por `curl`:
/// o `GET` do SGS responde `access-control-allow-origin: *`, mas o `OPTIONS`
/// responde 200 **sem cabeçalho algum de CORS** — verificação reprovada, e o
/// `GET` real nunca sai. Era a origem dos `connectionError` em série no
/// console (três por chamada, uma por tentativa do [RetryInterceptor]).
class AuthInterceptor extends Interceptor {
  final ApiConfig config;
  final String _brapiHost;

  AuthInterceptor(this.config)
      : _brapiHost = Uri.parse(config.brapiBaseUrl).host;

  /// `true` quando a requisição vai para a brapi (ou para o proxy que a
  /// substitui). Caminho relativo só pode resolver contra a base configurada,
  /// portanto conta como destino próprio.
  bool _isOwnBackend(Uri uri) => uri.host.isEmpty || uri.host == _brapiHost;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = config.brapiToken;
    if (config.mode == BrapiMode.direct &&
        token != null &&
        _isOwnBackend(options.uri)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    // Só faz sentido declarar o tipo do corpo quando existe corpo. Num GET o
    // cabeçalho não descreve nada e ainda força a verificação prévia do CORS.
    if (options.data != null) {
      options.headers['Content-Type'] = 'application/json';
    }
    handler.next(options);
  }
}

/// Limita o número de requisições simultâneas.
///
/// A brapi **não expõe nenhum cabeçalho de rate limit** — verificado: nenhum
/// `X-RateLimit-*` nem `Retry-After`. Como o limite é inobservável, a
/// estratégia é conter a concorrência na origem em vez de reagir ao 429.
class ThrottleInterceptor extends Interceptor {
  final int maxConcurrent;
  int _inFlight = 0;
  final _queue = <Completer<void>>[];

  ThrottleInterceptor({this.maxConcurrent = 4});

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_inFlight >= maxConcurrent) {
      final completer = Completer<void>();
      _queue.add(completer);
      await completer.future;
    }
    _inFlight++;
    handler.next(options);
  }

  void _release() {
    _inFlight = math.max(0, _inFlight - 1);
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    }
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _release();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _release();
    handler.next(err);
  }
}

/// Repete requisições falhas com espaçamento exponencial e ruído aleatório.
///
/// O ruído (*jitter*) evita que várias chamadas disparadas juntas — o caso
/// normal ao montar uma carteira — voltem a colidir todas no mesmo instante
/// após a espera.
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxAttempts;
  final Duration baseDelay;
  final math.Random _random;

  RetryInterceptor({
    required this.dio,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    math.Random? random,
  }) : _random = random ?? math.Random();

  static const _attemptKey = 'retry_attempt';

  bool _isRetryable(DioException error) {
    final status = error.response?.statusCode;
    if (status == 429) return true;
    if (status != null && status >= 500 && status < 600) return true;
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError;
  }

  /// Espera exponencial com jitter completo: `random(0, base · 2^n)`.
  Duration delayFor(int attempt) {
    final ceiling = baseDelay.inMilliseconds * math.pow(2, attempt).toInt();
    return Duration(milliseconds: _random.nextInt(ceiling + 1));
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;

    if (!_isRetryable(err) || attempt >= maxAttempts - 1) {
      return handler.next(err);
    }

    await Future<void>.delayed(delayFor(attempt));

    final options = err.requestOptions;
    options.extra[_attemptKey] = attempt + 1;

    try {
      final response = await dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }
}

/// Destino das mensagens de diagnóstico.
typedef LogSink = void Function(String message);

/// Log de diagnóstico com credenciais mascaradas.
///
/// Nenhum header de autorização e nenhum parâmetro de token chega ao console:
/// logs vazam para relatórios de erro e capturas de tela.
class SanitizedLogInterceptor extends Interceptor {
  final bool enabled;
  final LogSink sink;

  SanitizedLogInterceptor({this.enabled = false, LogSink? sink})
      : sink = sink ?? print;

  static final _tokenPattern = RegExp(r'([?&]token=)[^&]+', caseSensitive: false);

  static String sanitize(String input) =>
      input.replaceAllMapped(_tokenPattern, (m) => '${m[1]}****');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      sink('→ ${options.method} ${sanitize(options.uri.toString())}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (enabled) {
      sink(
        '← ${response.statusCode} ${sanitize(response.requestOptions.uri.toString())}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      sink(
        '✖ ${err.response?.statusCode ?? err.type.name} '
        '${sanitize(err.requestOptions.uri.toString())}',
      );
    }
    handler.next(err);
  }
}
