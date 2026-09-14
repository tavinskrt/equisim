import 'dart:convert';

import 'package:equisim/data/repositories/cvm_fundamentals_repository.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = Ticker.parse('WEGE3');
DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

/// Mercado de teste: sete exercícios de dezembro, com valor de mercado.
class _Mercado implements FundamentalsRepository {
  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async => Ok([
        for (var a = 2016; a <= 2022; a++)
          FundamentalsSnapshot(
            ticker: t,
            fiscalPeriodEnd: _d(a, 12, 31),
            netIncome: 9,
            marketCap: 1000,
          ),
      ]);

  @override
  Future<Result<Asset>> profile(Ticker t) async =>
      Ok(Asset(ticker: t, name: 'WEG', sector: const Sector(key: 'x', label: 'X')));

  @override
  Future<Result<List<Ticker>>> universe() async => Ok([_t]);
}

class _MercadoFora extends _Mercado {
  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async =>
      const Err(InsufficientData('Sem conexão com a fonte de dados.'));
}

String _pacote() => jsonEncode(CvmDocumentCodec.encodePackage({
      'WEGE3': [
        for (var a = 2019; a <= 2022; a++)
          CvmPeriodDocument(
            kind: CvmDocumentKind.dfp,
            periodStart: _d(a, 1, 1),
            periodEnd: _d(a, 12, 31),
            current: FundamentalsSnapshot(
              ticker: _t,
              fiscalPeriodEnd: _d(a, 12, 31),
              netIncome: 10,
              totalAssets: 500,
              receiptDate: _d(a + 1, 3, 1),
            ),
          ),
      ],
    }, geradoEm: _d(2026, 9, 14)));

