import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _faixa({
  int meses = 12,
  num nominal = 0.8,
  num inferior = 0.6248,
  num superior = 9.2125,
  Object? fora = 0.803,
}) =>
    {
      'meses': meses,
      'nominal': nominal,
      'fatorInferior': inferior,
      'fatorSuperior': superior,
      'observacoes': 730,
      'primeiraCoorte': 2018,
      'ultimaCoorte': 2024,
      'coberturaForaDaAmostra': fora,
      'observacoesForaDaAmostra': 651,
    };

void main() {
  group('Faixa calibrada — item C2', () {
    test('as bordas são o preço justo vezes os fatores, em centavos', () {
      final t = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [_faixa()],
      }).single;
      final b = CalibratedBand.of(const Money(1000), t)!;
      // R$ 10,00 × 0,6248 = R$ 6,248 → 625 centavos; × 9,2125 → 9.212,5 →
      // 9.213, com o meio afastado de zero de `Money`.
      expect(b.low.cents, 625);
      expect(b.high.cents, 9213);
    });

    test('preço justo não positivo não tem faixa: a razão não foi medida ali',
        () {
      final t = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [_faixa()],
      }).single;
      expect(CalibratedBand.of(Money.zero, t), isNull);
      expect(CalibratedBand.of(const Money(-500), t), isNull);
    });

    test('a seleção compara a frequência com folga, não por igualdade', () {
      final tabelas = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [
          _faixa(nominal: 0.9, inferior: 0.43, superior: 17),
          _faixa(nominal: 0.8),
          _faixa(meses: 36, nominal: 0.8, inferior: 0.5, superior: 9.5),
        ],
      });
      // 0,7 + 0,1 não é exatamente 0,8 em ponto flutuante.
      final t = CalibratedBand.select(tabelas, months: 36, nominal: 0.7 + 0.1);
      expect(t, isNotNull);
      expect(t!.months, 36);
      expect((t as FairValueBandTable).lowerFactor, 0.5);
      expect(CalibratedBand.select(tabelas, months: 24, nominal: 0.8), isNull);
    });

    test('faixa malformada ou fora de ordem é descartada, e não inventada', () {
      final tabelas = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [
          _faixa(inferior: 2, superior: 1),
          _faixa(inferior: 0, superior: 1),
          {'meses': '12'},
          'lixo',
          _faixa(fora: 'alto'),
          _faixa(fora: null),
        ],
      });
      expect(tabelas, hasLength(1));
      expect(tabelas.single.outOfSampleCoverage, isNull);
    });

    test('versão desconhecida não é lida', () {
      expect(
        CalibratedBandCodec.decode({
          'versao': 2,
          'faixas': [_faixa()],
        }),
        isEmpty,
      );
    });
  });

  group('Volatilidade do papel — a escala da forma do C2b', () {
    /// Fechamentos que sobem e descem pelo mesmo logaritmo, [passos] vezes.
    List<double> alternando(double inicio, double passo, int passos) {
      final v = [inicio];
      for (var i = 0; i < passos; i++) {
        v.add(v.last * math.exp(i.isEven ? passo : -passo));
      }
      return v;
    }

    PriceSeries serie(List<double> fechamentos) => PriceSeries(
          ticker: Ticker.parse('PETR4'),
          points: [
            for (final (i, c) in fechamentos.indexed)
              PricePoint(date: DateTime(2024, 1, 1).add(Duration(days: i)), close: c),
          ],
        );

    test('lê só os últimos 252 pregões, pelo desvio amostral anualizado', () {
      // 47 retornos de ±5% e depois 252 de ±1%: a janela vê só os de ±1%.
      // Média zero, variância amostral 252·0,01²/251, anualizada por √252.
      final antigos = alternando(100, 0.05, 47);
      final recentes = alternando(antigos.last, 0.01, 252).skip(1);
      final v = CalibratedBand.trailingVolatility(serie([...antigos, ...recentes]))!;
      expect(v, closeTo(0.01 * math.sqrt(252 / 251) * math.sqrt(252), 1e-12));
    });

    test('com menos de 120 retornos o papel fica sem volatilidade', () {
      expect(CalibratedBand.trailingVolatility(serie(alternando(10, 0.02, 119))),
          isNull);
      expect(CalibratedBand.trailingVolatility(serie(alternando(10, 0.02, 120))),
          isNotNull);
    });

    test('fechamento não positivo não forma retorno', () {
      // 130 retornos de ±2% e um zero no meio: os dois pares que tocam o zero
      // saem, e sobram 128 — com média e variância recalculadas sobre eles.
      final f = alternando(10, 0.02, 130)..[60] = 0;
      final v = CalibratedBand.trailingVolatility(serie(f))!;
      final r = <double>[
        for (var i = 1; i < f.length; i++)
          if (f[i - 1] > 0 && f[i] > 0) math.log(f[i] / f[i - 1]),
      ];
      expect(r, hasLength(128));
      final m = r.reduce((a, b) => a + b) / r.length;
      final s2 = r.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (r.length - 1);
      expect(v, closeTo(math.sqrt(s2 * 252), 1e-12));
    });
  });

  group('Faixa na escala da volatilidade — item C2b', () {
    Map<String, dynamic> pacote({
      Object? a = 0.079914,
      Object? b = 0.027969,
      Object? zi = -1.595952,
      Object? zs = 1.640003,
      int versao = 2,
    }) =>
        {
          'versao': versao,
          'forma': 'convergenciaNaVolatilidade',
          'faixas': [
            {
              'meses': 12,
              'nominal': 0.9,
              'a': a,
              'b': b,
              'zInferior': zi,
              'zSuperior': zs,
              'observacoes': 3517,
              'primeiraCoorte': 2018,
              'ultimaCoorte': 2025,
              'coberturaForaDaAmostra': 0.879,
              'observacoesForaDaAmostra': 3136,
            }
          ],
        };

    test('a faixa é o preço de hoje pelo centro medido e pela volatilidade', () {
      final t = CalibratedBandCodec.decode(pacote()).single as VolatilityBandTable;
      expect(t.b, closeTo(0.027969, 1e-9));
      final faixa = CalibratedBand.of(
        Money.fromReais(20),
        t,
        marketPrice: Money.fromReais(10),
        volatility: 0.40,
      )!;
      // Conta à mão: centro = 0,079914 + 0,027969·ln(2) = 0,099299;
      // borda = 10·exp(centro ± 0,40·z).
      final centro = 0.079914 + 0.027969 * math.log(2);
      expect(faixa.low.reais,
          closeTo(10 * math.exp(centro + 0.40 * -1.595952), 0.005));
      expect(faixa.high.reais,
          closeTo(10 * math.exp(centro + 0.40 * 1.640003), 0.005));
    });

    test('sem volatilidade, ou sem preço de mercado, não há faixa', () {
      final t = CalibratedBandCodec.decode(pacote()).single;
      final justo = Money.fromReais(20);
      final preco = Money.fromReais(10);
      expect(CalibratedBand.of(justo, t, marketPrice: preco), isNull);
      expect(CalibratedBand.of(justo, t, volatility: 0.4), isNull);
      expect(CalibratedBand.of(justo, t, marketPrice: Money.zero, volatility: 0.4),
          isNull);
      expect(CalibratedBand.of(justo, t, marketPrice: preco, volatility: 0),
          isNull);
      expect(
          CalibratedBand.of(justo, t, marketPrice: preco, volatility: double.nan),
          isNull);
      expect(CalibratedBand.of(Money.zero, t, marketPrice: preco, volatility: 0.4),
          isNull);
    });

    test('faixa malformada ou versão desconhecida não vira faixa', () {
      expect(CalibratedBandCodec.decode(pacote(a: '0,08')), isEmpty);
      expect(CalibratedBandCodec.decode(pacote(zi: null)), isEmpty);
      // Bordas fora de ordem.
      expect(CalibratedBandCodec.decode(pacote(zi: 2.0, zs: -2.0)), isEmpty);
      expect(CalibratedBandCodec.decode(pacote(versao: 3)), isEmpty);
      // O pacote da volatilidade não é lido como o do justo: sem `fatorInferior`
      // a faixa da versão 1 é descartada.
      expect(CalibratedBandCodec.decode(pacote(versao: 1)), isEmpty);
    });
  });
}
