// Os eventos de ações e as emissões por valor das coortes (itens B28 a B30).
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/b3/proventos.dart';
import '../../tool/coortes/eventos_de_acoes.dart';
import '../../tool/cvm/emissoes_fre.dart';

final _t = Ticker.parse('ABCD3');

/// Pregões úteis de março e abril de 2024: o bruto cai pelo [fator] a partir
/// de [ex]; a fonte cai junto quando [ajustada] é falso, e fica contínua quando
/// é verdadeiro.
({List<Pregao> brutos, PriceSeries fonte}) _papel(
    {required DateTime ex, required double fator, required bool ajustada}) {
  final brutos = <Pregao>[];
  final pts = <PricePoint>[];
  var d = DateTime.utc(2024, 3, 1);
  while (d.isBefore(DateTime.utc(2024, 5, 1))) {
    if (d.weekday <= 5) {
      final depois = !d.isBefore(ex);
      final bruto = depois ? 20 / fator : 20.0;
      brutos.add(Pregao(d, bruto, depois ? 2 : 1));
      final fonte = ajustada ? (depois ? 20 / fator : 20 / fator) : bruto;
      pts.add(PricePoint(date: DateTime(d.year, d.month, d.day), close: fonte));
    }
    d = d.add(const Duration(days: 1));
  }
  return (brutos: brutos, fonte: PriceSeries(ticker: _t, points: pts));
}

/// Uma linha de CSV escrita em duas partes, para caber na largura.
String _linha(String inicio, String fim) => '$inicio$fim';

ShareEvent _ev(DateTime ex, double f) =>
    ShareEvent(exDate: ex, factor: f, observedRatio: 1 / f);

