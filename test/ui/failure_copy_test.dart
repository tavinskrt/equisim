import 'package:equisim/presentation/shared/failure_copy.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Item B21, decisão 122 — **o erro do núcleo transporta a grandeza, e a frase
/// é montada na apresentação**.
///
/// O que se cobra aqui é a fronteira: o núcleo não escreve percentual nem casa
/// decimal, e a tela consegue escrever o número sem reextraí-lo do texto nem
/// repetir a constante do lado dela.
void main() {

  group('A apresentação escreve o número, e na unidade certa', () {
    test('fração vira percentual', () {
      const f = InvalidInput(
        'Os pesos devem somar 100%.',
        field: 'weights',
        actual: 0.7,
        limit: 1.0,
        unit: QuantityUnit.fraction,
      );
      final text = FailureCopy.of(f);
      expect(text, contains('Entrada inválida'));
      expect(text, contains('70,0%'));
      expect(text, contains('100,0%'));
    });

    test('contagem vira inteiro, sem casa decimal', () {
      const f = InvalidInput(
        'Limite de ativos por carteira excedido.',
        field: 'assets',
        actual: 18,
        limit: 15,
        unit: QuantityUnit.count,
      );
      final text = FailureCopy.of(f);
      expect(text, contains('Informado: 18.'));
      expect(text, contains('Limite: 15.'));
      expect(text, isNot(contains('18,0')),
          reason: 'meio ativo não existe');
    });

    test('sem unidade declarada, a tela não inventa número', () {
      const f = InvalidInput('O prazo deve ser de ao menos um mês.',
          field: 'months');
      final text = FailureCopy.of(f);
      expect(text, contains('O prazo deve ser de ao menos um mês.'));
      expect(text, isNot(contains('Informado')));
    });

    test('sem limite, escreve só o medido', () {
      const f = InvalidInput('Regra qualquer.',
          actual: 0.42, unit: QuantityUnit.fraction);
      final text = FailureCopy.of(f);
      expect(text, contains('Informado: 42,0%.'));
      expect(text, isNot(contains('Limite')));
    });
  });
}
