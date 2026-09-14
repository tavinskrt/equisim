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
