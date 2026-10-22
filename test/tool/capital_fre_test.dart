// Os eventos de ações e as emissões por valor das coortes (itens B28 a B30).
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/b3/proventos.dart';
import '../../tool/coortes/eventos_de_acoes.dart';
import '../../tool/cvm/emissoes_fre.dart';

final _t = Ticker.parse('ABCD3');

/// Pregões úteis de março e abril de 2024: o bruto cai pelo [factor] a partir
/// de [ex]; a fonte cai junto quando [adjusted] é falso, e fica contínua quando
/// é verdadeiro.
({List<TradingDay> rawSessions, PriceSeries source}) _security(
    {required DateTime ex, required double factor, required bool adjusted}) {
  final rawSessions = <TradingDay>[];
  final pts = <PricePoint>[];
  var d = DateTime.utc(2024, 3, 1);
  while (d.isBefore(DateTime.utc(2024, 5, 1))) {
    if (d.weekday <= 5) {
      final after = !d.isBefore(ex);
      final raw = after ? 20 / factor : 20.0;
      rawSessions.add(TradingDay(d, raw, after ? 2 : 1));
      final source = adjusted ? (after ? 20 / factor : 20 / factor) : raw;
      pts.add(PricePoint(date: DateTime(d.year, d.month, d.day), close: source));
    }
    d = d.add(const Duration(days: 1));
  }
  return (rawSessions: rawSessions, source: PriceSeries(ticker: _t, points: pts));
}

/// Uma linha de CSV escrita em duas partes, para caber na largura.
String _row(String start, String end) => '$start$end';

ShareEvent _ev(DateTime ex, double f) =>
    ShareEvent(exDate: ex, factor: f, observedRatio: 1 / f);

