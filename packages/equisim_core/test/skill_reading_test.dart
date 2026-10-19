import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _reading({
  num ic = 0.1,
  Object? t = 0.5,
  num critical = 2.7,
  num nw = 1.0,
}) =>
    {'ic': ic, 'tCorrigido': t, 'critico': critical, 'tNeweyWest': nw};

Map<String, dynamic> _package({
  Object? version = 2,
  Object? t = 0.2431,
  Object? critical = 2.705,
  Object? nw = 0.6894,
  Map<String, Object?>? composite,
  Map<String, Object?>? bm,
  Map<String, Object?>? upside,
}) =>
    {
      'versao': version,
      'horizonteMeses': 36,
      'coortes': 22,
      'potencialDadoBookToMarket': {
        'coeficiente': 0.0297,
        'tCorrigido': t,
        'critico': critical,
        'tNeweyWest': nw,
      },
      'ordenacoes': {
        'composto': composite ?? _reading(ic: 0.15),
        'bookToMarket': bm ?? _reading(ic: 0.181, t: 2.92, nw: 7.03),
        'potencial': upside ?? _reading(ic: 0.091, t: 0.74, nw: 1.89),
      },
    };

void main() {
  group('Leitura da habilidade — itens B1.0 e B1', () {
    test('lê o pacote, com as três ordenações', () {
      final s = SkillReadingCodec.decode(_package())!;
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
      OrderingReading withInput(double t, double nw) =>
          OrderingReading(ic: 0.1, overlapT: t, overlapCritical: 2.7, neweyWestT: nw);
      expect(withInput(2.71, 2.01).demonstrated, isTrue);
      expect(withInput(2.71, 2.0).demonstrated, isFalse,
          reason: 'o corrigido passa e o Newey-West não');
      expect(withInput(2.7, 3.5).demonstrated, isFalse,
          reason: 'o Newey-West passa e o corrigido fica no crítico');
    });

    group('a regra do prêmio, fixada antes de medir', () {
      TransversalOrdering? premium({
        required bool composite,
        required bool bm,
        required bool upside,
      }) {
        Map<String, Object?> l(bool passes) =>
            passes ? _reading(t: 3.0, nw: 2.5) : _reading(t: 1.0, nw: 1.0);
        return SkillReadingCodec.decode(_package(
          composite: l(composite),
          bm: l(bm),
          upside: l(upside),
        ))!
            .premiumOrdering;
      }

      test('o composto vem primeiro, quando passa', () {
        expect(premium(composite: true, bm: true, upside: true),
            TransversalOrdering.composite);
      });
      test('sem o composto, o book-to-market', () {
        expect(premium(composite: false, bm: true, upside: true),
            TransversalOrdering.bookToMarket);
      });
      test('só o potencial passando, o potencial', () {
        expect(premium(composite: false, bm: false, upside: true),
            TransversalOrdering.potential);
      });
      test('nenhuma passando, nenhum prêmio', () {
        expect(premium(composite: false, bm: false, upside: false), isNull);
      });
    });

    test('pacote malformado não vira leitura: a ressalva não some por descuido',
        () {
      expect(SkillReadingCodec.decode(_package(version: 1)), isNull);
      expect(SkillReadingCodec.decode(_package(t: '0,24')), isNull);
      expect(SkillReadingCodec.decode(_package(nw: null)), isNull);
      expect(SkillReadingCodec.decode(_package(critical: double.nan)), isNull);
      expect(SkillReadingCodec.decode(_package(bm: _reading(t: double.infinity))),
          isNull);
      final withoutComposite = _package()..['ordenacoes'] = {'bookToMarket': _reading()};
      expect(SkillReadingCodec.decode(withoutComposite), isNull,
          reason: 'as três ordenações precisam estar no pacote');
      expect(SkillReadingCodec.decode({'versao': 2}), isNull);
    });
  });
}
