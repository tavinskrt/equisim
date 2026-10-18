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

ApiClient _client(FixtureAdapter adapter) {
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

const _catalog = '''
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
      final source = TreasuryDatasource(_client(FixtureAdapter(bodies: {
        'package_show': _catalog,
        'precotaxatesourodireto.csv': _csv,
      })));
      final r = await source.latest();
      final quotes = r.unwrap();
      expect(quotes, hasLength(3));
      expect(quotes.map((q) => q.baseDate).toSet(), {DateTime.utc(2026, 9, 10)});
      expect(quotes.every((q) => q.rate < 0.2), isTrue,
          reason: 'a linha de 09/09, com 99,99%, não pode ter sido lida');
      // A taxa exata de cada título, e não só a ordem de grandeza: "13,56" é
      // 13,56% ao ano — a vírgula decimal lida errado passaria pelo teto de 20%
      // e deslocaria a curva inteira (lente `risco`, 16/09/2026).
      final byMaturityDate = {
        for (final q in quotes) q.maturity.toIso8601String().substring(0, 10): q.rate,
      };
      expect(byMaturityDate['2027-01-01'], closeTo(0.1356, 1e-12));
      expect(byMaturityDate['2029-01-01'], closeTo(0.1393, 1e-12));
      expect(byMaturityDate['2037-01-01'], closeTo(0.1433, 1e-12));
    });

    test('catálogo sem CSV é falha declarada', () async {
      final source = TreasuryDatasource(_client(FixtureAdapter(bodies: {
        'package_show': '{"result":{"resources":[]}}',
      })));
      expect((await source.latest()).isErr, isTrue);
    });

    test('arquivo fora do ar é falha, e não lista vazia', () async {
      final source = TreasuryDatasource(_client(FixtureAdapter(
        bodies: {'package_show': _catalog},
        failures: {'precotaxatesourodireto.csv': 503},
      )));
      expect((await source.latest()).isErr, isTrue);
    });

    test('CSV com o formato quebrado é falha, e não exceção crua', () async {
      // Lente `risco`, 20/09/2026. O arquivo do Tesouro é publicação em massa
      // com cabeçalho em texto: coluna renomeada, separador trocado ou taxa
      // ilegível têm de virar `Result.err`, e não estourar na leitura.

      // Cabeçalho certo e taxa ilegível na única linha do dia.
      const unreadableRate = 'Tipo Titulo;Data Vencimento;Data Base;'
          'Taxa Compra Manha;Taxa Venda Manha;'
          'PU Compra Manha;PU Venda Manha;PU Base Manha\n'
          'Tesouro Prefixado;01/01/2027;10/09/2026;;;;;\n';
      // Separador de vírgula no lugar do ponto e vírgula.
      const commaSeparator =
          'Tipo Titulo,Data Vencimento,Data Base,Taxa Compra Manha\n'
          'Tesouro Prefixado,01/01/2027,10/09/2026,13.56\n';
      const brokenCases = [
        '', // arquivo vazio
        'coisa;outra;terceira\n1;2;3\n', // sem as colunas que a curva lê
        unreadableRate,
        commaSeparator,
      ];
      for (final csv in brokenCases) {
        final source = TreasuryDatasource(_client(FixtureAdapter(bodies: {
          'package_show': _catalog,
          'precotaxatesourodireto.csv': csv,
        })));
        final r = await source.latest();
        expect(r.isErr, isTrue, reason: csv.isEmpty ? '(vazio)' : csv);
      }
    });
  });

  group('Curva do aplicativo — decisão 84', () {
    List<TreasuryQuote> day(DateTime base) => [
          TreasuryQuote(type: TreasuryCurve.ltn, maturity: DateTime.utc(2027, 1, 1), baseDate: base, rate: 0.1356),
          TreasuryQuote(type: TreasuryCurve.ltn, maturity: DateTime.utc(2029, 1, 1), baseDate: base, rate: 0.1393),
          TreasuryQuote(type: TreasuryCurve.ntnF, maturity: DateTime.utc(2037, 1, 1), baseDate: base, rate: 0.1433),
        ];

    test('a do dia vence a do pacote', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Source(() async => Ok(day(DateTime.utc(2026, 9, 10)))),
        loadPackage: () async => jsonEncode(TreasuryQuotesCodec.encode(
            day(DateTime.utc(2026, 9, 1)), generatedAt: DateTime.utc(2026, 9, 1))),
      );
      final c = (await repo.readAt(DateTime(2026, 9, 11))).curve;
      expect(c!.referenceDate, DateTime.utc(2026, 9, 10));
    });

    test('sem rede, o pacote recente serve', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Source(() async => const Err(InsufficientData('sem rede'))),
        loadPackage: () async => jsonEncode(TreasuryQuotesCodec.encode(
            day(DateTime.utc(2026, 9, 8)), generatedAt: DateTime.utc(2026, 9, 8))),
      );
      final c = (await repo.readAt(DateTime(2026, 9, 11))).curve;
      expect(c!.referenceDate, DateTime.utc(2026, 9, 8));
    });

    test('pacote velho não vira curva: a cascata recua, declarando', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Source(() async => const Err(InsufficientData('sem rede'))),
        loadPackage: () async => jsonEncode(TreasuryQuotesCodec.encode(
            day(DateTime.utc(2026, 6, 1)), generatedAt: DateTime.utc(2026, 6, 1))),
      );
      expect((await repo.readAt(DateTime(2026, 9, 11))).curve, isNull);
    });

    test('falha da busca não fica guardada: a próxima avaliação tenta de novo',
        () async {
      var calls = 0;
      final repo = RiskFreeCurveRepository(
        remote: _Source(() async {
          calls++;
          return calls == 1
              ? const Err(InsufficientData('sem rede'))
              : Ok(day(DateTime.utc(2026, 9, 10)));
        }),
        loadPackage: () async => throw StateError('sem pacote'),
      );
      expect((await repo.readAt(DateTime(2026, 9, 11))).curve, isNull);
      expect((await repo.readAt(DateTime(2026, 9, 11))).curve, isNotNull);
      expect(calls, 2);
    });

    test('a busca vale pelo dia: no dia seguinte, busca de novo', () async {
      var calls = 0;
      final repo = RiskFreeCurveRepository(
        remote: _Source(() async {
          calls++;
          return Ok(day(DateTime.utc(2026, 9, 10)));
        }),
        loadPackage: () async => throw StateError('sem pacote'),
      );
      await repo.readAt(DateTime(2026, 9, 11, 9));
      await repo.readAt(DateTime(2026, 9, 11, 18));
      expect(calls, 1, reason: 'o mesmo dia usa a mesma busca');
      await repo.readAt(DateTime(2026, 9, 12));
      expect(calls, 2);
    });

    String packageOf(DateTime base) => jsonEncode(
        TreasuryQuotesCodec.encode(day(base), generatedAt: base));

    test('na web, só o pacote — decisão 86', () async {
      final repo = RiskFreeCurveRepository(
        remote: null,
        loadPackage: () async => packageOf(DateTime.utc(2026, 9, 8)),
      );
      final r = await repo.readAt(DateTime(2026, 9, 11));
      expect(r.curve!.referenceDate, DateTime.utc(2026, 9, 8));
      expect(r.note, isNull, reason: 'com curva, a avaliação já diz a data');
    });

    test('na web, pacote vencido: a ressalva diz a data e o remédio', () async {
      final repo = RiskFreeCurveRepository(
        remote: null,
        loadPackage: () async => packageOf(DateTime.utc(2026, 6, 1)),
      );
      final r = await repo.readAt(DateTime(2026, 9, 11));
      expect(r.curve, isNull);
      expect(r.note, contains('Na web'));
      expect(r.note, contains('01/06/2026'));
      expect(r.note, contains('build novo'));
    });

    test('na web, sem pacote legível, a ressalva diz isso', () async {
      final repo = RiskFreeCurveRepository(
        remote: null,
        loadPackage: () async => '{isto não é json',
      );
      final r = await repo.readAt(DateTime(2026, 9, 11));
      expect(r.curve, isNull);
      expect(r.note, contains('não pôde ser lido'));
    });

    test('no nativo, sem o Tesouro e com pacote vencido, a ressalva não fala '
        'em build', () async {
      final repo = RiskFreeCurveRepository(
        remote: _Source(() async => const Err(InsufficientData('sem rede'))),
        loadPackage: () async => packageOf(DateTime.utc(2026, 6, 1)),
      );
      final r = await repo.readAt(DateTime(2026, 9, 11));
      expect(r.curve, isNull);
      expect(r.note, contains('O Tesouro não trouxe'));
      expect(r.note, contains('01/06/2026'));
      expect(r.note, isNot(contains('build novo')),
          reason: 'no nativo o remédio é a rede, e não um build');
    });
  });

  group('Registro da B3 no aplicativo — decisão 83', () {
    final package = jsonEncode(B3RegistryCodec.encodePackage([
      B3Registry.issuer({
        'code': 'CTKA',
        'totalNumberShares': '6.205.375',
      }, consultedOn: DateTime.utc(2026, 9, 14))!,
    ], generatedAt: DateTime.utc(2026, 9, 14)));

    test('a contagem vem pela raiz do ticker', () async {
      final repo = B3RegistryRepository(loadPackage: () async => package);
      final c = await repo.officialSharesFor(Ticker.parse('CTKA4'));
      // **Igualdade, e não tolerância** (lente `risco`, 21/09/2026). A
      // contagem da B3 é inteiro publicado — `6.205.375` —, e o que o teste
      // cobra do analisador é que ele leia esse inteiro, e não que chegue
      // perto dele. Fração aqui é defeito de leitura, não erro de arredondar.
      expect(c!.total, equals(6205375));
      expect(c.asOf, DateTime.utc(2026, 9, 14));
      expect(await repo.officialSharesFor(Ticker.parse('PETR4')), isNull);
    });

    test('sem pacote, o repositório é transparente', () async {
      final repo = B3RegistryRepository(
          loadPackage: () async => throw StateError('asset ausente'));
      expect(await repo.officialSharesFor(Ticker.parse('CTKA4')), isNull);
    });
  });
}

class _Source extends TreasuryDatasource {
  final Future<Result<List<TreasuryQuote>>> Function() _latest;
  _Source(this._latest)
      : super(ApiClient(const ApiConfig(
          mode: BrapiMode.direct,
          brapiBaseUrl: 'https://brapi.dev/api',
          bcbBaseUrl: 'https://api.bcb.gov.br/dados/serie',
        )));

  @override
  Future<Result<List<TreasuryQuote>>> latest() => _latest();
}
