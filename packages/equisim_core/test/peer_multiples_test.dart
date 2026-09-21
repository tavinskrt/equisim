import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Item B5 — a segunda leitura, por múltiplos de pares.
void main() {
  final ticker = Ticker.parse('PETR4');
  final hoje = DateTime(2026, 9, 14);

  PeerMultipleSet pares({
    double? pl,
    double? pvp,
    double? evEbitda,
    int n = 12,
    String grupo = 'petroleo-gas-e-biocombustiveis',
  }) =>
      PeerMultipleSet(
        asOf: hoje,
        byKind: {
          if (pl != null)
            MultipleKind.precoLucro:
                PeerMultiple(median: pl, peers: n, group: grupo),
          if (pvp != null)
            MultipleKind.precoPatrimonio:
                PeerMultiple(median: pvp, peers: n, group: grupo),
          if (evEbitda != null)
            MultipleKind.firmaEbitda:
                PeerMultiple(median: evEbitda, peers: n, group: grupo),
        },
      );

  FundamentalsSnapshot exercicio({
    double? lucro = 1000,
    double? patrimonio = 8000,
    double? ebitda = 2400,
    double caixa = 500,
    double divida = 3000,
  }) =>
      FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        totalRevenue: 12000,
        ebit: 1800,
        ebitda: ebitda,
        netIncome: lucro,
        incomeBeforeTax: 1400,
        incomeTaxExpense: -400,
        interestExpense: 300,
        earningsPerShare: lucro == null ? null : lucro / 1000,
        cash: caixa,
        shortTermDebt: divida * 0.25,
        longTermDebt: divida * 0.75,
        totalStockholderEquity: patrimonio,
        bookValuePerShare: patrimonio == null ? null : patrimonio / 1000,
        operatingCashFlow: 2000,
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 10000,
      );

  group('Cada múltiplo devolve o preço que ele implica', () {
    test('P/L é o múltiplo vezes o lucro, pelo divisor da ponte', () {
      final r = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(pl: 9.0),
      ).firstWhere((r) => r.kind == MultipleKind.precoLucro);
      expect(r.applied, isTrue);
      expect(r.fairValuePerShare, closeTo(9.0 * 1000 / 1000, 1e-12));
      expect(r.peer!.group, 'petroleo-gas-e-biocombustiveis');
    });

    test('o divisor é o da ponte, e não a contagem da fonte', () {
      // **A conferência que impede a comparação de medir outra coisa.** A
      // contagem da fonte é 1.000; se a ponte arbitrou 1.500, o múltiplo tem
      // de dividir por 1.500 — ou a divergência contra o DCF mediria a ponte
      // (decisão 83).
      final a = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(pl: 9.0),
      ).first;
      final b = PeerValuation.readings(
        latest: exercicio(),
        shares: 1500,
        peers: pares(pl: 9.0),
      ).first;
      expect(b.fairValuePerShare! / a.fairValuePerShare!,
          closeTo(1000 / 1500, 1e-12));
    });

    test('EV/EBITDA passa pela mesma ponte de dívida líquida do DCF', () {
      final r = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(evEbitda: 6.0),
      ).firstWhere((r) => r.kind == MultipleKind.firmaEbitda);
      // 6 × 2.400 = 14.400 de firma; menos 2.500 de dívida líquida = 11.900.
      expect(r.fairValuePerShare, closeTo(11.9, 1e-12));
    });

    test('caixa líquido soma, e é legítimo', () {
      final r = PeerValuation.readings(
        latest: exercicio(caixa: 6000, divida: 1000),
        shares: 1000,
        peers: pares(evEbitda: 6.0),
      ).firstWhere((r) => r.kind == MultipleKind.firmaEbitda);
      // 14.400 − (1.000 − 6.000) = 19.400.
      expect(r.fairValuePerShare, closeTo(19.4, 1e-12));
    });
  });

  group('Cada recusa diz por que o múltiplo não se aplica', () {
    test('prejuízo tira o P/L, e não o inverte', () {
      final r = PeerValuation.readings(
        latest: exercicio(lucro: -500),
        shares: 1000,
        peers: pares(pl: 9.0, pvp: 1.2),
      ).firstWhere((r) => r.kind == MultipleKind.precoLucro);
      expect(r.applied, isFalse);
      expect(r.refusal, MultipleRefusal.baseNaoPositiva);
    });

    test('patrimônio negativo tira o P/VP', () {
      final r = PeerValuation.readings(
        latest: exercicio(patrimonio: -200),
        shares: 1000,
        peers: pares(pvp: 1.2),
      ).firstWhere((r) => r.kind == MultipleKind.precoPatrimonio);
      expect(r.refusal, MultipleRefusal.baseNaoPositiva);
    });

    test('instituição financeira não usa EV/EBITDA', () {
      // Depósito e captação são insumo do negócio, e não financiamento
      // (decisão 102): a ponte de dívida líquida não descreve banco.
      final r = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(evEbitda: 6.0),
        sectorKey: 'financeiro',
        industry: 'Intermediários Financeiros',
      ).firstWhere((r) => r.kind == MultipleKind.firmaEbitda);
      expect(r.refusal, MultipleRefusal.instituicaoFinanceira);

      // E o setor econômico sozinho **não** basta: na taxonomia oficial da B3
      // ele reúne banco, seguradora e administradora, e quem separa é o
      // subsetor (decisão 87). Sem ele, o múltiplo entra.
      final semSubsetor = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(evEbitda: 6.0),
        sectorKey: 'financeiro',
      ).firstWhere((r) => r.kind == MultipleKind.firmaEbitda);
      expect(semSubsetor.applied, isTrue);
    });

    test('grupo pequeno demais não produz mediana usável', () {
      final r = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(pl: 9.0, n: PeerValuation.minimumPeers - 1),
      ).first;
      expect(r.refusal, MultipleRefusal.paresInsuficientes);
    });

    test('a ponte que deixa o acionista negativo é recusada, e não invertida',
        () {
      final r = PeerValuation.readings(
        latest: exercicio(ebitda: 100, divida: 9000, caixa: 0),
        shares: 1000,
        peers: pares(evEbitda: 6.0),
      ).firstWhere((r) => r.kind == MultipleKind.firmaEbitda);
      expect(r.refusal, MultipleRefusal.ponteNaoPositiva);
      expect(r.fairValuePerShare, isNull);
    });
  });

  group('O consolidado é mediana, e a divergência é declarada', () {
    test('mediana das aplicadas, e o fora da curva não arrasta', () {
      final rs = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(pl: 9.0, pvp: 1.2, evEbitda: 60.0),
      );
      // 9,00 / 9,60 / 141,90 — a mediana é 9,60, e a média seria 53,50.
      expect(PeerValuation.consolidated(rs), closeTo(9.6, 1e-9));
    });

    test('a divergência é múltiplos ÷ DCF − 1', () {
      final rs = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(pl: 9.0),
      );
      expect(
        PeerValuation.divergence(readings: rs, dcfFairValue: 6.0),
        closeTo(9.0 / 6.0 - 1, 1e-12),
      );
    });

    test('DCF não positivo não produz divergência inventada', () {
      final rs = PeerValuation.readings(
        latest: exercicio(),
        shares: 1000,
        peers: pares(pl: 9.0),
      );
      expect(PeerValuation.divergence(readings: rs, dcfFairValue: 0),
          isNull);
    });

    test('sem leitura aplicável, não há consolidado nem divergência', () {
      final rs = PeerValuation.readings(
        latest: exercicio(lucro: -1, patrimonio: -1, ebitda: -1),
        shares: 1000,
        peers: pares(pl: 9.0, pvp: 1.2, evEbitda: 6.0),
      );
      expect(PeerValuation.consolidated(rs), isNull);
      expect(PeerValuation.divergence(readings: rs, dcfFairValue: 6.0),
          isNull);
    });

    test('o limite de divergência separa concordar de discordar', () {
      PeerTriangulation com(double dcf) => PeerTriangulation.build(
            latest: exercicio(),
            shares: 1000,
            peers: pares(pl: 9.0),
            dcfFairValue: dcf,
          )!;
      // 9,00 contra 6,20 é +45%; contra 5,80 é +55%.
      expect(com(6.2).diverges, isFalse);
      expect(com(5.8).diverges, isTrue);
    });

    test('sem pacote de pares não há triangulação', () {
      expect(
        PeerTriangulation.build(
          latest: exercicio(),
          shares: 1000,
          peers: null,
          dcfFairValue: 6.0,
        ),
        isNull,
      );
    });
  });

  group('O pacote versionado vai e volta', () {
    test('o codec lê o que a ferramenta grava', () {
      final json = <String, Object?>{
        'geradoEm': hoje.toIso8601String(),
        'porTicker': {
          'PETR4': {
            'precoLucro': {'mediana': 9.0, 'pares': 12, 'grupo': 'petroleo'},
            'precoPatrimonio': {
              'mediana': 1.2,
              'pares': 14,
              'grupo': 'petroleo',
            },
          },
        },
      };
      final lido = PeerMultipleCodec.decode(json);
      expect(lido.keys, ['PETR4']);
      final s = lido['PETR4']!;
      expect(s.asOf, hoje);
      expect(s.byKind[MultipleKind.precoLucro]!.median, 9.0);
      expect(s.byKind[MultipleKind.precoLucro]!.peers, 12);
      expect(s.byKind.containsKey(MultipleKind.firmaEbitda), isFalse);
    });

    test('pacote ilegível desliga a triangulação em vez de explodir', () {
      expect(PeerMultipleCodec.decode(const {}), isEmpty);
      expect(PeerMultipleCodec.decode(const {'porTicker': 7}), isEmpty);
      expect(
        PeerMultipleCodec.decode(const {
          'geradoEm': 'nem data',
          'porTicker': {'PETR4': {}},
        }),
        isEmpty,
      );
    });

    test('mediana não positiva no pacote é descartada, e não usada', () {
      final lido = PeerMultipleCodec.decode({
        'geradoEm': hoje.toIso8601String(),
        'porTicker': {
          'PETR4': {
            'precoLucro': {'mediana': -3.0, 'pares': 12, 'grupo': 'x'},
            'precoPatrimonio': {'mediana': 1.2, 'pares': 12, 'grupo': 'x'},
          },
        },
      });
      expect(lido['PETR4']!.byKind.containsKey(MultipleKind.precoLucro),
          isFalse);
      expect(lido['PETR4']!.byKind.containsKey(MultipleKind.precoPatrimonio),
          isTrue);
    });
  });
}
