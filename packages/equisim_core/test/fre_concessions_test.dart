import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  group('Fim do contrato no texto do FRE — item A6', () {
    // Os textos são os do formulário, copiados das companhias do universo.
    test('mês por extenso, com e sem "até"', () {
      expect(FreConcessionTerm.endOf('Junho de 2042'), _d(2042, 6, 30));
      expect(FreConcessionTerm.endOf('até novembro de 2027'), _d(2027, 11, 30));
      expect(FreConcessionTerm.endOf('Até agosto de 2030.'), _d(2030, 8, 31));
      expect(FreConcessionTerm.endOf('até Julho/2025'), _d(2025, 7, 31));
      expect(FreConcessionTerm.endOf('até Fevereiro de 2016'), _d(2016, 2, 29));
      expect(FreConcessionTerm.endOf('Março de 2035'), _d(2035, 3, 31));
    });

    test('data completa, com ponto ou barra, e o intervalo vale pelo fim', () {
      expect(FreConcessionTerm.endOf('até 20.03.2033'), _d(2033, 3, 20));
      expect(FreConcessionTerm.endOf('Válido até 07/07/2045'), _d(2045, 7, 7));
      expect(FreConcessionTerm.endOf('de 08.03.2018 a 08.03.2048'),
          _d(2048, 3, 8));
      expect(FreConcessionTerm.endOf('De 11/08/2017 até 11/08/2047'),
          _d(2047, 8, 11));
      expect(FreConcessionTerm.endOf('23.09.2022'), _d(2022, 9, 23));
    });

    test('prazo contado a partir de um início', () {
      expect(FreConcessionTerm.endOf('30 anos, a partir de 03/2019'),
          _d(2049, 3, 31));
      expect(FreConcessionTerm.endOf('30 anos, a partir 06.07.1994'),
          _d(2024, 7, 6));
    });

    test('com prorrogação, vale o prazo de hoje', () {
      expect(FreConcessionTerm.endOf('2028, prorrogável até 2058'),
          _d(2028, 12, 31));
      expect(FreConcessionTerm.endOf('Até 27/08/23 (Prorr. 27/08/38)'),
          _d(2023, 8, 27));
    });

    test('recusa o que não dá data absoluta', () {
      expect(FreConcessionTerm.endOf('Prazo indeterminado'), isNull);
      expect(FreConcessionTerm.endOf('Vide item 9.1 deste formulário'), isNull);
      expect(FreConcessionTerm.endOf('6 anos'), isNull);
      expect(FreConcessionTerm.endOf('35 anos (vencimento do contrato)'),
          isNull);
      expect(FreConcessionTerm.endOf(''), isNull);
      expect(FreConcessionTerm.endOf(null), isNull);
      expect(FreConcessionTerm.endOf('31/02/2030'), isNull,
          reason: 'data que não existe não vira março');
    });
  });

  group('Resumo por companhia', () {
    test('contrato vencido na data do formulário não conta', () {
      final r = FreConcessionTerm.summarize([
        'até Fevereiro de 2016',
        'até julho/2045',
        'até Dezembro/2035',
        'Prazo indeterminado',
      ], _d(2019, 1, 1));
      expect(r.contratos, 4);
      expect(r.lidos, 3);
      expect(r.vigentes, 2);
      expect(r.end, _d(2035, 12, 31), reason: 'mediana baixa de dois');
    });

    test('sem contrato vigente, sem fim', () {
      final r = FreConcessionTerm.summarize(['Vide item 9.1'], _d(2022, 1, 1));
      expect(r.end, isNull);
      expect(r.lidos, 0);
    });
  });
}
