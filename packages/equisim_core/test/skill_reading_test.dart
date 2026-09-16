import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _leitura({
  num ic = 0.1,
  Object? t = 0.5,
  num critico = 2.7,
  num nw = 1.0,
}) =>
    {'ic': ic, 'tCorrigido': t, 'critico': critico, 'tNeweyWest': nw};

Map<String, dynamic> _pacote({
  Object? versao = 2,
  Object? t = 0.2431,
  Object? critico = 2.705,
  Object? nw = 0.6894,
  Map<String, Object?>? composto,
  Map<String, Object?>? bm,
  Map<String, Object?>? potencial,
}) =>
    {
      'versao': versao,
      'horizonteMeses': 36,
      'coortes': 22,
      'potencialDadoBookToMarket': {
        'coeficiente': 0.0297,
        'tCorrigido': t,
        'critico': critico,
        'tNeweyWest': nw,
      },
      'ordenacoes': {
        'composto': composto ?? _leitura(ic: 0.15),
        'bookToMarket': bm ?? _leitura(ic: 0.181, t: 2.92, nw: 7.03),
        'potencial': potencial ?? _leitura(ic: 0.091, t: 0.74, nw: 1.89),
      },
    };

void main() {
  group('Leitura da habilidade — itens B1.0 e B1', () {
    test('lê o pacote, com as três ordenações', () {
      final s = SkillReadingCodec.decode(_pacote())!;
      expect(s.months, 36);
      expect(s.cohorts, 22);
      expect(s.conditionalCoefficient, 0.0297);
      expect(s.overlapT, 0.2431);
      expect(s.demonstrated, isFalse);
      expect(s.potentialIc, 0.091);
      expect(s.bookToMarketIc, 0.181);
      expect(s.orderings[TransversalOrdering.composite]!.ic, 0.15);
    });

    test('o critério da decisão 96 exige os dois t, e estritamente', () {
      OrderingReading com(double t, double nw) =>
          OrderingReading(ic: 0.1, overlapT: t, overlapCritical: 2.7, neweyWestT: nw);
      expect(com(2.71, 2.01).demonstrated, isTrue);
      expect(com(2.71, 2.0).demonstrated, isFalse,
          reason: 'o corrigido passa e o Newey-West não');
      expect(com(2.7, 3.5).demonstrated, isFalse,
          reason: 'o Newey-West passa e o corrigido fica no crítico');
    });

    group('a regra do prêmio, fixada antes de medir', () {
      TransversalOrdering? premio({
        required bool composto,
        required bool bm,
        required bool potencial,
      }) {
        Map<String, Object?> l(bool passa) =>
            passa ? _leitura(t: 3.0, nw: 2.5) : _leitura(t: 1.0, nw: 1.0);
        return SkillReadingCodec.decode(_pacote(
          composto: l(composto),
          bm: l(bm),
          potencial: l(potencial),
        ))!
            .premiumOrdering;
      }

      test('o composto vem primeiro, quando passa', () {
        expect(premio(composto: true, bm: true, potencial: true),
            TransversalOrdering.composite);
      });
      test('sem o composto, o book-to-market', () {
        expect(premio(composto: false, bm: true, potencial: true),
            TransversalOrdering.bookToMarket);
      });
      test('só o potencial passando, o potencial', () {
        expect(premio(composto: false, bm: false, potencial: true),
            TransversalOrdering.potential);
      });
      test('nenhuma passando, nenhum prêmio', () {
        expect(premio(composto: false, bm: false, potencial: false), isNull);
      });
    });

    test('pacote malformado não vira leitura: a ressalva não some por descuido',
        () {
      expect(SkillReadingCodec.decode(_pacote(versao: 1)), isNull);
      expect(SkillReadingCodec.decode(_pacote(t: '0,24')), isNull);
      expect(SkillReadingCodec.decode(_pacote(nw: null)), isNull);
      expect(SkillReadingCodec.decode(_pacote(critico: double.nan)), isNull);
      expect(SkillReadingCodec.decode(_pacote(bm: _leitura(t: double.infinity))),
          isNull);
      final semComposto = _pacote()..['ordenacoes'] = {'bookToMarket': _leitura()};
      expect(SkillReadingCodec.decode(semComposto), isNull,
          reason: 'as três ordenações precisam estar no pacote');
      expect(SkillReadingCodec.decode({'versao': 2}), isNull);
    });
  });
}
