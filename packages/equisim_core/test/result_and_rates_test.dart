import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('Ok carrega valor e não carrega falha', () {
      const result = Result<int>.ok(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
      expect(result.unwrap(), 42);
    });

    test('Err carrega falha e não carrega valor', () {
      const result = Result<int>.err(InvalidInput('erro'));
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, isA<InvalidInput>());
      expect(result.unwrap, throwsStateError);
    });

    test('map transforma apenas o sucesso', () {
      expect(const Result<int>.ok(2).map((v) => v * 3).unwrap(), 6);
      const failure = Result<int>.err(InvalidInput('x'));
      expect(failure.map((v) => v * 3).isErr, isTrue);
    });

    test('flatMap encadeia sem aninhar', () {
      final chained = const Result<int>.ok(2)
          .flatMap((v) => Result<String>.ok('valor $v'));
      expect(chained.unwrap(), 'valor 2');

      final shortCircuit = const Result<int>.err(InvalidInput('x'))
          .flatMap((v) => Result<String>.ok('nunca'));
      expect(shortCircuit.isErr, isTrue);
    });

    test('fold trata os dois lados', () {
      expect(
        const Result<int>.ok(5).fold((v) => 'ok $v', (f) => 'erro'),
        'ok 5',
      );
      expect(
        const Result<int>.err(InvalidInput('x'))
            .fold((v) => 'ok', (f) => 'erro: ${f.message}'),
        'erro: x',
      );
    });

    test('getOrElse devolve o padrão em caso de falha', () {
      expect(const Result<int>.ok(1).getOrElse(99), 1);
      expect(const Result<int>.err(InvalidInput('x')).getOrElse(99), 99);
    });

    test('falhas carregam contexto tipado', () {
      const quality = DataQualityFailure('divergência', observedDeviation: 0.38);
      expect(quality.observedDeviation, 0.38);
      const insufficient = InsufficientData('faltou', subject: 'PETR4');
      expect(insufficient.subject, 'PETR4');
    });
  });

  group('RateSeries', () {
    test('acumula fator composto de taxas diárias', () {
      const series = RateSeries(
        dates: [],
        rates: [0.001, 0.001, 0.001],
      );
      // 1,001³ − 1 = 0,003003001
      expect(series.accumulated, closeTo(0.003003001, 1e-12));
    });

    test('anualiza pelo número de períodos por ano', () {
      // 252 pregões a 0,0374% ao dia ≈ 9,9% ao ano.
      final rates = List<double>.filled(252, 0.000374);
      final series = RateSeries(dates: const [], rates: rates);
      expect(series.annualized(), closeTo(series.accumulated, 1e-9));
      expect(series.annualized(), closeTo(0.0988, 1e-3));
    });

    test('série vazia não quebra', () {
      const empty = RateSeries(dates: [], rates: []);
      expect(empty.isEmpty, isTrue);
      expect(empty.accumulated, 0.0);
      expect(empty.annualized(), 0.0);
    });

    test('meio ano de CDI anualiza para o dobro do acumulado, composto', () {
      final rates = List<double>.filled(126, 0.000374);
      final series = RateSeries(dates: const [], rates: rates);
      final acumulado = series.accumulated;
      final anual = series.annualized();
      // Anualizar meio ano deve dar aproximadamente (1+acum)² − 1.
      expect(anual, closeTo((1 + acumulado) * (1 + acumulado) - 1, 1e-6));
    });
  });

  group('PriceSeries', () {
    test('ordena cronologicamente mesmo com entrada fora de ordem', () {
      final series = PriceSeries(
        ticker: Ticker.parse('PETR4'),
        points: [
          PricePoint(date: DateTime(2024, 1, 3), close: 12),
          PricePoint(date: DateTime(2024, 1, 1), close: 10),
          PricePoint(date: DateTime(2024, 1, 2), close: 11),
        ],
      );
      expect(series.firstDate, DateTime(2024, 1, 1));
      expect(series.lastDate, DateTime(2024, 1, 3));
      expect(series.points.map((p) => p.close).toList(), [10, 11, 12]);
    });

    test('closeAsOf faz forward fill em dia sem pregão', () {
      final series = PriceSeries(
        ticker: Ticker.parse('PETR4'),
        points: [
          PricePoint(date: DateTime(2024, 1, 2), close: 10),
          PricePoint(date: DateTime(2024, 1, 5), close: 12),
        ],
      );
      // Dias 3 e 4 sem pregão: mantém o último fechamento conhecido.
      expect(series.closeAsOf(DateTime(2024, 1, 3)), 10);
      expect(series.closeAsOf(DateTime(2024, 1, 4)), 10);
      expect(series.closeAsOf(DateTime(2024, 1, 5)), 12);
      expect(series.closeAsOf(DateTime(2024, 1, 6)), 12);
    });

    test('closeAsOf devolve nulo antes do primeiro pregão', () {
      final series = PriceSeries(
        ticker: Ticker.parse('PETR4'),
        points: [PricePoint(date: DateTime(2024, 1, 2), close: 10)],
      );
      expect(series.closeAsOf(DateTime(2023, 12, 31)), isNull);
    });

    test('closeOn exige a data exata', () {
      final series = PriceSeries(
        ticker: Ticker.parse('PETR4'),
        points: [PricePoint(date: DateTime(2024, 1, 2), close: 10)],
      );
      expect(series.closeOn(DateTime(2024, 1, 2)), 10);
      expect(series.closeOn(DateTime(2024, 1, 3)), isNull);
    });
  });
}
