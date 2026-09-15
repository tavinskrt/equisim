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
      final b = CalibratedBand.around(const Money(1000), t)!;
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
      expect(CalibratedBand.around(Money.zero, t), isNull);
      expect(CalibratedBand.around(const Money(-500), t), isNull);
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
      expect(t.lowerFactor, 0.5);
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
}
