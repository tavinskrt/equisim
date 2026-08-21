import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('converte reais para centavos sem erro de arredondamento', () {
      expect(Money.fromReais(10.55).cents, 1055);
      expect(Money.fromReais(0.1).cents, 10);
      expect(Money.fromReais(1 / 3).cents, 33);
    });

    test('somas repetidas não acumulam erro de ponto flutuante', () {
      // Em double, somar 0,10 dez vezes produz 0.9999999999999999.
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total = total + Money.fromReais(0.10);
      }
      expect(total.cents, 100);
      expect(total.reais, 1.0);
    });

    test('multiplicação por peso arredonda para o centavo', () {
      final slice = Money.fromReais(1000) * (1 / 3);
      expect(slice.cents, 33333);
    });

    test('comparações e sinal', () {
      expect(Money.fromReais(5) > Money.fromReais(3), isTrue);
      expect(Money.fromReais(-2).isPositive, isFalse);
      expect((-Money.fromReais(2)).cents, -200);
      expect(Money.zero.isZero, isTrue);
    });
  });

  group('Ticker', () {
    test('normaliza e valida formato da B3', () {
      expect(Ticker.parse(' petr4 ').value, 'PETR4');
      expect(Ticker.parse('taee11').value, 'TAEE11');
    });

    test('rejeita formatos inválidos', () {
      expect(() => Ticker.parse('PET'), throwsFormatException);
      expect(() => Ticker.parse('PETR4X'), throwsFormatException);
      expect(Ticker.tryParse('!!!'), isNull);
    });

    test('Units são ações e não recebem tratamento especial', () {
      // O universo vem de type=stock, que já exclui fundos; não há inferência
      // de classe pelo sufixo 11.
      expect(Ticker.parse('TAEE11').value, 'TAEE11');
      expect(Ticker.parse('BRBI11').value, 'BRBI11');
    });

    test('aceita dígito na raiz — B3SA3 é a própria bolsa', () {
      // Um padrão de quatro letras excluiria B3SA3 da lista de ativos.
      expect(Ticker.parse('B3SA3').value, 'B3SA3');
      expect(Ticker.tryParse('B3SA3'), isNotNull);
    });

    test('rejeita ticker do mercado fracionário', () {
      // PETR4F é o mesmo ativo que PETR4, negociado em lote fracionário.
      // Admiti-lo permitiria montar carteira com os dois como se fossem
      // empresas distintas. A fonte lista 403 deles em type=stock.
      expect(Ticker.tryParse('PETR4F'), isNull);
      expect(Ticker.tryParse('BBAS3F'), isNull);
      expect(Ticker.tryParse('VALE3F'), isNull);
    });

    test('rejeita classes especiais com sufixo de letra', () {
      expect(Ticker.tryParse('MRSA6B'), isNull);
      expect(Ticker.tryParse('EQMA3B'), isNull);
    });

    test('primeiro caractere precisa ser letra', () {
      expect(Ticker.tryParse('3PTR4'), isNull);
    });

    test('igualdade por valor', () {
      expect(Ticker.parse('VALE3'), equals(Ticker.parse('vale3')));
    });
  });

  group('Weights', () {
    test('distribuição igualitária soma exatamente 1,0', () {
      for (final n in [1, 3, 7, 15]) {
        final tickers =
            List.generate(n, (i) => Ticker.parse('AAAA$i'));
        final weights = Weights.equal(tickers);
        expect(
          Weights.sum(weights.values),
          closeTo(1.0, 1e-12),
          reason: 'falhou com $n ativos',
        );
        expect(Weights.sumsToOne(weights.values), isTrue);
      }
    });

    test('três ativos: resíduo de 1/3 é absorvido, não perdido', () {
      final tickers = [
        Ticker.parse('PETR4'),
        Ticker.parse('VALE3'),
        Ticker.parse('ITUB4'),
      ];
      final weights = Weights.equal(tickers);
      expect(Weights.sum(weights.values), closeTo(1.0, 1e-15));
    });

    test('normalize reescala pesos arbitrários para 100%', () {
      final normalized = Weights.normalize({
        Ticker.parse('PETR4'): 2.0,
        Ticker.parse('VALE3'): 3.0,
        Ticker.parse('ITUB4'): 5.0,
      });
      expect(Weights.sum(normalized.values), closeTo(1.0, 1e-12));
      expect(normalized[Ticker.parse('ITUB4')]!.value, closeTo(0.5, 1e-9));
    });

    test('rejeita peso fora do intervalo', () {
      expect(() => Weight.fraction(1.5), throwsArgumentError);
      expect(() => Weight.fraction(-0.1), throwsArgumentError);
    });
  });

  group('DateRange', () {
    test('calcula anos e meses', () {
      final range = DateRange(DateTime(2020, 1, 15), DateTime(2025, 1, 15));
      expect(range.years, closeTo(5.0, 0.02));
      expect(range.months, 60);
    });

    test('rejeita intervalo invertido', () {
      expect(
        () => DateRange(DateTime(2025), DateTime(2020)),
        throwsArgumentError,
      );
    });
  });
}
