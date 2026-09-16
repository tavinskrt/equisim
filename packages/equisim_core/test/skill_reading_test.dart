import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _pacote({
  Object? versao = 1,
  Object? t = 0.2421,
  Object? critico = 2.705,
  Object? nw = 0.6869,
  Object? icPotencial = 0.0911,
}) =>
    {
      'versao': versao,
      'horizonteMeses': 36,
      'coortes': 22,
      'potencialDadoBookToMarket': {
        'coeficiente': 0.0295,
        'tCorrigido': t,
        'critico': critico,
        'tNeweyWest': nw,
      },
      'icPotencial': icPotencial,
      'icBookToMarket': 0.1813,
    };

void main() {
  group('Leitura da habilidade — item B1.0', () {
    test('lê o pacote', () {
      final s = SkillReadingCodec.decode(_pacote())!;
      expect(s.months, 36);
      expect(s.cohorts, 22);
      expect(s.conditionalCoefficient, 0.0295);
      expect(s.overlapT, 0.2421);
      expect(s.overlapCritical, 2.705);
      expect(s.neweyWestT, 0.6869);
      expect(s.potentialIc, 0.0911);
      expect(s.bookToMarketIc, 0.1813);
      expect(s.demonstrated, isFalse);
    });

    test('o critério da decisão 96 exige os dois t, e estritamente', () {
      SkillReading com(double t, double nw) =>
          SkillReadingCodec.decode(_pacote(t: t, critico: 2.7, nw: nw))!;
      expect(com(2.71, 2.01).demonstrated, isTrue);
      // O corrigido passa e o Newey-West não: a decisão 96 pede os dois.
      expect(com(2.71, 2.0).demonstrated, isFalse);
      // O Newey-West passa e o corrigido fica no crítico.
      expect(com(2.7, 3.5).demonstrated, isFalse);
      expect(com(-3, -3).demonstrated, isFalse);
    });

    test('pacote malformado não vira leitura: a ressalva não some por descuido',
        () {
      expect(SkillReadingCodec.decode(_pacote(versao: 2)), isNull);
      expect(SkillReadingCodec.decode(_pacote(t: '0,24')), isNull);
      expect(SkillReadingCodec.decode(_pacote(nw: null)), isNull);
      expect(SkillReadingCodec.decode(_pacote(critico: double.nan)), isNull);
      expect(SkillReadingCodec.decode(_pacote(icPotencial: double.infinity)),
          isNull);
      expect(SkillReadingCodec.decode({'versao': 1}), isNull);
    });
  });
}