void main() {
  final ex = DateTime.utc(2024, 4, 2);

  group('o que a fonte não ajustou', () {
    test('bonificação que a fonte deixou como veio sai, com o dia do salto',
        () {
      final p = _security(ex: ex, factor: 1.1, adjusted: false);
      final without = notAdjustedBySource(p.source, p.rawSessions, [_ev(ex, 1.1)]);
      expect(without, hasLength(1));
      expect(without.single.exDate, DateTime.utc(2024, 4, 2));
    });

    test('evento que a fonte ajustou não sai', () {
      final p = _security(ex: ex, factor: 2, adjusted: true);
      expect(notAdjustedBySource(p.source, p.rawSessions, [_ev(ex, 2)]), isEmpty);
    });

    test('evento mal localizado a até dez dias é achado no salto', () {
      final p = _security(ex: ex, factor: 1.25, adjusted: false);
      final without = notAdjustedBySource(
          p.source, p.rawSessions, [_ev(DateTime.utc(2024, 3, 28), 1.25)]);
      expect(without.single.exDate, DateTime.utc(2024, 4, 2));
    });

    test('sem salto que case, nada sai — ajustar no dia errado inventaria um',
        () {
      final p = _security(ex: ex, factor: 1.0, adjusted: false);
      expect(notAdjustedBySource(p.source, p.rawSessions, [_ev(ex, 1.5)]), isEmpty);
    });
  });

  group('a contagem que o FRE ainda não absorveu', () {
    final count = [
      (since: DateTime.utc(2020, 1, 1), shares: 1000.0),
    ];

    test('parada desde antes do desdobramento, recebe o fator', () {
      final r = sharesWithEvents(
          count, DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 4, 16), 2)]);
      expect(r.shares, 2000);
      expect(r.applied, hasLength(1));
    });

    test('já absorvido pelo fator, fica como está', () {
      final r = sharesWithEvents([
        ...count,
        (since: DateTime.utc(2024, 3, 10), shares: 2000.0),
      ], DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 4, 16), 2)]);
      expect(r.shares, 2000);
      expect(r.applied, isEmpty);
    });

    test('mudou depois do evento por outro fator: a conta não reconstrói', () {
      final r = sharesWithEvents([
        ...count,
        (since: DateTime.utc(2024, 5, 1), shares: 1300.0),
      ], DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 4, 16), 2)]);
      expect(r.shares, 1300);
    });

    test('o formulário tratou o evento junto com outra operação: fica', () {
      // A AERI3 registrou o grupamento de 20 para 1 antes da data ex e junto
      // com uma emissão, com razão 0,081; aplicar de novo tirava 95% do valor.
      final r = sharesWithEvents([
        (since: DateTime.utc(2020, 12, 11), shares: 766.21e6),
        (since: DateTime.utc(2024, 4, 11), shares: 62.12e6),
      ], DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 5, 14), 0.05)]);
      expect(r.shares, 62.12e6);
      expect(r.applied, isEmpty);
    });

    test('evento anterior à contagem, ou posterior à data, não entra', () {
      final r = sharesWithEvents(count, DateTime(2024, 6, 30), [
        _ev(DateTime.utc(1989, 9, 15), 10),
        _ev(DateTime.utc(2024, 7, 1), 2),
      ]);
      expect(r.shares, 1000);
    });
  });

  group('a variação do capital que nenhum evento explica', () {
    final cand = [
      (
        issuance: ShareIssue(
            date: DateTime.utc(2024, 3, 20),
            amount: Money.fromReais(500),
            shares: 100),
        ratio: 1.1,
      ),
    ];

    test('com o salto e a troca de DISMES no preço, é bonificação', () {
      final p = _security(ex: ex, factor: 1.1, adjusted: false);
      expect(issuancesWithoutEvent(cand, p.rawSessions, const []), isEmpty);
    });

    test('com evento de mesmo fator no registro, também', () {
      final p = _security(ex: ex, factor: 1.0, adjusted: false);
      expect(
          issuancesWithoutEvent(
              cand, p.rawSessions, [_ev(DateTime.utc(2024, 5, 7), 1.1)]),
          isEmpty);
    });

    test('sem nenhum dos dois, sai como emissão sem valor declarado', () {
      final p = _security(ex: ex, factor: 1.0, adjusted: false);
      final r = issuancesWithoutEvent(cand, p.rawSessions, const []);
      expect(r.single.amount, Money.fromReais(500));
      expect(r.single.declared, isFalse);
    });
  });

  group('as emissões por valor do FRE', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('fre_'));
    tearDown(() => folder.deleteSync(recursive: true));

    void writeFile(String name, List<String> rows) =>
        File('${folder.path}/$name').writeAsStringSync(rows.join('\n'),
            encoding: latin1);

    const header = 'CNPJ_Companhia;Data_Referencia;Versao;ID_Documento;'
        'Nome_Companhia;ID_Capital_Social_Aumento;Data_Deliberacao;'
        'Orgao_Deliberacao_Aumento;Data_Emissao;Valor_Total_Emissao;'
        'Tipo_Subscricao;Quantidade_Acoes_Ordinarias;'
        'Quantidade_Acoes_Preferenciais;Quantidade_Total_Acoes;'
        'Subscricao_Capital_Anterior;Fator_Cotacao;Preco_Emissao;'
        'Criterio_Determinacao_Preco_Emissao;Forma_Integralizacao';

    setUp(() {
      writeFile('fre_cia_aberta_2025.csv', [
        'CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;CD_CVM;CATEG_DOC;ID_DOC;DT_RECEB;LINK_DOC',
        '1;2025-01-01;1;X;1;FRE;D1;2025-05-30;',
        '1;2025-01-01;2;X;1;FRE;D2;2026-03-10;',
      ]);
      writeFile('fre_cia_aberta_capital_social_aumento_2025.csv', [
        header,
        // A primeira versão: a emissão ainda com R$ 1,0 bilhão, repetida.
        _row('1;2025-01-01;1;D1;X;a1;2025-03-01;AGE;2025-03-01;1000000000;',
            'Subscrição particular;100;0;100;0;R\$;10;;Em dinheiro'),
        _row('1;2025-01-01;1;D1;X;a2;2025-03-01;AGE;2025-03-01;1000000000;',
            'Subscrição particular;100;0;100;0;R\$;10;;Em dinheiro'),
        // A segunda versão relista com outro identificador e o valor final, e
        // traz uma bonificação e uma capitalização sem ação nova.
        _row('1;2025-01-01;2;D2;X;b1;2025-03-01;AGE;2025-03-01;1300000000;',
            'Subscrição particular;100;0;100;0;R\$;13;;Em dinheiro'),
        _row('1;2025-01-01;2;D2;X;b2;2025-12-10;AGE;2025-12-10;500;',
            'Subscrição particular;1000;0;1000;0;R\$;0.5;;Ações Bonificadas'),
        _row('1;2025-01-01;2;D2;X;b3;2026-01-05;AGE;;700;',
            'Sem emissão de ações;0;0;0;0;R\$;0;;'),
      ]);
    });

    test('vale o formulário mais recente recebido até a data, inteiro', () {
      final fre = FreIssuances.read(folder: folder.path)!;
      expect(fre.known('1', DateTime(2025, 1, 1)), isEmpty,
          reason: 'nenhum formulário recebido ainda');
      final first = fre.known('1', DateTime(2025, 6, 1));
      expect(first, hasLength(1),
          reason: 'a mesma emissão repetida no formulário entra uma vez');
      expect(first.single.amount, Money.fromReais(1e9));
      final second = fre.known('1', DateTime(2026, 9, 1));
      expect(second.map((e) => e.amount), [Money.fromReais(1.3e9)],
          reason: 'a versão nova relista com outro identificador: somar as '
              'duas contaria a emissão duas vezes; bonificação e capitalização '
              'sem ação nova saem');
    });
  });
}
