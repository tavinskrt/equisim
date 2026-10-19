import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _band({
  int months = 12,
  num nominal = 0.8,
  num lower = 0.6248,
  num upper = 9.2125,
  Object? outside = 0.803,
}) =>
    {
      'meses': months,
      'nominal': nominal,
      'fatorInferior': lower,
      'fatorSuperior': upper,
      'observacoes': 730,
      'primeiraCoorte': 2018,
      'ultimaCoorte': 2024,
      'coberturaForaDaAmostra': outside,
      'observacoesForaDaAmostra': 651,
    };

void main() {
  group('Faixa calibrada — item C2', () {
    test('as bordas são o preço justo vezes os fatores, em centavos', () {
      final t = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [_band()],
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
        'faixas': [_band()],
      }).single;
      expect(CalibratedBand.of(Money.zero, t), isNull);
      expect(CalibratedBand.of(const Money(-500), t), isNull);
    });

    test('a seleção compara a frequência com folga, não por igualdade', () {
      final tables = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [
          _band(nominal: 0.9, lower: 0.43, upper: 17),
          _band(nominal: 0.8),
          _band(months: 36, nominal: 0.8, lower: 0.5, upper: 9.5),
        ],
      });
      // 0,7 + 0,1 não é exatamente 0,8 em ponto flutuante.
      final t = CalibratedBand.select(tables, months: 36, nominal: 0.7 + 0.1);
      expect(t, isNotNull);
      expect(t!.months, 36);
      expect((t as FairValueBandTable).lowerFactor, 0.5);
      expect(CalibratedBand.select(tables, months: 24, nominal: 0.8), isNull);
    });

    test('faixa malformada ou fora de ordem é descartada, e não inventada', () {
      final tables = CalibratedBandCodec.decode({
        'versao': 1,
        'faixas': [
          _band(lower: 2, upper: 1),
          _band(lower: 0, upper: 1),
          {'meses': '12'},
          'lixo',
          _band(outside: 'alto'),
          _band(outside: null),
        ],
      });
      expect(tables, hasLength(1));
      expect(tables.single.outOfSampleCoverage, isNull);
    });

    test('versão desconhecida não é lida', () {
      expect(
        CalibratedBandCodec.decode({
          'versao': 2,
          'faixas': [_band()],
        }),
        isEmpty,
      );
    });
  });

  group('Volatilidade do papel — a escala da forma do C2b', () {
    /// Fechamentos que sobem e descem pelo mesmo logaritmo, [stepCount] vezes.
    List<double> alternating(double start, double step, int stepCount) {
      final v = [start];
      for (var i = 0; i < stepCount; i++) {
        v.add(v.last * math.exp(i.isEven ? step : -step));
      }
      return v;
    }

    PriceSeries series(List<double> closes) => PriceSeries(
          ticker: Ticker.parse('PETR4'),
          points: [
            for (final (i, c) in closes.indexed)
              PricePoint(date: DateTime(2024, 1, 1).add(Duration(days: i)), close: c),
          ],
        );

    test('lê só os últimos 252 pregões, pelo desvio amostral anualizado', () {
      // 47 retornos de ±5% e depois 252 de ±1%: a janela vê só os de ±1%.
      // Média zero, variância amostral 252·0,01²/251, anualizada por √252.
      final old = alternating(100, 0.05, 47);
      final recent = alternating(old.last, 0.01, 252).skip(1);
      final v = CalibratedBand.trailingVolatility(series([...old, ...recent]))!;
      expect(v, closeTo(0.01 * math.sqrt(252 / 251) * math.sqrt(252), 1e-12));
    });

    test('com menos de 120 retornos o papel fica sem volatilidade', () {
      expect(CalibratedBand.trailingVolatility(series(alternating(10, 0.02, 119))),
          isNull);
      expect(CalibratedBand.trailingVolatility(series(alternating(10, 0.02, 120))),
          isNotNull);
    });

    test('fechamento não positivo não forma retorno', () {
      // 130 retornos de ±2% e um zero no meio: os dois pares que tocam o zero
      // saem, e sobram 128 — com média e variância recalculadas sobre eles.
      final f = alternating(10, 0.02, 130)..[60] = 0;
      final v = CalibratedBand.trailingVolatility(series(f))!;
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
    Map<String, dynamic> package({
      Object? a = 0.079914,
      Object? b = 0.027969,
      Object? zLower = -1.595952,
      Object? zUpper = 1.640003,
      int version = 2,
    }) =>
        {
          'versao': version,
          'forma': 'convergenciaNaVolatilidade',
          'faixas': [
            {
              'meses': 12,
              'nominal': 0.9,
              'a': a,
              'b': b,
              'zInferior': zLower,
              'zSuperior': zUpper,
              'observacoes': 3517,
              'primeiraCoorte': 2018,
              'ultimaCoorte': 2025,
              'coberturaForaDaAmostra': 0.879,
              'observacoesForaDaAmostra': 3136,
            }
          ],
        };

    test('a faixa é o preço de hoje pelo centro medido e pela volatilidade', () {
      final t = CalibratedBandCodec.decode(package()).single as VolatilityBandTable;
      expect(t.b, closeTo(0.027969, 1e-9));
      final band = CalibratedBand.of(
        Money.fromReais(20),
        t,
        marketPrice: Money.fromReais(10),
        volatility: 0.40,
      )!;
      // Conta à mão: centro = 0,079914 + 0,027969·ln(2) = 0,099299;
      // borda = 10·exp(centro ± 0,40·z).
      final center = 0.079914 + 0.027969 * math.log(2);
      expect(band.low.reais,
          closeTo(10 * math.exp(center + 0.40 * -1.595952), 0.005));
      expect(band.high.reais,
          closeTo(10 * math.exp(center + 0.40 * 1.640003), 0.005));
    });

    test('sem volatilidade, ou sem preço de mercado, não há faixa', () {
      final t = CalibratedBandCodec.decode(package()).single;
      final fairValue = Money.fromReais(20);
      final price = Money.fromReais(10);
      expect(CalibratedBand.of(fairValue, t, marketPrice: price), isNull);
      expect(CalibratedBand.of(fairValue, t, volatility: 0.4), isNull);
      expect(CalibratedBand.of(fairValue, t, marketPrice: Money.zero, volatility: 0.4),
          isNull);
      expect(CalibratedBand.of(fairValue, t, marketPrice: price, volatility: 0),
          isNull);
      expect(
          CalibratedBand.of(fairValue, t, marketPrice: price, volatility: double.nan),
          isNull);
      expect(CalibratedBand.of(Money.zero, t, marketPrice: price, volatility: 0.4),
          isNull);
    });

    test('faixa malformada ou versão desconhecida não vira faixa', () {
      expect(CalibratedBandCodec.decode(package(a: '0,08')), isEmpty);
      expect(CalibratedBandCodec.decode(package(zLower: null)), isEmpty);
      // Bordas fora de ordem.
      expect(CalibratedBandCodec.decode(package(zLower: 2.0, zUpper: -2.0)), isEmpty);
      expect(CalibratedBandCodec.decode(package(version: 3)), isEmpty);
      // O pacote da volatilidade não é lido como o do justo: sem `fatorInferior`
      // a faixa da versão 1 é descartada.
      expect(CalibratedBandCodec.decode(package(version: 1)), isEmpty);
    });
  });
}
