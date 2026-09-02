import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/network/api_client.dart';
import 'package:equisim/data/network/interceptors.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_adapter.dart';

const _config = ApiConfig(
  mode: BrapiMode.direct,
  brapiBaseUrl: 'https://brapi.dev/api',
  brapiToken: 'token-de-teste',
  bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthInterceptor', () {
    RequestOptions runWith(ApiConfig config, {String? path}) {
      final options = RequestOptions(path: path ?? '/v2/stocks/quote');
      AuthInterceptor(config).onRequest(options, RequestInterceptorHandler());
      return options;
    }

    test('modo direto injeta o token', () {
      final options = runWith(const ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: 'https://brapi.dev/api',
        brapiToken: 'segredo',
        bcbBaseUrl: '',
      ));
      expect(options.headers['Authorization'], 'Bearer segredo');
    });

    test('modo proxy não envia credencial alguma', () {
      final options = runWith(const ApiConfig(
        mode: BrapiMode.proxied,
        brapiBaseUrl: 'https://proxy.exemplo/api',
        brapiToken: 'nunca-usado',
        bcbBaseUrl: '',
      ));
      expect(options.headers.containsKey('Authorization'), isFalse,
          reason: 'com proxy o token vive só no servidor');
    });

    test('não manda a credencial para host de terceiro', () {
      final options = runWith(
        const ApiConfig(
          mode: BrapiMode.direct,
          brapiBaseUrl: 'https://brapi.dev/api',
          brapiToken: 'segredo',
          bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
        ),
        path: 'https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados',
      );
      expect(options.headers.containsKey('Authorization'), isFalse,
          reason: 'o Banco Central não assina a brapi, e o cabeçalho extra '
              'reprova a verificação prévia do CORS no alvo web');
    });

    test('GET sem corpo não declara Content-Type', () {
      final options = runWith(const ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: 'https://brapi.dev/api',
        brapiToken: 'segredo',
        bcbBaseUrl: '',
      ));
      expect(options.headers.containsKey('Content-Type'), isFalse,
          reason: 'sem corpo o cabeçalho não descreve nada e ainda força o '
              'OPTIONS de verificação');
    });
  });

  group('RetryInterceptor — espaçamento exponencial com ruído', () {
    test('o teto da espera dobra a cada tentativa', () {
      final interceptor = RetryInterceptor(
        dio: Dio(),
        baseDelay: const Duration(milliseconds: 100),
        random: math.Random(1),
      );
      // Com jitter completo a espera é sorteada em [0, base·2ⁿ]; o que se
      // verifica é o teto, não o valor exato.
      for (var attempt = 0; attempt < 4; attempt++) {
        final ceiling = 100 * math.pow(2, attempt);
        for (var i = 0; i < 50; i++) {
          final delay = interceptor.delayFor(attempt);
          expect(delay.inMilliseconds, lessThanOrEqualTo(ceiling.toInt()));
          expect(delay.inMilliseconds, greaterThanOrEqualTo(0));
        }
      }
    });

    test('o ruído evita que chamadas simultâneas colidam de novo', () {
      final interceptor = RetryInterceptor(
        dio: Dio(),
        baseDelay: const Duration(milliseconds: 500),
        random: math.Random(7),
      );
      final delays = List.generate(20, (_) => interceptor.delayFor(2).inMilliseconds);
      expect(delays.toSet().length, greaterThan(1),
          reason: 'esperas idênticas recriariam a colisão que causou o 429');
    });
  });

  group('RetryInterceptor — a repetição de verdade', () {
    // O grupo acima prova a MATEMÁTICA da espera. Nada ali força uma
    // requisição bloqueada a ser reemitida — e falha de cálculo de atraso não
    // derruba o usuário, falha de não reenviar derruba. Estes testes exercitam
    // o caminho inteiro: status 429, exceção, `onError`, refetch.

    ApiClient clienteCom(FixtureAdapter adapter) {
      final dio = Dio(BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: ApiClient.acceptsStatus,
      ));
      dio.httpClientAdapter = adapter;
      return ApiClient(_config, dio: dio);
    }

    test('429 seguido de 200 é reemitido e devolve o corpo bom', () async {
      final adapter = FixtureAdapter(
        statusSequence: {'/teste': [429, 200]},
        bodies: {'/teste': '{"results":[{"ok":true}]}'},
      );

      final result =
          await clienteCom(adapter).getJson('https://brapi.dev/api/teste');

      expect(result.isOk, isTrue,
          reason: 'sem reemissão, o 429 viraria falha e o corpo bom se '
              'perderia');
      expect(adapter.callCount['/teste'], 2,
          reason: 'exatamente uma repetição: a primeira falhou, a segunda não');
    });

    test('429 insistente esgota as tentativas e vira falha de limite',
        () async {
      final adapter = FixtureAdapter(
        statusSequence: {'/teste': [429]},
        bodies: {'/teste': '{"results":[]}'},
      );

      final result =
          await clienteCom(adapter).getJson('https://brapi.dev/api/teste');

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<DataQualityFailure>(),
          reason: 'esgotada a repetição, o 429 tem mapeamento próprio');
      // `maxAttempts` é 3 no padrão do cliente: a original mais duas repetições.
      expect(adapter.callCount['/teste'], 3);
    });

    test('erro de cliente NÃO é repetido — repetir credencial má multiplica '
        'a falha', () async {
      final adapter = FixtureAdapter(
        statusSequence: {'/teste': [401, 200]},
        bodies: {'/teste': '{"results":[]}'},
      );

      final result =
          await clienteCom(adapter).getJson('https://brapi.dev/api/teste');

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InvalidInput>());
      expect(adapter.callCount['/teste'], 1);
    });

    test('falha de transporte é repetida como o 429', () async {
      // Sem status, mas transitória: é a outra metade de `_isRetryable`.
      final adapter = FixtureAdapter(
        transportErrors: {'/teste': DioExceptionType.connectionTimeout},
      );

      final result =
          await clienteCom(adapter).getJson('https://brapi.dev/api/teste');

      expect(result.isErr, isTrue);
      expect(adapter.callCount['/teste'], 3);
    });
  });

  group('SanitizedLogInterceptor', () {
    test('mascara token que apareça na query string', () {
      const url = 'https://brapi.dev/api/v2/quote?token=abc123XYZ&range=1d';
      expect(SanitizedLogInterceptor.sanitize(url), contains('token=****'));
      expect(SanitizedLogInterceptor.sanitize(url), isNot(contains('abc123XYZ')));
      expect(SanitizedLogInterceptor.sanitize(url), contains('range=1d'));
    });

    test('não altera URL sem credencial', () {
      const url = 'https://brapi.dev/api/v2/stocks/historical?symbols=PETR4';
      expect(SanitizedLogInterceptor.sanitize(url), url);
    });
  });

  group('ApiConfig', () {
    test('diagnóstico nunca revela o token completo', () {
      const config = ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: 'https://brapi.dev/api',
        brapiToken: 'wmvstKEWAuQa1Pex2BQXXb',
        bcbBaseUrl: '',
      );
      expect(config.diagnostics, isNot(contains('wmvstKEWAuQa1Pex2BQXXb')));
      expect(config.diagnostics, contains('****'));
    });

    test('modo proxy é considerado credenciado sem token local', () {
      const config = ApiConfig(
        mode: BrapiMode.proxied,
        brapiBaseUrl: 'https://proxy.exemplo',
        bcbBaseUrl: '',
      );
      expect(config.hasCredential, isTrue);
      expect(config.brapiToken, isNull);
    });
  });
}
