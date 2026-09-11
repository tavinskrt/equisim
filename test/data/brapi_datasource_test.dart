import 'package:dio/dio.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/datasources/remote/bcb_datasource.dart';
import 'package:equisim/data/datasources/remote/brapi_datasource.dart';
import 'package:equisim/data/network/api_client.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_adapter.dart';

const _config = ApiConfig(
  mode: BrapiMode.direct,
  brapiBaseUrl: 'https://brapi.dev/api',
  brapiToken: 'token-de-teste',
  bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
);

ApiClient clientWith(FixtureAdapter adapter) {
  // `ApiClient.acceptsStatus`, e nao uma lambda propria: a politica precisa ser
  // a MESMA de producao. Enquanto era duplicada aqui, este cliente aceitava o
  // 429 como resposta normal e a repeticao automatica nunca era exercitada.
  final dio = Dio(BaseOptions(
    responseType: ResponseType.plain,
    validateStatus: ApiClient.acceptsStatus,
  ));
  dio.httpClientAdapter = adapter;
  return ApiClient(_config, dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrapiDatasource — cotações', () {
    test('lote devolve uma série por ativo solicitado', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      });
      final datasource = BrapiDatasource(clientWith(adapter));

      final result = await datasource.historicalBatch(
        [Ticker.parse('PETR4'), Ticker.parse('VALE3')],
      );

      expect(result.isOk, isTrue);
      final series = result.unwrap();
      expect(series.keys.map((t) => t.value).toSet(), {'PETR4', 'VALE3'});
      expect(series[Ticker.parse('PETR4')]!.points, isNotEmpty);
      // Uma única requisição para os dois ativos.
      expect(adapter.callCount['/v2/stocks/historical'], 1);
    });

    test('série vem ordenada e com preços positivos', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      })));

      final series = (await datasource.historicalBatch([Ticker.parse('PETR4')]))
          .unwrap()[Ticker.parse('PETR4')]!;

      for (var i = 1; i < series.points.length; i++) {
        expect(
          series.points[i].date.isAfter(series.points[i - 1].date),
          isTrue,
          reason: 'a série precisa estar em ordem cronológica',
        );
      }
      expect(series.points.every((p) => p.close > 0), isTrue);
    });

    test('epoch em segundos vira data sem horário', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_historical_batch',
      })));
      final series = (await datasource.historicalBatch([Ticker.parse('PETR4')]))
          .unwrap()[Ticker.parse('PETR4')]!;
      final first = series.points.first.date;
      expect(first.hour, 0);
      expect(first.minute, 0);
    });

    test('Ibovespa é carregado da mesma rota histórica', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/historical': 'brapi_ibovespa',
      })));
      final result = await datasource.ibovespa();
      expect(result.isOk, isTrue);
      expect(result.unwrap().points, isNotEmpty);
    });
  });

  group('BrapiDatasource — payload corrompido', () {
    // Fixture gravada é resposta BOA: testar higienização contra ela prova só
    // o formato do arquivo. O que a camada existe para filtrar precisa ser
    // injetado de propósito.

    test('descarta ponto com preço não positivo', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(bodies: {
        '/v2/stocks/historical': '''
{"results":[{"symbol":"PETR4","data":{"historicalDataPrice":[
  {"date":1704157200,"close":30.0},
  {"date":1704243600,"close":-5.0},
  {"date":1704330000,"close":0.0},
  {"date":1704416400,"close":31.5}
]}}]}''',
      })));

      final result = await datasource.historicalBatch([Ticker.parse('PETR4')]);
      final series = result.unwrap()[Ticker.parse('PETR4')]!;

      // Dois pontos sobrevivem; o negativo e o zero somem sem derrubar o lote.
      expect(series.points.length, 2);
      expect(series.points.every((p) => p.close > 0), isTrue);
    });

    test('reordena pontos que a fonte entrega fora de ordem', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(bodies: {
        '/v2/stocks/historical': '''
{"results":[{"symbol":"VALE3","data":{"historicalDataPrice":[
  {"date":1704416400,"close":31.5},
  {"date":1704157200,"close":30.0},
  {"date":1704330000,"close":31.0}
]}}]}''',
      })));

      final result = await datasource.historicalBatch([Ticker.parse('VALE3')]);
      final series = result.unwrap()[Ticker.parse('VALE3')]!;

      expect(series.points.length, 3);
      for (var i = 1; i < series.points.length; i++) {
        expect(
          series.points[i].date.isAfter(series.points[i - 1].date),
          isTrue,
          reason: 'a série precisa sair cronológica, venha como vier',
        );
      }
      // E a busca por data continua correta depois da reordenação.
      expect(series.closeAsOf(series.lastDate), 31.5);
    });

    test('ponto sem data ou sem fechamento é ignorado, não derruba o lote',
        () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(bodies: {
        '/v2/stocks/historical': '''
{"results":[{"symbol":"ITUB4","data":{"historicalDataPrice":[
  {"close":30.0},
  {"date":1704157200},
  {"date":1704243600,"close":"texto"},
  {"date":1704330000,"close":32.0}
]}}]}''',
      })));

      final result = await datasource.historicalBatch([Ticker.parse('ITUB4')]);
      expect(result.isOk, isTrue);
      expect(result.unwrap()[Ticker.parse('ITUB4')]!.points.length, 1);
    });

    test('ativo todo corrompido some do mapa sem levar o lote junto',
        () async {
      // Mapa parcial é o contrato do lote: um ativo ruim não pode derrubar os
      // outros, nem entrar como série vazia que o backtest aceitaria.
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(bodies: {
        '/v2/stocks/historical': '''
{"results":[
  {"symbol":"PETR4","data":{"historicalDataPrice":[
    {"date":1704157200,"close":-1.0},
    {"date":1704243600,"close":0.0}
  ]}},
  {"symbol":"VALE3","data":{"historicalDataPrice":[
    {"date":1704157200,"close":60.0}
  ]}}
]}''',
      })));

      final result = await datasource.historicalBatch(
        [Ticker.parse('PETR4'), Ticker.parse('VALE3')],
      );
      expect(result.isOk, isTrue);
      final map = result.unwrap();
      expect(map.containsKey(Ticker.parse('PETR4')), isFalse);
      expect(map[Ticker.parse('VALE3')]!.points.length, 1);
    });

    test('lote inteiro corrompido falha explicitamente, e não em silêncio',
        () async {
      // Sem nenhuma série utilizável, devolver mapa vazio faria o consumidor
      // tratar corrupção como "ativo sem histórico". O erro precisa ser dito.
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(bodies: {
        '/v2/stocks/historical': '''
{"results":[{"symbol":"PETR4","data":{"historicalDataPrice":[
  {"date":1704157200,"close":-1.0}
]}}]}''',
      })));

      final result = await datasource.historicalBatch([Ticker.parse('PETR4')]);
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InsufficientData>());
    });
  });

  group('BrapiDatasource — falha sem resposta do servidor', () {
    // O grupo de erro existente cobre status codificados (401, 404, 429). Uma
    // conexão que cai não tem status nenhum: `DioException.response` é nulo, e
    // era o caminho sem cobertura. Exceção crua atravessando a camada de dados
    // quebraria o contrato `Result` inteiro.

    Future<void> viraFalha(DioExceptionType tipo) async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        transportErrors: {'/v2/stocks/historical': tipo},
      )));
      final result = await datasource.historicalBatch([Ticker.parse('PETR4')]);
      expect(result.isErr, isTrue, reason: '$tipo deveria virar Result.err');
      expect(result.failureOrNull, isA<InsufficientData>());
    }

    test('tempo de conexão esgotado vira falha de domínio', () async {
      await viraFalha(DioExceptionType.connectionTimeout);
    });

    test('tempo de recepção esgotado vira falha de domínio', () async {
      await viraFalha(DioExceptionType.receiveTimeout);
    });

    test('conexão perdida vira falha de domínio', () async {
      await viraFalha(DioExceptionType.connectionError);
    });

    test('erro de transporte desconhecido também não escapa', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        transportErrors: {'/v2/stocks/historical': DioExceptionType.unknown},
      )));
      final result = await datasource.historicalBatch([Ticker.parse('PETR4')]);
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ComputationFailure>());
    });
  });

  group('BrapiDatasource — fundamentos', () {
    test('falha de UM demonstrativo reprova a busca inteira', () async {
      // Decisao 68. A versao anterior seguia com `continue` e devolvia Ok
      // desde que ALGUM dos quatro respondesse — produzindo serie com balanco
      // preenchido e resultado ausente, que e a forma que a decisao 52 trata
      // como "ausencia nao e zero". E o repositorio GRAVA o resultado no
      // cache, de modo que a corrupcao sobrevivia a falha de rede e era
      // preferida nas leituras seguintes.
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: {
          '/v2/stocks/statistics?symbols=PETR4&mode=history':
              'brapi_statistics_history_petr4',
          '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
          '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
          '/v2/stocks/statistics?symbols=PETR4&mode=current':
              'brapi_statistics_current_petr4',
        },
        failures: {'/v2/stocks/income-statement': 503},
      )));

      final r = await datasource.fundamentalsHistory(Ticker.parse('PETR4'));
      expect(r.isErr, isTrue,
          reason: 'sem a DRE, a serie nao descreve a empresa');
    });

    test('e o mesmo vale para falha de transporte', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: {
          '/v2/stocks/statistics?symbols=PETR4&mode=history':
              'brapi_statistics_history_petr4',
          '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
          '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
          '/v2/stocks/statistics?symbols=PETR4&mode=current':
              'brapi_statistics_current_petr4',
        },
        transportErrors: {
          '/v2/stocks/cash-flow': DioExceptionType.connectionTimeout,
        },
      )));

      final r = await datasource.fundamentalsHistory(Ticker.parse('PETR4'));
      expect(r.isErr, isTrue);
    });

    test('funde os quatro demonstrativos pela chave do exercício', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      })));

      final result =
          await datasource.fundamentalsHistory(Ticker.parse('PETR4'));
      expect(result.isOk, isTrue);

      final snapshots = result.unwrap();
      expect(snapshots.length, greaterThan(10),
          reason: 'a fonte entrega 16 exercícios anuais');

      // Um mesmo exercício precisa reunir campos de demonstrativos diferentes.
      final recent = snapshots.lastWhere(
        (s) => s.fiscalPeriodEnd.year >= 2023,
        orElse: () => snapshots.last,
      );
      expect(recent.totalRevenue, isNotNull, reason: 'DRE');
      expect(recent.operatingCashFlow, isNotNull, reason: 'DFC');
      expect(recent.cash, isNotNull, reason: 'Balanço');
    });

    test('deriva D&A, alíquota efetiva e dívida líquida', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      })));

      final snapshots =
          (await datasource.fundamentalsHistory(Ticker.parse('PETR4'))).unwrap();
      final withDerived = snapshots.where(
        (s) => s.depreciationAndAmortization != null,
      );
      expect(withDerived, isNotEmpty,
          reason: 'D&A = EBITDA − EBIT deve ser derivável em algum exercício');

      final withTax = snapshots.where((s) => s.effectiveTaxRate != null);
      expect(withTax, isNotEmpty);
      expect(withTax.every((s) => s.effectiveTaxRate! <= 0.5), isTrue,
          reason: 'a alíquota é limitada para conter exercícios atípicos');
    });

    test('exercícios saem em ordem cronológica', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/statistics?symbols=PETR4&mode=history':
            'brapi_statistics_history_petr4',
        '/v2/stocks/income-statement': 'brapi_income_statement_history_petr4',
        '/v2/stocks/balance-sheet': 'brapi_balance_sheet_history_petr4',
        '/v2/stocks/cash-flow': 'brapi_cash_flow_history_petr4',
        '/v2/stocks/statistics?symbols=PETR4&mode=current':
            'brapi_statistics_current_petr4',
      })));
      final snapshots =
          (await datasource.fundamentalsHistory(Ticker.parse('PETR4'))).unwrap();
      for (var i = 1; i < snapshots.length; i++) {
        expect(
          snapshots[i].fiscalPeriodEnd.isAfter(snapshots[i - 1].fiscalPeriodEnd),
          isTrue,
        );
      }
    });
  });

  group('BrapiDatasource — perfil e tickers', () {
    test('mapeia setor e indústria da taxonomia da fonte', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(routes: {
        '/v2/stocks/profile': 'brapi_profile_petr4',
      })));
      final asset = (await datasource.profile(Ticker.parse('PETR4'))).unwrap();
      expect(asset.sector.isUnknown, isFalse);
      expect(asset.sector.key, 'energia');
      expect(asset.industry, isNotNull);
    });

    test('resolve renomeação usando o parâmetro plural correto', () async {
      final adapter = FixtureAdapter(routes: {
        '/v2/tickers/resolve': 'brapi_resolve_viia3',
      });
      final datasource = BrapiDatasource(clientWith(adapter));

      final resolved = await datasource.resolve(Ticker.parse('VIIA3'));
      expect(resolved.isOk, isTrue);
      expect(resolved.unwrap()?.value, 'BHIA3');
    });
  });

  group('BcbDatasource', () {
    test('converte percentual diário em fração', () async {
      final datasource = BcbDatasource(clientWith(FixtureAdapter(routes: {
        'bcdata.sgs.12': 'bcb_cdi',
      })));

      final result = await datasource.cdi(
        DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)),
      );
      expect(result.isOk, isTrue);

      final series = result.unwrap();
      expect(series.rates, isNotEmpty);
      // 0,043739% ao dia → 0,00043739 em fração.
      expect(series.rates.first, closeTo(0.00043739, 1e-9));
      expect(series.rates.every((r) => r > 0 && r < 0.01), isTrue);
    });

    test('acumula e anualiza o CDI do período', () async {
      final datasource = BcbDatasource(clientWith(FixtureAdapter(routes: {
        'bcdata.sgs.12': 'bcb_cdi',
      })));
      final series = (await datasource.cdi(
        DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)),
      )).unwrap();

      expect(series.accumulated, greaterThan(0));
      // Um trimestre de CDI a ~10,6% a.a. anualiza para a mesma ordem.
      expect(series.annualized(), greaterThan(0.08));
      expect(series.annualized(), lessThan(0.16));
    });

    test('datas dd/MM/yyyy são interpretadas corretamente', () async {
      final datasource = BcbDatasource(clientWith(FixtureAdapter(routes: {
        'bcdata.sgs.12': 'bcb_cdi',
      })));
      final series = (await datasource.cdi(
        DateRange(DateTime(2024, 1, 1), DateTime(2024, 3, 31)),
      )).unwrap();
      expect(series.dates.first.year, 2024);
      expect(series.dates.first.month, 1);
    });
  });

  group('Tratamento de erro da API', () {
    test('401 vira falha de credencial, não exceção crua', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: const {},
        failures: {'/v2/stocks/profile': 401},
      )));
      final result = await datasource.profile(Ticker.parse('PETR4'));
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<InvalidInput>());
      expect(result.failureOrNull!.message, contains('Credencial'));
    });

    test('404 vira dado insuficiente', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: const {},
        failures: {'/v2/stocks/profile': 404},
      )));
      final result = await datasource.profile(Ticker.parse('XXXX3'));
      expect(result.failureOrNull, isA<InsufficientData>());
    });

    test('429 é reportado como limite de requisições', () async {
      final datasource = BrapiDatasource(clientWith(FixtureAdapter(
        routes: const {},
        failures: {'/v2/stocks/profile': 429},
      )));
      final result = await datasource.profile(Ticker.parse('PETR4'));
      expect(result.failureOrNull, isA<DataQualityFailure>());
    });
  });
}
