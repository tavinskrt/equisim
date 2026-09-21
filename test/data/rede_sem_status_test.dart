import 'package:dio/dio.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/datasources/remote/bcb_datasource.dart';
import 'package:equisim/data/datasources/remote/tesouro_datasource.dart';
import 'package:equisim/data/network/api_client.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_adapter.dart';

/// Falha de rede **sem status HTTP** nas fontes de taxa — lente `risco`,
/// 21/09/2026.
///
/// O grupo equivalente do `BrapiDatasource` existe desde a rodada que o abriu;
/// o BCB e o Tesouro ficaram sem ele. **Eles são os fornecedores das taxas do
/// DCF e do backtest**: exceção crua atravessando a camada de dados quebraria o
/// contrato `Result` inteiro, e uma conexão que cai não tem status nenhum —
/// `DioException.response` é nulo, e nenhum dos testes de status o exercita.
///
/// A captura mora no `ApiClient` (`on DioException`), e é ela que este arquivo
/// cobra: **a garantia é central, e a cobertura precisa ser de cada fonte**,
/// porque quem acrescentar uma quarta fonte amanhã pode não passar por lá.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiClient cliente(FixtureAdapter adapter) {
    final dio = Dio(BaseOptions(
      responseType: ResponseType.plain,
      validateStatus: ApiClient.acceptsStatus,
    ));
    dio.httpClientAdapter = adapter;
    return ApiClient(
      ApiConfig(
        mode: BrapiMode.direct,
        brapiBaseUrl: 'https://brapi.dev/api',
        bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
      ),
      dio: dio,
    );
  }

  const tipos = [
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.unknown,
  ];

  group('BcbDatasource — falha sem resposta do servidor', () {
    for (final tipo in tipos) {
      test('${tipo.name} vira Result.err, e não exceção', () async {
        final fonte = BcbDatasource(cliente(FixtureAdapter(
          transportErrors: {'bcdata.sgs': tipo},
        )));
        final r = await fonte.series(
          BcbDatasource.seriesCdiDaily,
          DateRange(DateTime(2024, 1, 1), DateTime(2024, 12, 31)),
        );
        expect(r.isErr, isTrue, reason: '$tipo deveria virar Result.err');
        expect(r.failureOrNull, isNotNull);
      });
    }
  });

  group('TesouroDatasource — falha sem resposta do servidor', () {
    for (final tipo in tipos) {
      test('${tipo.name} vira Result.err, e não exceção', () async {
        final fonte = TesouroDatasource(cliente(FixtureAdapter(
          transportErrors: {'package_show': tipo},
        )));
        final r = await fonte.latest();
        expect(r.isErr, isTrue, reason: '$tipo deveria virar Result.err');
        expect(r.failureOrNull, isNotNull);
      });
    }

    test('a queda no CSV, depois do catálogo, também não escapa', () async {
      // **Duas chamadas, dois caminhos.** O catálogo responde e o arquivo cai:
      // é o caso que um teste só do primeiro salto não pega.
      final fonte = TesouroDatasource(cliente(FixtureAdapter(
        bodies: {'package_show': _catalogo},
        transportErrors: {
          'precotaxatesourodireto.csv': DioExceptionType.connectionError,
        },
      )));
      final r = await fonte.latest();
      expect(r.isErr, isTrue);
      expect(r.failureOrNull, isNotNull);
    });
  });
}

const _catalogo = '''
{"result":{"resources":[
  {"format":"CSV","url":"https://exemplo.gov.br/precotaxatesourodireto.csv"}
]}}''';
