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
  /// Configuração de onde veio a credencial e para onde ela pode ir.
  final ApiConfig config;

  final String _brapiHost;

  /// Declara o interceptor, memorizando o host da brapi a partir de
  /// `config.brapiBaseUrl` — é a comparação que restringe o envio do token.
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
  /// Teto de requisições em voo. As excedentes esperam em fila FIFO.
  final int maxConcurrent;

  int _inFlight = 0;
  final _queue = <Completer<void>>[];

  /// Declara o limitador.
  ///
  /// - [maxConcurrent]: teto de concorrência. Padrão `4`, escolhido por conter
  ///   a rajada de montagem de carteira sem serializar tudo.
  ///
  /// **A fila não tem teto nem tempo limite**: requisições esperam
  /// indefinidamente por uma vaga. Aceitável porque o número de chamadas por
  /// interação é limitado pelo teto de 15 ativos da carteira.
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
  /// Cliente usado para reemitir a requisição. É a mesma instância que hospeda
  /// este interceptor, o que faz a repetição atravessar a cadeia inteira de
  /// novo — inclusive o limitador de concorrência.
  final Dio dio;

  /// Total de tentativas, contando a original. `3` significa duas repetições.
  final int maxAttempts;

  /// Base da espera exponencial.
  final Duration baseDelay;

  final math.Random _random;

  /// Declara o repetidor.
  ///
  /// - [dio]: cliente que reemite.
  /// - [maxAttempts]: tentativas no total. Padrão `3`.
  /// - [baseDelay]: base do teto exponencial. Padrão 500 ms.
  /// - [random]: gerador injetável, para tornar o teste determinístico.
  ///
  /// Repete apenas o que pode melhorar sozinho: `429`, `5xx` e falhas de
  /// conexão ou tempo esgotado. `4xx` de cliente não é repetido — repetir uma
  /// credencial inválida só multiplica a falha.
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
  ///
  /// - [attempt]: número da tentativa já consumida, a partir de zero.
  ///
  /// O jitter é **completo**, não parcial: o sorteio vai de zero ao teto, e não
  /// de metade do teto ao teto. É o que descorrelaciona por inteiro rajadas que
  /// falharam juntas.
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
  /// Chave geral do log. Desligado por padrão — em produção não se registra
  /// tráfego.
  final bool enabled;

  /// Destino das mensagens. Padrão `print`.
  final LogSink sink;

  /// Declara o log sanitizado.
  ///
  /// - [enabled]: liga o registro. Padrão `false`.
  /// - [sink]: destino. Sem ele, `print`.
  SanitizedLogInterceptor({this.enabled = false, LogSink? sink})
      : sink = sink ?? print;

  static final _tokenPattern = RegExp(r'([?&]token=)[^&]+', caseSensitive: false);

  /// Mascara o valor de um parâmetro `token=` na URL.
  ///
  /// - [input]: texto a limpar, tipicamente uma URL.
  ///
  /// **Cobre apenas o token em parâmetro de consulta.** O header
  /// `Authorization` nunca é registrado porque este interceptor não imprime
  /// headers — não porque esta função o remova. Ao acrescentar registro de
  /// headers, mascare-os aqui antes.
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