void main() {
  test('com pacote, a CVM entra campo a campo e o mercado segue', () async {
    final repo = CvmFundamentalsRepository(
      mercado: _Mercado(),
      carregarPacote: () async => _pacote(),
      hoje: () => DateTime(2023, 4, 1),
    );
    final s = (await repo.history(_t)).unwrap();
    expect(s.length, 7);
    expect(s.last.netIncome, 10, reason: 'a CVM vence onde tem');
    expect(s.last.totalAssets, 500);
    expect(s.last.marketCap, 1000, reason: 'mercado continua do mercado');
    expect(s.first.netIncome, 9, reason: 'antes da CVM, só o mercado');
  });

  test('sem pacote, o repositório é transparente', () async {
    final repo = CvmFundamentalsRepository(
      mercado: _Mercado(),
      carregarPacote: () async => throw StateError('asset ausente'),
      hoje: () => DateTime(2023, 4, 1),
    );
    final s = (await repo.history(_t)).unwrap();
    expect(s.every((x) => (x.netIncome! - 9).abs() < 1e-9), isTrue);
    expect(s.length, 7);
  });

  test('pacote corrompido também não derruba a avaliação', () async {
    final repo = CvmFundamentalsRepository(
      mercado: _Mercado(),
      carregarPacote: () async => '{isto não é json',
      hoje: () => DateTime(2023, 4, 1),
    );
    expect((await repo.history(_t)).isOk, isTrue);
  });

  test('a série ancorada fica desligada por padrão — decisão 73', () {
    final repo = CvmFundamentalsRepository(
      mercado: _Mercado(),
      carregarPacote: () async => _pacote(),
      hoje: () => DateTime(2023, 4, 1),
    );
    expect(repo.ancorada, isFalse);
  });

  test('o pacote é lido uma vez só', () async {
    var leituras = 0;
    final repo = CvmFundamentalsRepository(
      mercado: _Mercado(),
      carregarPacote: () async {
        leituras++;
        return _pacote();
      },
      hoje: () => DateTime(2023, 4, 1),
    );
    await repo.history(_t);
    await repo.history(_t);
    await repo.history(_t);
    expect(leituras, 1);
  });

  test('nem quando várias avaliações pedem o pacote ao mesmo tempo', () async {
    // `valuationProvider` é uma família: telas diferentes pedem ativos
    // diferentes em paralelo, e cada leitura é um JSON de 9 MB decodificado
    // na thread da interface.
    var leituras = 0;
    final repo = CvmFundamentalsRepository(
      mercado: _Mercado(),
      carregarPacote: () async {
        leituras++;
        await Future<void>.delayed(Duration.zero);
        return _pacote();
      },
      hoje: () => DateTime(2023, 4, 1),
    );
    final r = await Future.wait([for (var i = 0; i < 4; i++) repo.history(_t)]);
    expect(leituras, 1);
    expect(
        r.every((x) => (x.unwrap().last.netIncome! - 10).abs() < 1e-9), isTrue);
  });

  test('falha da série de mercado passa adiante, e não vira série da CVM sozinha',
      () async {
    // O mercado dá preço, valor de mercado e contagem; sem ele a série da CVM
    // não forma avaliação, e fingir que forma esconderia a falha.
    final repo = CvmFundamentalsRepository(
      mercado: _MercadoFora(),
      carregarPacote: () async => _pacote(),
      hoje: () => DateTime(2023, 4, 1),
    );
    final r = await repo.history(_t);
    expect(r.isErr, isTrue);
    expect(r.failureOrNull, isA<InsufficientData>());
  });

  group('A ausência aparece — item A1.10', () {
    CvmFundamentalsRepository comPacote(Future<String> Function() pacote,
            {DateTime? hoje}) =>
        CvmFundamentalsRepository(
          mercado: _Mercado(),
          carregarPacote: pacote,
          hoje: () => hoje ?? DateTime(2026, 10, 1),
        );

    test('pacote ausente vira ressalva, e a série continua', () async {
      final repo = comPacote(() async => throw StateError('asset ausente'));
      expect(await repo.coverageOf(_t), CvmCoverage.pacoteAusente);
      expect(await repo.coverageNote(_t), contains('não trouxe o pacote'));
      expect((await repo.history(_t)).isOk, isTrue);
    });

    test('JSON inválido é ilegível, e diz por quê', () async {
      final repo = comPacote(() async => '{isto não é json');
      expect(await repo.coverageOf(_t), CvmCoverage.pacoteIlegivel);
      expect(await repo.coverageNote(_t), contains('JSON é inválido'));
    });

    test('versão que o leitor não conhece é ilegível, e não vazio', () async {
      final repo = comPacote(() async => jsonEncode({
            'versao': CvmDocumentCodec.versao + 1,
            'geradoEm': '2026-09-14',
            'tickers': {},
          }));
      expect(await repo.coverageOf(_t), CvmCoverage.pacoteIlegivel);
      expect(await repo.coverageNote(_t), contains('versão'));
    });

    test('pacote sem ativo nenhum é ilegível', () async {
      final repo = comPacote(() async => jsonEncode({
            'versao': CvmDocumentCodec.versao,
            'geradoEm': '2026-09-14',
            'tickers': {},
          }));
      expect(await repo.coverageOf(_t), CvmCoverage.pacoteIlegivel);
    });

    test('ativo fora do pacote é declarado, com a data do pacote', () async {
      final repo = comPacote(() async => _pacote());
      final outro = Ticker.parse('PETR4');
      expect(await repo.coverageOf(outro), CvmCoverage.semDocumentos);
      expect(await repo.coverageNote(outro), contains('14/09/2026'));
    });

    test('ativo coberto por pacote recente não leva ressalva', () async {
      final repo = comPacote(() async => _pacote());
      expect(await repo.coverageOf(_t), CvmCoverage.coberto);
      expect(await repo.coverageNote(_t), isNull);
    });

    test('pacote defasado é declarado', () async {
      final repo =
          comPacote(() async => _pacote(), hoje: DateTime(2027, 3, 1));
      expect(await repo.coverageNote(_t), contains('há 168 dias'));
    });
  });
}
