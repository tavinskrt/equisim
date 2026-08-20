import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/network/interceptors.dart';
import 'package:equisim/data/quality/dividend_quality_gate.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthInterceptor', () {
    RequestOptions runWith(ApiConfig config) {
      final options = RequestOptions(path: '/v2/stocks/quote');
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

  group('Portão de qualidade de proventos', () {
    final asOf = DateTime(2026, 8, 19);
    final ticker = Ticker.parse('BBAS3');

    List<DividendEvent> eventsTotalling(double total) => [
          DividendEvent(
            ticker: ticker,
            exDate: DateTime(2026, 3, 1),
            paymentDate: DateTime(2026, 3, 15),
            amountPerShare: total,
            kind: DividendKind.jcp,
          ),
        ];

    test('aprova quando o DY calculado bate com o publicado', () {
      // R$ 0,551 sobre R$ 18,08 = 3,05%; a fonte publica 3,00%.
      final report = DividendQualityGate.check(
        ticker: ticker,
        events: eventsTotalling(0.551),
        currentPrice: 18.08,
        publishedYield: 0.03,
        asOf: asOf,
      );
      expect(report.status, DividendQuality.consistent);
      expect(report.isTrustworthy, isTrue);
      expect(report.computedYield, closeTo(0.0305, 1e-3));
    });

    test('sinaliza divergência em vez de reportar número errado', () {
      final report = DividendQualityGate.check(
        ticker: ticker,
        events: eventsTotalling(2.0), // muito acima do real
        currentPrice: 18.08,
        publishedYield: 0.03,
        asOf: asOf,
      );
      expect(report.status, DividendQuality.divergent);
      expect(report.isTrustworthy, isFalse);
      expect(report.message, contains('diverge'));
    });

    test('sem DY publicado, o resultado é não verificado — não aprovado', () {
      final report = DividendQualityGate.check(
        ticker: ticker,
        events: eventsTotalling(0.551),
        currentPrice: 18.08,
        publishedYield: null,
        asOf: asOf,
      );
      expect(report.status, DividendQuality.unverified);
    });

    test('a janela de 12 meses ignora eventos antigos', () {
      final events = [
        DividendEvent(
          ticker: ticker,
          exDate: DateTime(2026, 3, 1),
          paymentDate: DateTime(2026, 3, 15),
          amountPerShare: 0.5,
          kind: DividendKind.jcp,
        ),
        DividendEvent(
          ticker: ticker,
          exDate: DateTime(2020, 3, 1),
          paymentDate: DateTime(2020, 3, 15),
          amountPerShare: 9.0,
          kind: DividendKind.jcp,
        ),
      ];
      expect(
        DividendQualityGate.trailingTwelveMonths(events, asOf),
        closeTo(0.5, 1e-9),
      );
    });

    test('a tolerância acomoda o arredondamento da fonte', () {
      // A fonte publica dividendYield com duas casas (0,03 · 0,06 · 0,08),
      // então casar além de ~1 p.p. é impossível por construção.
      final report = DividendQualityGate.check(
        ticker: ticker,
        events: eventsTotalling(0.72), // 3,98%
        currentPrice: 18.08,
        publishedYield: 0.03,
        asOf: asOf,
      );
      expect(report.status, DividendQuality.consistent);
    });
  });
}
