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
  group('A grandeza viaja estruturada, e não formatada', () {
    test('a soma dos pesos sai do domínio como fração, e não como frase', () {
      final r = Portfolio.weighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        allocation: {
          Asset(
            ticker: Ticker.parse('PETR4'),
            name: 'PETR4',
            sector: Sector.fromKey('energia', label: 'energia'),
          ): 0.7,
        },
      );

      expect(r.isErr, isTrue);
      final f = r.failureOrNull! as InvalidInput;
      expect(f.actual, closeTo(0.7, 1e-12));
      expect(f.limit, closeTo(1.0, 1e-12));
      expect(f.unit, QuantityUnit.fraction);
      expect(f.field, 'weights');
      // **A frase do núcleo diz a regra, e não o número medido.**
      expect(f.message, isNot(contains('70')));
      expect(f.message, contains('100%'),
          reason: 'a regra é "somar 100%", e ela é parte do diagnóstico');
    });

    test('o limite de ativos viaja como contagem', () {
      // Tickers válidos e distintos: quatro letras mais um dígito de 1 a 8.
      final muitos = {
        for (var i = 0; i < Portfolio.maxAssets + 3; i++)
          Asset(
            ticker: Ticker.parse(
                '${String.fromCharCode(65 + i ~/ 8)}AAA${i % 8 + 1}'),
            name: 'A$i',
            sector: Sector.fromKey('energia', label: 'energia'),
          ): 1 / (Portfolio.maxAssets + 3),
      };
      final r = Portfolio.weighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        allocation: muitos,
      );

      expect(r.isErr, isTrue);
      final f = r.failureOrNull! as InvalidInput;
      expect(f.unit, QuantityUnit.count);
      expect(f.limit, Portfolio.maxAssets.toDouble());
      expect(f.actual, muitos.length.toDouble());
      // **O limite não está mais chumbado na frase**: antes ele era
      // interpolado, e a tela tinha de exibir a frase pronta ou repetir a
      // constante do lado dela.
      expect(f.message, isNot(contains('${Portfolio.maxAssets}')));
    });
  });

  group('A apresentação escreve o número, e na unidade certa', () {
    test('fração vira percentual', () {
      const f = InvalidInput(
        'Os pesos devem somar 100%.',
        field: 'weights',
        actual: 0.7,
        limit: 1.0,
        unit: QuantityUnit.fraction,
      );
      final texto = FailureCopy.of(f);
      expect(texto, contains('Entrada inválida'));
      expect(texto, contains('70,0%'));
      expect(texto, contains('100,0%'));
    });

    test('contagem vira inteiro, sem casa decimal', () {
      const f = InvalidInput(
        'Limite de ativos por carteira excedido.',
        field: 'assets',
        actual: 18,
        limit: 15,
        unit: QuantityUnit.count,
      );
      final texto = FailureCopy.of(f);
      expect(texto, contains('Informado: 18.'));
      expect(texto, contains('Limite: 15.'));
      expect(texto, isNot(contains('18,0')),
          reason: 'meio ativo não existe');
    });

    test('sem unidade declarada, a tela não inventa número', () {
      const f = InvalidInput('O prazo deve ser de ao menos um mês.',
          field: 'months');
      final texto = FailureCopy.of(f);
      expect(texto, contains('O prazo deve ser de ao menos um mês.'));
      expect(texto, isNot(contains('Informado')));
    });

    test('sem limite, escreve só o medido', () {
      const f = InvalidInput('Regra qualquer.',
          actual: 0.42, unit: QuantityUnit.fraction);
      final texto = FailureCopy.of(f);
      expect(texto, contains('Informado: 42,0%.'));
      expect(texto, isNot(contains('Limite')));
    });
  });
}
