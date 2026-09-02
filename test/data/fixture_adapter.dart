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

  /// Corpo JSON **literal** por trecho de URL, respondido com status 200.
  ///
  /// Existe para o que fixture gravada não consegue exercitar: payload
  /// deliberadamente corrompido — preço negativo, data fora de ordem, campo
  /// ausente. Gravar isso como arquivo daria a impressão de ser resposta real
  /// da fonte, que é o oposto do que o teste quer dizer.
  final Map<String, String> bodies;

  /// Status por tentativa, na ordem, para um mesmo trecho de URL.
  ///
  /// A chamada `n` recebe o `n`-ésimo status; esgotada a lista, repete o
  /// último. É o que permite provar a **repetição de verdade**: `[429, 200]`
  /// só devolve o corpo bom se o cliente tiver reemitido a requisição.
  final Map<String, List<int>> statusSequence;

  /// Falha de transporte por trecho de URL — tempo esgotado, conexão perdida.
  ///
  /// Diferente de [failures]: ali há resposta com status; aqui não há resposta
  /// nenhuma, que é o caso em que `DioException.response` é nulo.
  final Map<String, DioExceptionType> transportErrors;

  /// Quantas vezes cada rota foi chamada — permite verificar que o cache
  /// realmente evitou a segunda ida à rede.
  final Map<String, int> callCount = {};

  FixtureAdapter({
    this.routes = const {},
    this.failures = const {},
    this.bodies = const {},
    this.statusSequence = const {},
    this.transportErrors = const {},
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();

    for (final entry in transportErrors.entries) {
      if (url.contains(entry.key)) {
        callCount[entry.key] = (callCount[entry.key] ?? 0) + 1;
        throw DioException(
          requestOptions: options,
          type: entry.value,
          error: 'falha de transporte forçada',
        );
      }
    }

    for (final entry in statusSequence.entries) {
      if (!url.contains(entry.key)) continue;
      final attempt = callCount[entry.key] ?? 0;
      callCount[entry.key] = attempt + 1;
      final statuses = entry.value;
      final status =
          statuses.isEmpty ? 200 : statuses[attempt.clamp(0, statuses.length - 1)];
      if (status != 200) {
        return ResponseBody.fromString(
          '{"error":"status $status na tentativa ${attempt + 1}"}',
          status,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString(
        _bodyFor(entry.key),
        200,
        headers: _jsonHeaders,
      );
    }

    for (final entry in bodies.entries) {
      if (url.contains(entry.key)) {
        callCount[entry.key] = (callCount[entry.key] ?? 0) + 1;
        return ResponseBody.fromString(entry.value, 200, headers: _jsonHeaders);
      }
    }

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

  /// Corpo de sucesso de uma rota em sequência: o literal, se houver, senão a
  /// fixture gravada.
  String _bodyFor(String route) {
    final literal = bodies[route];
    if (literal != null) return literal;
    final name = routes[route];
    if (name == null) {
      throw StateError('Rota $route em sequência sem corpo nem fixture.');
    }
    final file = File('test/fixtures/$name.json');
    if (!file.existsSync()) {
      throw StateError('Fixture ausente: ${file.path}');
    }
    return file.readAsStringSync();
  }

  static const _jsonHeaders = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  void close({bool force = false}) {}
}
