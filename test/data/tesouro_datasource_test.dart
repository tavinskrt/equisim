import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/datasources/remote/tesouro_datasource.dart';
import 'package:equisim/data/network/api_client.dart';
import 'package:equisim/data/repositories/b3_registry_repository.dart';
import 'package:equisim/data/repositories/risk_free_curve_repository.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_adapter.dart';

ApiClient _cliente(FixtureAdapter adapter, {String? tesouroProxyUrl}) {
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
      tesouroProxyUrl: tesouroProxyUrl,
    ),
    dio: dio,
  );
}

const _catalogo = '''
{"result":{"resources":[
  {"format":"PDF","url":"https://exemplo.gov.br/taxa.pdf"},
  {"format":"CSV","url":"https://exemplo.gov.br/precotaxatesourodireto.csv"}
]}}''';

/// Cabeçalho, o dia mais recente — com um título que a curva não usa no meio
/// —, e o dia anterior, que a leitura não pode alcançar.
const _csv = 'Tipo Titulo;Data Vencimento;Data Base;Taxa Compra Manha;'
    'Taxa Venda Manha;PU Compra Manha;PU Venda Manha;PU Base Manha\n'
    'Tesouro Selic;01/03/2027;10/09/2026;0,00;0,01;19854,30;19843,06;19843,06\n'
    'Tesouro Prefixado;01/01/2027;10/09/2026;13,56;13,68;960,00;959,00;959,00\n'
    'Tesouro Prefixado;01/01/2029;10/09/2026;13,93;14,05;750,00;749,00;749,00\n'
    'Tesouro Prefixado com Juros Semestrais;01/01/2037;10/09/2026;14,33;14,45;900,00;899,00;899,00\n'
    'Tesouro Prefixado;01/01/2027;09/09/2026;99,99;99,99;1,00;1,00;1,00\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tesouro direto do arquivo — item A2.1', () {
    test('lê só o dia mais recente, e só os prefixados', () async {
      final fonte = TesouroDatasource(_cliente(FixtureAdapter(bodies: {
        'package_show': _catalogo,
        'precotaxatesourodireto.csv': _csv,
      })));
      final r = await fonte.latest();
      final cotacoes = r.unwrap();
      expect(cotacoes, hasLength(3));
      expect(cotacoes.map((q) => q.baseDate).toSet(), {DateTime.utc(2026, 9, 10)});
      expect(cotacoes.every((q) => q.rate < 0.2), isTrue,
          reason: 'a linha de 09/09, com 99,99%, não pode ter sido lida');
    });

    test('catálogo sem CSV é falha declarada', () async {
      final fonte = TesouroDatasource(_cliente(FixtureAdapter(bodies: {
        'package_show': '{"result":{"resources":[]}}',
      })));
      expect((await fonte.latest()).isErr, isTrue);
    });

    test('arquivo fora do ar é falha, e não lista vazia', () async {
      final fonte = TesouroDatasource(_cliente(FixtureAdapter(
        bodies: {'package_show': _catalogo},
        failures: {'precotaxatesourodireto.csv': 503},
      )));
      expect((await fonte.latest()).isErr, isTrue);
    });
  });

  group('Tesouro pela função de nuvem', () {
    test('com o endereço configurado, pergunta à função', () async {
      final corpo = jsonEncode(TreasuryQuotesCodec.encode([
        TreasuryQuote(
          type: TreasuryCurve.ltn,
          maturity: DateTime.utc(2027, 1, 1),
          baseDate: DateTime.utc(2026, 9, 10),
          rate: 0.1356,
        ),
      ], geradoEm: DateTime.utc(2026, 9, 10)));
      final adapter = FixtureAdapter(bodies: {'/tesouro': corpo});
      final fonte = TesouroDatasource(_cliente(adapter,
          tesouroProxyUrl: 'https://funcoes.exemplo/tesouro'));
      final cotacoes = (await fonte.latest()).unwrap();
      expect(cotacoes.single.rate, closeTo(0.1356, 1e-12));
      expect(adapter.callCount['package_show'], isNull,
          reason: 'a função substitui o caminho direto');
    });
  });

  group('Curva do aplicativo — decisão 84', () {
    List<TreasuryQuote> dia(DateTime base) => [
          TreasuryQuote(type: TreasuryCurve.ltn, maturity: DateTime.utc(2027, 1, 1), baseDate: base, rate: 0.1356),
          TreasuryQuote(type: TreasuryCurve.ltn, maturity: DateTime.utc(2029, 1, 1), baseDate: base, rate: 0.1393),
          TreasuryQuote(type: TreasuryCurve.ntnF, maturity: DateTime.utc(2037, 1, 1), baseDate: base, rate: 0.1433),
        ];

    test('a do dia vence a do pacote', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Fonte(() async => Ok(dia(DateTime.utc(2026, 9, 10)))),
        carregarPacote: () async => jsonEncode(TreasuryQuotesCodec.encode(
            dia(DateTime.utc(2026, 9, 1)), geradoEm: DateTime.utc(2026, 9, 1))),
      );
      final c = await repo.curveAt(DateTime(2026, 9, 11));
      expect(c!.referenceDate, DateTime.utc(2026, 9, 10));
    });

    test('sem rede, o pacote recente serve', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Fonte(() async => const Err(InsufficientData('sem rede'))),
        carregarPacote: () async => jsonEncode(TreasuryQuotesCodec.encode(
            dia(DateTime.utc(2026, 9, 8)), geradoEm: DateTime.utc(2026, 9, 8))),
      );
      final c = await repo.curveAt(DateTime(2026, 9, 11));
      expect(c!.referenceDate, DateTime.utc(2026, 9, 8));
    });

    test('pacote velho não vira curva: a cascata recua, declarando', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Fonte(() async => const Err(InsufficientData('sem rede'))),
        carregarPacote: () async => jsonEncode(TreasuryQuotesCodec.encode(
            dia(DateTime.utc(2026, 6, 1)), geradoEm: DateTime.utc(2026, 6, 1))),
      );
      expect(await repo.curveAt(DateTime(2026, 9, 11)), isNull);
    });

    test('falha da busca não fica guardada: a próxima avaliação tenta de novo',
        () async {
      var chamadas = 0;
      final repo = RiskFreeCurveRepository(
        remote: _Fonte(() async {
          chamadas++;
          return chamadas == 1
              ? const Err(InsufficientData('sem rede'))
              : Ok(dia(DateTime.utc(2026, 9, 10)));
        }),
        carregarPacote: () async => throw StateError('sem pacote'),
      );
      expect(await repo.curveAt(DateTime(2026, 9, 11)), isNull);
      expect(await repo.curveAt(DateTime(2026, 9, 11)), isNotNull);
      expect(chamadas, 2);
    });

    test('a busca vale pelo dia: no dia seguinte, busca de novo', () async {
      var chamadas = 0;
      final repo = RiskFreeCurveRepository(
        remote: _Fonte(() async {
          chamadas++;
          return Ok(dia(DateTime.utc(2026, 9, 10)));
        }),
        carregarPacote: () async => throw StateError('sem pacote'),
      );
      await repo.curveAt(DateTime(2026, 9, 11, 9));
      await repo.curveAt(DateTime(2026, 9, 11, 18));
      expect(chamadas, 1, reason: 'o mesmo dia usa a mesma busca');
      await repo.curveAt(DateTime(2026, 9, 12));
      expect(chamadas, 2);
    });
  });

  group('Registro da B3 no aplicativo — decisão 83', () {
    final pacote = jsonEncode(B3RegistryCodec.encodePackage([
      B3Registry.issuer({
        'code': 'CTKA',
        'totalNumberShares': '6.205.375',
      }, consultedOn: DateTime.utc(2026, 9, 14))!,
    ], geradoEm: DateTime.utc(2026, 9, 14)));

    test('a contagem vem pela raiz do ticker', () async {
      final repo = B3RegistryRepository(carregarPacote: () async => pacote);
      final c = await repo.officialSharesFor(Ticker.parse('CTKA4'));
      expect(c!.total, closeTo(6205375, 1e-6));
      expect(c.asOf, DateTime.utc(2026, 9, 14));
      expect(await repo.officialSharesFor(Ticker.parse('PETR4')), isNull);
    });

    test('sem pacote, o repositório é transparente', () async {
      final repo = B3RegistryRepository(
          carregarPacote: () async => throw StateError('asset ausente'));
      expect(await repo.officialSharesFor(Ticker.parse('CTKA4')), isNull);
    });
  });
}

class _Fonte extends TesouroDatasource {
  final Future<Result<List<TreasuryQuote>>> Function() _latest;
  _Fonte(this._latest)
      : super(ApiClient(const ApiConfig(
          mode: BrapiMode.direct,
          brapiBaseUrl: 'https://brapi.dev/api',
          bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
        )));

  @override
  Future<Result<List<TreasuryQuote>>> latest() => _latest();
}
