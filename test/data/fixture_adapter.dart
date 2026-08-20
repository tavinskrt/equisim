import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Adaptador de HTTP que responde a partir de arquivos gravados.
///
/// As fixtures são **respostas reais** da brapi e do Banco Central, capturadas
/// uma vez e versionadas. Isso dá aos testes as duas propriedades que faltavam
/// na suíte antiga: rodam offline e são determinísticos — a suíte anterior
/// batia na API de produção e falhava conforme o mercado mudava.
class FixtureAdapter implements HttpClientAdapter {
  /// Trechos de URL mapeados para o nome da fixture.
  final Map<String, String> routes;

  /// URLs que devem falhar, para exercitar o tratamento de erro.
  final Map<String, int> failures;

  /// Quantas vezes cada rota foi chamada — permite verificar que o cache
  /// realmente evitou a segunda ida à rede.
  final Map<String, int> callCount = {};

  FixtureAdapter({required this.routes, this.failures = const {}});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();

    for (final entry in failures.entries) {
      if (url.contains(entry.key)) {
        callCount[entry.key] = (callCount[entry.key] ?? 0) + 1;
        return ResponseBody.fromString('{"error":"forçado"}', entry.value,
            headers: _jsonHeaders);
      }
    }

    for (final entry in routes.entries) {
      if (url.contains(entry.key)) {
        callCount[entry.key] = (callCount[entry.key] ?? 0) + 1;
        final file = File('test/fixtures/${entry.value}.json');
        if (!file.existsSync()) {
          throw StateError('Fixture ausente: ${file.path}');
        }
        return ResponseBody.fromString(
          file.readAsStringSync(),
          200,
          headers: _jsonHeaders,
        );
      }
    }

    throw StateError('Nenhuma fixture registrada para $url');
  }

  static const _jsonHeaders = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  void close({bool force = false}) {}
}
