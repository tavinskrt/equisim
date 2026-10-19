// A composição declarada das units, do formulário cadastral da CVM (item B16).
//
// Cada caso de leitura de texto é uma linha **real** da FCA, copiada do
// arquivo: a coluna é texto livre, e o que garante que o leitor serve é ele
// acertar as dezoito formas que as companhias de fato escreveram.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Leitura do texto declarado', () {
    test('as nove units do universo saem com a composição certa', () {
      // Cada string é a linha da FCA da companhia, com o ano em comentário.
      const declared = <String, ({String text, int shares})>{
        'ALUP11': (text: '1 ON E 2 PN', shares: 3),
        'BPAC11': (text: '1 ON E 2 PNA', shares: 3),
        'BRBI11': (text: '2 ações preferenciais e 1 ação ordinária', shares: 3),
        'ENGI11': (text: '1 ação ordinária e 4 ações preferenciais', shares: 5),
        'IGTI11': (text: '1 ON e 2 PN', shares: 3),
        'KLBN11': (text: '1 KLBN3 + 4 KLBN4', shares: 5),
        'SANB11': (text: '1 ON + 1 PN', shares: 2),
        'SAPR11': (text: '1 ON e 4 PN', shares: 5),
        'TAEE11': (text: '1 ON / 2 PN', shares: 3),
      };
      for (final e in declared.entries) {
        expect(UnitCompositionCodec.parse(e.value.text), e.value.shares,
            reason: e.key);
      }
    });

    test('código de três letras conta, e a ENGI11 de 2018 é o caso', () {
      // A FCA de 2018 declara "1 ENG3 e 4 ENGI4": exigir quatro letras no
      // código somava só o 4, e a unit saía com uma ação a menos.
      expect(UnitCompositionCodec.parse('1 ENG3 e 4 ENGI4'), 5);
      expect(UnitCompositionCodec.parse('1 VVAR3 + 2 VVAR4'), 3);
    });

    test('recibo de subscrição não é ação', () {
      // A BMGB11 declara "1 PN + 3 Recibos de Subscrição" e tem **uma** ação.
      expect(UnitCompositionCodec.parse('1 PN + 3 Recibos de Subscrição'), 1);
    });

    test('texto sem espécie reconhecível devolve nulo', () {
      expect(UnitCompositionCodec.parse(''), isNull);
      expect(UnitCompositionCodec.parse('Vide item 9.1'), isNull);
    });

    test('composição acima do teto é recusada, e não confinada', () {
      // Confinar devolveria um divisor plausível para um texto que o leitor
      // não entendeu. Recusar manda quem chama recuar para a razão medida.
      expect(UnitCompositionCodec.parse('11 ON + 3 PN'), isNull);
      expect(UnitCompositionCodec.parse('6 ON + 4 PN'), 10);
    });
  });

  group('O formulário vigente na data', () {
    final series = [
      const UnitComposition(year: 2018, shares: 4, declared: '1 ON + 3 PN'),
      const UnitComposition(year: 2021, shares: 5, declared: '1 ON + 4 PN'),
      const UnitComposition(year: 2024, shares: 3, declared: '1 ON + 2 PN'),
    ];

    test('vale o mais recente até a data, e nunca um posterior', () {
      expect(UnitCompositionCodec.at(series, DateTime(2019, 6, 30))?.shares, 4);
      expect(UnitCompositionCodec.at(series, DateTime(2021, 1, 1))?.shares, 5);
      expect(UnitCompositionCodec.at(series, DateTime(2023, 12, 31))?.shares, 5,
          reason: 'o formulário de 2024 seria conhecimento futuro em 2023');
      expect(UnitCompositionCodec.at(series, DateTime(2026, 9, 14))?.shares, 3);
    });

    test('antes do primeiro formulário não há composição', () {
      expect(UnitCompositionCodec.at(series, DateTime(2017, 12, 31)), isNull);
    });
  });

  group('Pacote', () {
    test('ida e volta preserva ano, contagem e texto', () {
      final package = UnitCompositionCodec.encodePackage(
        {
          'SAPR11': [
            const UnitComposition(year: 2025, shares: 5, declared: '1 ON e 4 PN'),
          ],
        },
        generatedAt: DateTime(2026, 9, 14),
      );
      final parsed = UnitCompositionCodec.decodePackage(package);
      expect(parsed['SAPR11'], hasLength(1));
      expect(parsed['SAPR11']!.single.shares, 5);
      expect(parsed['SAPR11']!.single.year, 2025);
      expect(parsed['SAPR11']!.single.declared, '1 ON e 4 PN');
    });

    test('entrada malformada é pulada, e não derruba a leitura', () {
      final parsed = UnitCompositionCodec.decodePackage({
        'versao': UnitCompositionCodec.version,
        'units': {
          'AAAA11': [
            {'ano': 2025, 'acoes': 0},
            {'ano': 2024, 'acoes': 99},
            {'ano': 2023, 'acoes': 3, 'texto': '1 ON + 2 PN'},
          ],
          'BBBB11': 'lixo',
        },
      });
      expect(parsed.keys, ['AAAA11']);
      expect(parsed['AAAA11']!.single.shares, 3);
    });

    test('pacote sem units devolve mapa vazio', () {
      expect(UnitCompositionCodec.decodePackage(const {}), isEmpty);
    });
  });
}
