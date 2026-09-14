import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

Map<String, dynamic> _ev(String label, String fator, String dataCom,
        {String isin = 'BRXXXXACNOR0', String emitido = ''}) =>
    {
      'assetIssued': emitido,
      'factor': fator,
      'approvedOn': '01/01/2020',
      'isinCode': isin,
      'label': label,
      'lastDatePrior': dataCom,
      'remarks': '',
    };

void main() {
  group('Números e datas da B3', () {
    test('ponto de milhar e vírgula decimal', () {
      expect(B3Registry.parseNumber('5.730.834.040'), 5730834040);
      expect(B3Registry.parseNumber('0,05000000000'), closeTo(0.05, 1e-15));
      expect(B3Registry.parseNumber('9.900,00000000000'), 9900);
      expect(B3Registry.parseNumber(''), isNull);
    });

    test('dd/mm/aaaa', () {
      expect(B3Registry.parseDate('15/04/2024'), _d(2024, 4, 15));
      expect(B3Registry.parseDate('2024-04-15'), isNull);
    });
  });

  group('Convenção do fator — conferida contra o preço', () {
    test('desdobramento e bonificação são acréscimo percentual', () {
      // BBAS3, 2024: "DESDOBRAMENTO 100" e o preço caiu pela metade.
      expect(B3Registry.multiplier('DESDOBRAMENTO', 100), 2);
      expect(B3Registry.multiplier('DESDOBRAMENTO', 900), 10);
      expect(B3Registry.multiplier('BONIFICACAO', 25), 1.25);
    });

    test('grupamento é multiplicador', () {
      // AERI3, 2024: "GRUPAMENTO 0,05" — 20 para 1.
      expect(B3Registry.multiplier('GRUPAMENTO', 0.05), 0.05);
    });

    test('cisão, incorporação e resgate ficam de fora', () {
      expect(B3Registry.multiplier('CIS RED CAP', 100), isNull);
      expect(B3Registry.multiplier('INCORPORACAO', 100), isNull);
      expect(B3Registry.multiplier('RESG TOTAL RV', 100), isNull);
      expect(B3Registry.multiplier('GRUPAMENTO', 0), isNull);
    });
  });

  group('Eventos', () {
    test('mesma data e ISIN se compõem', () {
      // VIVT3, 2025: grupamento de 40 para 1 e desdobramento de 1 para 80 no
      // mesmo dia — o preço caiu pela metade. Lido um a um, erra por 40x.
      final e = B3Registry.events([
        _ev('GRUPAMENTO', '0,02500000000', '14/04/2025'),
        _ev('DESDOBRAMENTO', '7.900,00000000000', '14/04/2025'),
      ]);
      expect(e, hasLength(1));
      expect(e.single.factor, closeTo(2.0, 1e-12));
      expect(e.single.labels, ['GRUPAMENTO', 'DESDOBRAMENTO']);
    });

    test('a mesma entrada repetida por papel emitido conta uma vez', () {
      final e = B3Registry.events([
        _ev('DESDOBRAMENTO', '100,00000000000', '15/04/2024', emitido: 'A'),
        _ev('DESDOBRAMENTO', '100,00000000000', '15/04/2024', emitido: 'B'),
      ]);
      expect(e.single.factor, 2);
    });

    test('ISIN diferente não se compõe', () {
      final e = B3Registry.events([
        _ev('BONIFICACAO', '10,00000000000', '23/12/2025', isin: 'BRAAAAACNOR0'),
        _ev('BONIFICACAO', '10,00000000000', '23/12/2025', isin: 'BRAAAAACNPR0'),
      ]);
      expect(e, hasLength(2));
    });

    test('a data ex é o dia útil seguinte à data-com', () {
      // Sexta 12/09/2025 → segunda 15/09/2025.
      final sexta = B3Registry.events([_ev('BONIFICACAO', '10', '12/09/2025')]);
      expect(sexta.single.exDate, _d(2025, 9, 15));
      // Sexta antes do Carnaval de 2024 → quarta de cinzas.
      final carnaval = B3Registry.events([_ev('BONIFICACAO', '10', '09/02/2024')]);
      expect(carnaval.single.exDate, _d(2024, 2, 14));
    });
  });

  group('Emissor', () {
    final json = {
      'code': 'BBAS',
      'totalNumberShares': '5.730.834.040',
      'numberCommonShares': '5.730.834.040',
      'numberPreferredShares': '0',
      'stockDividends': [
        _ev('DESDOBRAMENTO', '100,00000000000', '15/04/2024',
            isin: 'BRBBASACNOR3'),
        _ev('GRUPAMENTO', '0,00100000000', '23/01/2004', isin: 'BRBBASACNOR3'),
      ],
    };

    test('lê contagem e eventos', () {
      final e = B3Registry.issuer(json, consultedOn: _d(2026, 9, 14))!;
      expect(e.code, 'BBAS');
      expect(e.totalShares, 5730834040);
      expect(e.events, hasLength(2));
      expect(e.events.first.exDate.isBefore(e.events.last.exDate), isTrue);
    });

    test('fator entre duas datas compõe só os eventos no intervalo', () {
      final e = B3Registry.issuer(json, consultedOn: _d(2026, 9, 14))!;
      expect(e.factorBetween('BRBBASACNOR3', _d(2023, 12, 31), _d(2026, 9, 14)), 2);
      expect(e.factorBetween('BRBBASACNOR3', _d(2024, 12, 31), _d(2026, 9, 14)), 1);
      expect(e.factorBetween('BRBBASACNPR0', _d(2023, 12, 31), _d(2026, 9, 14)), 1,
          reason: 'outro ISIN');
    });

    test('sem código não é emissor', () {
      expect(B3Registry.issuer({'code': ''}, consultedOn: _d(2026, 9, 14)), isNull);
    });
  });

  group('Pacote', () {
    test('ida e volta preserva contagem e eventos', () {
      final e = B3Registry.issuer({
        'code': 'VIVT',
        'totalNumberShares': '1.624.086.235',
        'stockDividends': [
          _ev('GRUPAMENTO', '0,02500000000', '14/04/2025'),
          _ev('DESDOBRAMENTO', '7.900,00000000000', '14/04/2025'),
        ],
      }, consultedOn: _d(2026, 9, 14))!;
      final pacote = B3RegistryCodec.encodePackage([e], geradoEm: _d(2026, 9, 14));
      final lido = B3RegistryCodec.decodePackage(pacote)['VIVT']!;
      expect(lido.totalShares, e.totalShares);
      expect(lido.consultedOn, _d(2026, 9, 14));
      expect(lido.events.single.factor, closeTo(2, 1e-12));
      expect(lido.events.single.exDate, e.events.single.exDate);
    });

    test('versão desconhecida não é lida pela metade', () {
      expect(B3RegistryCodec.decodePackage({'versao': 99, 'emissores': {}}), isEmpty);
    });
  });
}
