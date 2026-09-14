import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

final _ref = DateTime.utc(2026, 9, 10);

YieldCurve _curva(List<List<double>> pts) =>
    YieldCurve.of(_ref, [for (final p in pts) CurveVertex(p[0], p[1])])!;

void main() {
  group('Curva', () {
    test('plana devolve a mesma taxa em todo prazo e todo forward', () {
      final c = _curva([
        [0.5, 0.10],
        [2, 0.10],
        [5, 0.10],
        [10, 0.10],
      ]);
      for (final t in [0.25, 1.0, 3.7, 10.0, 15.0]) {
        expect(c.spotRate(t), closeTo(0.10, 1e-12), reason: 'spot $t');
      }
      for (final f in c.annualForwards(12)) {
        expect(f, closeTo(0.10, 1e-12));
      }
      expect(c.terminalRate(10), closeTo(0.10, 1e-12));
    });

    test('reproduz a taxa de cada vértice', () {
      final c = _curva([
        [0.3, 0.1356],
        [2.3, 0.1393],
        [5.3, 0.1429],
        [10.3, 0.1433],
      ]);
      for (final v in c.vertices) {
        expect(c.spotRate(v.years), closeTo(v.rate, 1e-12));
      }
    });

    test('o forward entre dois vértices fecha o fator composto', () {
      // (1+z2)^t2 = (1+z1)^t1 · (1+f)^(t2−t1)
      final c = _curva([
        [1, 0.10],
        [3, 0.12],
        [5, 0.13],
      ]);
      final f = c.forwardRate(1, 3);
      final esquerda = math.pow(1.12, 3);
      final direita = math.pow(1.10, 1) * math.pow(1 + f, 2);
      expect(direita, closeTo(esquerda, 1e-12));
    });

    test('curva inclinada: forward acima da taxa à vista', () {
      final c = _curva([
        [1, 0.05],
        [5, 0.08],
        [10, 0.10],
      ]);
      expect(c.forwardRate(4, 5), greaterThan(c.spotRate(5)));
      final fw = c.annualForwards(10);
      expect(fw.first, lessThan(fw.last));
    });

    test('além do último vértice segue o forward do último segmento', () {
      final c = _curva([
        [1, 0.10],
        [5, 0.11],
        [10, 0.12],
      ]);
      final ultimo = c.forwardRate(5, 10);
      expect(c.forwardRate(10, 11), closeTo(ultimo, 1e-12));
      expect(c.terminalRate(15), closeTo(ultimo, 1e-12));
    });

    test('antes do primeiro vértice, taxa à vista plana', () {
      final c = _curva([
        [1, 0.10],
        [5, 0.11],
        [10, 0.12],
      ]);
      expect(c.spotRate(0.5), closeTo(0.10, 1e-12));
    });
  });

  group('Montagem', () {
    test('com menos de três vértices não há curva', () {
      expect(
        YieldCurve.of(_ref, const [CurveVertex(1, 0.1), CurveVertex(5, 0.11)]),
        isNull,
        reason: 'dois pontos são a interpolação que a curva veio substituir',
      );
    });

    test('descarta o que é registro corrompido', () {
      final c = YieldCurve.of(_ref, const [
        CurveVertex(1, 0.10),
        CurveVertex(-1, 0.10),
        CurveVertex(2, double.nan),
        CurveVertex(3, 1.5),
        CurveVertex(5, 0.11),
        CurveVertex(10, 0.12),
      ])!;
      expect(c.vertices.length, 3);
    });

    test('prazo repetido fica com o primeiro informado', () {
      final c = YieldCurve.of(_ref, const [
        CurveVertex(2, 0.1393), // LTN
        CurveVertex(2, 0.1373), // NTN-F de mesmo vencimento
        CurveVertex(5, 0.14),
        CurveVertex(10, 0.143),
      ])!;
      expect(c.spotRate(2), closeTo(0.1393, 1e-12));
    });
  });

  group('Tesouro Direto', () {
    TreasuryQuote q(String tipo, DateTime venc, DateTime base, double taxa) =>
        TreasuryQuote(type: tipo, maturity: venc, baseDate: base, rate: taxa);

    final sexta = DateTime.utc(2026, 9, 11);
    final quinta = DateTime.utc(2026, 9, 10);
    List<TreasuryQuote> dia(DateTime base, double deslocamento) => [
          q(TreasuryCurve.ltn, DateTime.utc(2027, 1, 1), base, 0.1356 + deslocamento),
          q(TreasuryCurve.ltn, DateTime.utc(2029, 1, 1), base, 0.1393 + deslocamento),
          q(TreasuryCurve.ntnF, DateTime.utc(2029, 1, 1), base, 0.1373 + deslocamento),
          q(TreasuryCurve.ntnF, DateTime.utc(2037, 1, 1), base, 0.1433 + deslocamento),
          q('Tesouro Selic', DateTime.utc(2030, 1, 1), base, 0.0001),
        ];

    test('usa a data-base mais recente até a avaliação', () {
      final c = TreasuryCurve.at([...dia(quinta, 0), ...dia(sexta, 0.01)],
          DateTime.utc(2026, 9, 13))!;
      expect(c.referenceDate, sexta);
    });

    test('NUNCA olha para a frente', () {
      // Avaliando na quinta, a curva de sexta ainda nao existia.
      final c = TreasuryCurve.at([...dia(quinta, 0), ...dia(sexta, 0.01)],
          quinta)!;
      expect(c.referenceDate, quinta);
      expect(c.vertices.first.rate, closeTo(0.1356, 1e-12));
    });

    test('sem data-base na última semana, não inventa curva', () {
      expect(TreasuryCurve.at(dia(quinta, 0), DateTime.utc(2026, 9, 30)),
          isNull);
    });

    test('LTN vence a NTN-F no mesmo vencimento, e a Selic não entra', () {
      final c = TreasuryCurve.at(dia(quinta, 0), quinta)!;
      expect(c.vertices.length, 3,
          reason: 'duas LTN e uma NTN-F longa; a NTN-F de 2029 e a Selic saem');
      final dois = c.vertices.firstWhere((v) => v.years > 2 && v.years < 3);
      expect(dois.rate, closeTo(0.1393, 1e-12));
    });

    test('o prazo é em dias úteis ÷ 252, como o PU do Tesouro — decisão 79',
        () {
      final c = TreasuryCurve.at(dia(quinta, 0), quinta)!;
      // `du` conferido contra o PU das LTN de 10/09/2026: 76 e 575.
      expect(c.vertices[0].years, closeTo(76 / 252, 1e-12));
      expect(c.vertices[1].years, closeTo(575 / 252, 1e-12));
    });
  });

  group('Arquivo e pacote do Tesouro — item A2.1', () {
    test('lê a linha do prefixado, e ignora cabeçalho e outros títulos', () {
      final q = TreasuryCsv.parseLine(
          'Tesouro Prefixado;01/01/2027;10/09/2026;13,56;13,68;960,00;959,00;959,00')!;
      expect(q.type, TreasuryCurve.ltn);
      expect(q.maturity, DateTime.utc(2027, 1, 1));
      expect(q.baseDate, DateTime.utc(2026, 9, 10));
      expect(q.rate, closeTo(0.1356, 1e-12));
      expect(TreasuryCsv.parseLine('Tipo Titulo;Data Vencimento;Data Base;Taxa'), isNull);
      expect(TreasuryCsv.parseLine('Tesouro Selic;01/03/2027;10/09/2026;0,01'), isNull);
      expect(TreasuryCsv.parseLine('Tesouro Prefixado;xx;10/09/2026;13,5'), isNull);
    });

    test('a data-base de qualquer título marca o fim do bloco', () {
      expect(TreasuryCsv.baseDateOf('Tesouro Selic;01/03/2027;10/09/2026;0,01'),
          DateTime.utc(2026, 9, 10));
      expect(TreasuryCsv.baseDateOf('Tipo Titulo;Data Vencimento;Data Base'), isNull);
    });

    test('pacote de ida e volta, e versão desconhecida é lista vazia', () {
      final q = TreasuryQuote(
        type: TreasuryCurve.ntnF,
        maturity: DateTime.utc(2037, 1, 1),
        baseDate: DateTime.utc(2026, 9, 10),
        rate: 0.1433,
      );
      final json = TreasuryQuotesCodec.encode([q], geradoEm: DateTime.utc(2026, 9, 10));
      final lido = TreasuryQuotesCodec.decode(json).single;
      expect(lido.type, q.type);
      expect(lido.maturity, q.maturity);
      expect(lido.baseDate, q.baseDate);
      expect(lido.rate, q.rate);
      expect(TreasuryQuotesCodec.decode({...json, 'versao': 99}), isEmpty);
    });

    test('taxa corrompida no pacote fica de fora', () {
      final json = {
        'versao': TreasuryQuotesCodec.versao,
        'cotacoes': [
          {'tipo': TreasuryCurve.ltn, 'vencimento': '2027-01-01', 'dataBase': '2026-09-10', 'taxa': 13.56},
        ],
      };
      expect(TreasuryQuotesCodec.decode(json), isEmpty,
          reason: 'taxa em percentual, e não em fração, é registro corrompido');
    });
  });
}
