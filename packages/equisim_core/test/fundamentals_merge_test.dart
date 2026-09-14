import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _t = Ticker.parse('TEST3');

FundamentalsSnapshot _cvm() => FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: DateTime(2024, 12, 31),
      receiptDate: DateTime(2025, 2, 19),
      totalRevenue: 1000,
      ebit: 250,
      netIncome: 140,
      totalAssets: 5000,
      totalStockholderEquity: 2000,
      treasuryShares: 1e6,
      // A CVM nao publica mercado.
    );

FundamentalsSnapshot _mercado() => FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: DateTime(2024, 12, 31),
      totalRevenue: 999, // divergente de proposito
      ebit: 240,
      netIncome: 138,
      ebitda: 300, // so o mercado tem
      marketCap: 9e9,
      sharesOutstanding: 1e9,
      enterpriseToEbitda: 7.5,
    );

FundamentalsSnapshot _cvmSemPl() => FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: DateTime(2024, 12, 31),
      netIncome: 140,
    );

FundamentalsSnapshot _mercado2() => FundamentalsSnapshot(
      ticker: _t,
      fiscalPeriodEnd: DateTime(2024, 12, 31),
      bookValuePerShare: 6.18,
      sharesOutstandingAsOf: 234178210,
    );

void main() {
  group('Mescla', () {
    test('a CVM vence no que ela publica', () {
      final m = FundamentalsMerge.merge(cvm: _cvm(), mercado: _mercado())!;
      expect(m.snapshot.totalRevenue, 1000);
      expect(m.snapshot.ebit, 250);
      expect(m.snapshot.netIncome, 140);
      expect(m.provenance.of('netIncome'), FieldSource.cvm);
      expect(m.provenance.of('totalRevenue'), FieldSource.cvm);
    });

    test('o mercado preenche o que a CVM não tem', () {
      final m = FundamentalsMerge.merge(cvm: _cvm(), mercado: _mercado())!;
      expect(m.snapshot.ebitda, 300);
      expect(m.provenance.of('ebitda'), FieldSource.mercado);
    });

    test('exercício de outra data não empresta fluxo — decisão 78',
        () {
      // Doze meses até junho de 2025 contra o dezembro de 2024 do mercado.
      final junho = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime.utc(2025, 6, 30),
        receiptDate: DateTime.utc(2025, 8, 10),
        ebit: 260,
        netIncome: 150,
      );
      final dezembro = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime.utc(2024, 12, 31),
        receiptDate: DateTime.utc(2025, 2, 19),
        ebitda: 300,
        interestExpense: -40,
        nopat: 170,
        earningsPerShare: 1.38,
        sharesOutstandingAsOf: 1e8,
        bookValuePerShare: 19.5,
        marketCap: 9e9,
        sharesOutstanding: 1e9,
        enterpriseToEbitda: 7.5,
      );
      final m = FundamentalsMerge.merge(cvm: junho, mercado: dezembro)!;
      final s = m.snapshot;
      expect(s.interestExpense, isNull,
          reason: 'juros de outra janela no custo da dívida');
      expect(s.nopat, isNull, reason: 'o NOPAT sai do EBIT desta janela');
      expect(s.ebitda, isNull);
      expect(s.earningsPerShare, isNull,
          reason: 'LPA de outro lucro no árbitro lucro ÷ LPA');
      expect(s.sharesOutstandingAsOf, 1e8,
          reason: 'o par por ação do último encerramento é estoque, e é a '
              'base de patrimônio da cascata');
      expect(s.bookValuePerShare, 19.5);
      expect(s.marketCap, 9e9, reason: 'o valor de mercado é de hoje');
      expect(s.sharesOutstanding, 1e9);
      expect(s.enterpriseToEbitda, 7.5);
      expect(s.ebit, 260);
      expect(m.provenance.of('interestExpense'), FieldSource.ausente);
      expect(m.provenance.of('marketCap'), FieldSource.mercado);
    });

    group('A base de patrimônio é o PL da CVM — decisão 81', () {
      test('o VPA é derivado, e o produto devolve o PL da demonstração', () {
        final cvm = FundamentalsSnapshot(
          ticker: _t,
          fiscalPeriodEnd: DateTime.utc(2025, 12, 31),
          totalStockholderEquity: 48.25e9,
        );
        // HAPV3: a base de mercado dava R$ 373 bi.
        final mercado = FundamentalsSnapshot(
          ticker: _t,
          fiscalPeriodEnd: DateTime.utc(2025, 12, 31),
          bookValuePerShare: 49.7,
          sharesOutstandingAsOf: 7.507e9,
        );
        final m = FundamentalsMerge.merge(cvm: cvm, mercado: mercado)!;
        expect(m.snapshot.equityBookValue, closeTo(48.25e9, 1e-3));
        expect(m.snapshot.sharesOutstandingAsOf, 7.507e9,
            reason: 'a contagem continua sendo a do mercado — decisão 70');
        expect(m.provenance.of('bookValuePerShare'), FieldSource.derivado);
      });

      test('no ponto de junho, o PL é o de junho', () {
        final junho = FundamentalsSnapshot(
          ticker: _t,
          fiscalPeriodEnd: DateTime.utc(2025, 6, 30),
          totalStockholderEquity: 2100,
        );
        final dezembro = FundamentalsSnapshot(
          ticker: _t,
          fiscalPeriodEnd: DateTime.utc(2024, 12, 31),
          bookValuePerShare: 20,
          sharesOutstandingAsOf: 100,
        );
        final m = FundamentalsMerge.merge(cvm: junho, mercado: dezembro)!;
        expect(m.snapshot.equityBookValue, closeTo(2100, 1e-9),
            reason: 'e não os 2.000 de dezembro, que a decisão 78 declarava');
      });

      test('PL negativo continua sem base, como o VPA negativo do mercado', () {
        final cvm = FundamentalsSnapshot(
          ticker: _t,
          fiscalPeriodEnd: DateTime.utc(2025, 12, 31),
          totalStockholderEquity: -500,
        );
        final mercado = FundamentalsSnapshot(
          ticker: _t,
          fiscalPeriodEnd: DateTime.utc(2025, 12, 31),
          bookValuePerShare: 3,
          sharesOutstandingAsOf: 100,
        );
        final m = FundamentalsMerge.merge(cvm: cvm, mercado: mercado)!;
        expect(m.snapshot.equityBookValue, isNull);
        expect(m.snapshot.bookValuePerShare, -5);
      });

      test('sem PL na CVM, o VPA do mercado segue', () {
        final m = FundamentalsMerge.merge(cvm: _cvmSemPl(), mercado: _mercado2())!;
        expect(m.snapshot.bookValuePerShare, 6.18);
        expect(m.provenance.of('bookValuePerShare'), FieldSource.mercado);
      });
    });

    test('fevereiro bissexto é a mesma janela', () {
      expect(
        FundamentalsMerge.mesmaJanela(
            DateTime.utc(2024, 2, 29), DateTime.utc(2024, 2, 28)),
        isTrue,
      );
      expect(
        FundamentalsMerge.mesmaJanela(
            DateTime.utc(2024, 6, 30), DateTime.utc(2023, 12, 31)),
        isFalse,
      );
    });

    test('a contagem do exercício NUNCA vem da CVM — decisão 70', () {
      // A escala do campo da CVM varia por declarante: 60,9% em unidades,
      // 34,5% em milhares. Importar o absoluto levou a MILS3 a +14.037%.
      // A ferramenta de ingestao ja deixou de preenche-lo; a regra fica na
      // mescla para que outra montagem nao o reintroduza.
      final cvmComContagem = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime(2024, 12, 31),
        sharesOutstandingAsOf: 234178, // em milhares, e errado
        bookValuePerShare: 9999,
      );
      final mercado = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime(2024, 12, 31),
        sharesOutstandingAsOf: 234178210,
        bookValuePerShare: 6.18,
      );
      final m = FundamentalsMerge.merge(cvm: cvmComContagem, mercado: mercado)!;
      expect(m.snapshot.sharesOutstandingAsOf, 234178210);
      expect(m.snapshot.bookValuePerShare, 6.18);
      expect(m.provenance.of('sharesOutstandingAsOf'), FieldSource.mercado);
    });

    test('a tesouraria entra pela fração, e devolve contagem INTEIRA', () {
      final s = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime(2024, 12, 31),
        treasuryFraction: 7250 / 234178,
      );
      // MILS3 em 2024: 7.250 de 234.178 em tesouraria — 3,096%. A base de
      // mercado sao 234.178.210 papeis, e a liquida, 226.928.203.
      final liquida = s.sharesNetOfTreasury(234178210)!;
      expect(liquida, liquida.roundToDouble(),
          reason: 'contagem de acao e inteira');
      expect(liquida, 226928203.0);
      // A tolerancia e o proprio arredondamento: meia acao em 234.178.210
      // desloca a fracao em 2,1e-9. Exigir mais que isso seria exigir que a
      // contagem NAO fosse inteira.
      expect(1 - liquida / 234178210, closeTo(7250 / 234178, 1e-8),
          reason: 'a fracao se preserva, e a escala nao entra');
    });

    test('sem fração, a contagem absoluta ainda serve', () {
      final s = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime(2024, 12, 31),
        treasuryShares: 1000,
      );
      expect(s.sharesNetOfTreasury(10000), 9000);
    });

    test('valor de mercado e contagem corrente NUNCA vêm da CVM', () {
      // Mesmo que a CVM trouxesse — e ela nao traz —, estes descrevem o hoje
      // do papel, e nao o exercicio.
      final cvmComMercado = FundamentalsSnapshot(
        ticker: _t,
        fiscalPeriodEnd: DateTime(2024, 12, 31),
        marketCap: 1.0,
        sharesOutstanding: 2.0,
        enterpriseToEbitda: 3.0,
      );
      final m = FundamentalsMerge.merge(
          cvm: cvmComMercado, mercado: _mercado())!;
      expect(m.snapshot.marketCap, 9e9);
      expect(m.snapshot.sharesOutstanding, 1e9);
      expect(m.snapshot.enterpriseToEbitda, 7.5);
      // Só os que o exemplar de mercado preenche; os demais de
      // `somenteDeMercado` têm teste próprio acima.
      for (final c in const [
        'marketCap',
        'sharesOutstanding',
        'enterpriseToEbitda',
      ]) {
        expect(m.provenance.of(c), FieldSource.mercado, reason: c);
      }
    });

    test('a data de recebimento é da CVM', () {
      final m = FundamentalsMerge.merge(cvm: _cvm(), mercado: _mercado())!;
      expect(m.snapshot.receiptDate, DateTime(2025, 2, 19));
      expect(m.provenance.of('receiptDate'), FieldSource.cvm);
    });

    test('campos que só a CVM tem chegam ao resultado', () {
      final m = FundamentalsMerge.merge(cvm: _cvm(), mercado: _mercado())!;
      expect(m.snapshot.totalAssets, 5000);
      expect(m.snapshot.treasuryShares, 1e6);
      expect(m.provenance.of('totalAssets'), FieldSource.cvm);
    });

    test('fonte única não perde nada, e a procedência diz qual', () {
      final soCvm = FundamentalsMerge.merge(cvm: _cvm())!;
      expect(soCvm.snapshot.netIncome, 140);
      expect(soCvm.provenance.of('netIncome'), FieldSource.cvm);
      expect(soCvm.provenance.of('marketCap'), FieldSource.ausente);

      final soMercado = FundamentalsMerge.merge(mercado: _mercado())!;
      expect(soMercado.snapshot.marketCap, 9e9);
      expect(soMercado.provenance.of('marketCap'), FieldSource.mercado);
      expect(soMercado.provenance.of('totalAssets'), FieldSource.ausente);
    });

    test('sem nenhuma das duas, devolve nulo', () {
      expect(FundamentalsMerge.merge(), isNull);
    });

    test('campo ausente nas duas fica ausente, e não zero', () {
      final m = FundamentalsMerge.merge(cvm: _cvm(), mercado: _mercado())!;
      expect(m.snapshot.freeCashFlow, isNull);
      expect(m.provenance.of('freeCashFlow'), FieldSource.ausente);
    });
  });

  group('Procedência', () {
    test('conta por fonte e lista o que veio da CVM', () {
      final m = FundamentalsMerge.merge(cvm: _cvm(), mercado: _mercado())!;
      final c = m.provenance.contagem;
      expect(c[FieldSource.cvm], greaterThan(0));
      expect(c[FieldSource.mercado], greaterThan(0));
      expect(m.provenance.daCvm, contains('netIncome'));
      expect(m.provenance.daCvm, contains('totalAssets'));
      expect(m.provenance.daCvm, isNot(contains('marketCap')));
      // A lista sai ordenada, para o relatorio nao mudar entre execucoes.
      final ordenada = [...m.provenance.daCvm]..sort();
      expect(m.provenance.daCvm, ordenada);
    });

    test('o mapa é imutável', () {
      final p = FundamentalsProvenance({'x': FieldSource.cvm});
      expect(() => p.byField['y'] = FieldSource.mercado, throwsUnsupportedError);
    });
  });
}