void main() {
  final ex = DateTime.utc(2024, 4, 2);

  group('o que a fonte não ajustou', () {
    test('bonificação que a fonte deixou como veio sai, com o dia do salto',
        () {
      final p = _papel(ex: ex, fator: 1.1, ajustada: false);
      final sem = naoAjustadosPelaFonte(p.fonte, p.brutos, [_ev(ex, 1.1)]);
      expect(sem, hasLength(1));
      expect(sem.single.exDate, DateTime.utc(2024, 4, 2));
    });

    test('evento que a fonte ajustou não sai', () {
      final p = _papel(ex: ex, fator: 2, ajustada: true);
      expect(naoAjustadosPelaFonte(p.fonte, p.brutos, [_ev(ex, 2)]), isEmpty);
    });

    test('evento mal localizado a até dez dias é achado no salto', () {
      final p = _papel(ex: ex, fator: 1.25, ajustada: false);
      final sem = naoAjustadosPelaFonte(
          p.fonte, p.brutos, [_ev(DateTime.utc(2024, 3, 28), 1.25)]);
      expect(sem.single.exDate, DateTime.utc(2024, 4, 2));
    });

    test('sem salto que case, nada sai — ajustar no dia errado inventaria um',
        () {
      final p = _papel(ex: ex, fator: 1.0, ajustada: false);
      expect(naoAjustadosPelaFonte(p.fonte, p.brutos, [_ev(ex, 1.5)]), isEmpty);
    });
  });

  group('a contagem que o FRE ainda não absorveu', () {
    final contagem = [
      (desde: DateTime.utc(2020, 1, 1), acoes: 1000.0),
    ];

    test('parada desde antes do desdobramento, recebe o fator', () {
      final r = acoesComEventos(
          contagem, DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 4, 16), 2)]);
      expect(r.acoes, 2000);
      expect(r.aplicados, hasLength(1));
    });

    test('já absorvido pelo fator, fica como está', () {
      final r = acoesComEventos([
        ...contagem,
        (desde: DateTime.utc(2024, 3, 10), acoes: 2000.0),
      ], DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 4, 16), 2)]);
      expect(r.acoes, 2000);
      expect(r.aplicados, isEmpty);
    });

    test('mudou depois do evento por outro fator: a conta não reconstrói', () {
      final r = acoesComEventos([
        ...contagem,
        (desde: DateTime.utc(2024, 5, 1), acoes: 1300.0),
      ], DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 4, 16), 2)]);
      expect(r.acoes, 1300);
    });

    test('o formulário tratou o evento junto com outra operação: fica', () {
      // A AERI3 registrou o grupamento de 20 para 1 antes da data ex e junto
      // com uma emissão, com razão 0,081; aplicar de novo tirava 95% do valor.
      final r = acoesComEventos([
        (desde: DateTime.utc(2020, 12, 11), acoes: 766.21e6),
        (desde: DateTime.utc(2024, 4, 11), acoes: 62.12e6),
      ], DateTime(2024, 6, 30), [_ev(DateTime.utc(2024, 5, 14), 0.05)]);
      expect(r.acoes, 62.12e6);
      expect(r.aplicados, isEmpty);
    });

    test('evento anterior à contagem, ou posterior à data, não entra', () {
      final r = acoesComEventos(contagem, DateTime(2024, 6, 30), [
        _ev(DateTime.utc(1989, 9, 15), 10),
        _ev(DateTime.utc(2024, 7, 1), 2),
      ]);
      expect(r.acoes, 1000);
    });
  });

  group('a variação do capital que nenhum evento explica', () {
    final cand = [
      (
        emissao: ShareIssue(
            date: DateTime.utc(2024, 3, 20),
            amount: Money.fromReais(500),
            shares: 100),
        razao: 1.1,
      ),
    ];

    test('com o salto e a troca de DISMES no preço, é bonificação', () {
      final p = _papel(ex: ex, fator: 1.1, ajustada: false);
      expect(emissoesSemEvento(cand, p.brutos, const []), isEmpty);
    });

    test('com evento de mesmo fator no registro, também', () {
      final p = _papel(ex: ex, fator: 1.0, ajustada: false);
      expect(
          emissoesSemEvento(
              cand, p.brutos, [_ev(DateTime.utc(2024, 5, 7), 1.1)]),
          isEmpty);
    });

    test('sem nenhum dos dois, sai como emissão sem valor declarado', () {
      final p = _papel(ex: ex, fator: 1.0, ajustada: false);
      final r = emissoesSemEvento(cand, p.brutos, const []);
      expect(r.single.amount, Money.fromReais(500));
      expect(r.single.declared, isFalse);
    });
  });

  group('as emissões por valor do FRE', () {
    late Directory pasta;
    setUp(() => pasta = Directory.systemTemp.createTempSync('fre_'));
    tearDown(() => pasta.deleteSync(recursive: true));

    void grava(String nome, List<String> linhas) =>
        File('${pasta.path}/$nome').writeAsStringSync(linhas.join('\n'),
            encoding: latin1);

    const cabecalho = 'CNPJ_Companhia;Data_Referencia;Versao;ID_Documento;'
        'Nome_Companhia;ID_Capital_Social_Aumento;Data_Deliberacao;'
        'Orgao_Deliberacao_Aumento;Data_Emissao;Valor_Total_Emissao;'
        'Tipo_Subscricao;Quantidade_Acoes_Ordinarias;'
        'Quantidade_Acoes_Preferenciais;Quantidade_Total_Acoes;'
        'Subscricao_Capital_Anterior;Fator_Cotacao;Preco_Emissao;'
        'Criterio_Determinacao_Preco_Emissao;Forma_Integralizacao';

    setUp(() {
      grava('fre_cia_aberta_2025.csv', [
        'CNPJ_CIA;DT_REFER;VERSAO;DENOM_CIA;CD_CVM;CATEG_DOC;ID_DOC;DT_RECEB;LINK_DOC',
        '1;2025-01-01;1;X;1;FRE;D1;2025-05-30;',
        '1;2025-01-01;2;X;1;FRE;D2;2026-03-10;',
      ]);
      grava('fre_cia_aberta_capital_social_aumento_2025.csv', [
        cabecalho,
        // A primeira versão: a emissão ainda com R$ 1,0 bilhão, repetida.
        _linha('1;2025-01-01;1;D1;X;a1;2025-03-01;AGE;2025-03-01;1000000000;',
            'Subscrição particular;100;0;100;0;R\$;10;;Em dinheiro'),
        _linha('1;2025-01-01;1;D1;X;a2;2025-03-01;AGE;2025-03-01;1000000000;',
            'Subscrição particular;100;0;100;0;R\$;10;;Em dinheiro'),
        // A segunda versão relista com outro identificador e o valor final, e
        // traz uma bonificação e uma capitalização sem ação nova.
        _linha('1;2025-01-01;2;D2;X;b1;2025-03-01;AGE;2025-03-01;1300000000;',
            'Subscrição particular;100;0;100;0;R\$;13;;Em dinheiro'),
        _linha('1;2025-01-01;2;D2;X;b2;2025-12-10;AGE;2025-12-10;500;',
            'Subscrição particular;1000;0;1000;0;R\$;0.5;;Ações Bonificadas'),
        _linha('1;2025-01-01;2;D2;X;b3;2026-01-05;AGE;;700;',
            'Sem emissão de ações;0;0;0;0;R\$;0;;'),
      ]);
    });

    test('vale o formulário mais recente recebido até a data, inteiro', () {
      final fre = EmissoesFre.ler(pasta: pasta.path)!;
      expect(fre.conhecidas('1', DateTime(2025, 1, 1)), isEmpty,
          reason: 'nenhum formulário recebido ainda');
      final primeira = fre.conhecidas('1', DateTime(2025, 6, 1));
      expect(primeira, hasLength(1),
          reason: 'a mesma emissão repetida no formulário entra uma vez');
      expect(primeira.single.amount, Money.fromReais(1e9));
      final segunda = fre.conhecidas('1', DateTime(2026, 9, 1));
      expect(segunda.map((e) => e.amount), [Money.fromReais(1.3e9)],
          reason: 'a versão nova relista com outro identificador: somar as '
              'duas contaria a emissão duas vezes; bonificação e capitalização '
              'sem ação nova saem');
    });
  });
}
