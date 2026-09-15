// A ponte por papel na data da coorte (item C3).
//
// **Dois defeitos da montagem das coortes, e um é a causa do outro.**
//
// 1. **O preço da coorte estava na base de ações de hoje.** A fonte publica o
//    fechamento ajustado por todo evento de ações até hoje, e a coorte o
//    multiplicava pela contagem do exercício, que está na base daquele ano. A
//    MGLU3 de 30/09/2020 entrava a R$ 212,38: o fechamento do dia foi R$ 84,95,
//    e o desdobramento de 4 para 1 de outubro de 2020 e o grupamento de 10 para
//    1 de 2024 o levaram à base de hoje. O valor de mercado da coorte saía
//    errado pelo produto dos eventos posteriores — o mesmo fator no potencial
//    e no book-to-market —, e o volume da fonte, que não é ajustado, dava à
//    Porta 0 um financeiro errado pelo mesmo fator. Conferido em 15/09/2026:
//    697 de 2.247 observações das listadas com fechamento no COTAHIST estavam
//    fora da base da data por mais de 2%, e 386 por mais de 1,5 vez.
// 2. **A razão de unidade e o divisor colapsavam por construção** (limitações
//    §3.5): com `valor de mercado = contagem × preço` e a mesma contagem como
//    corrente, a unit saía com `u = 1` e as duas candidatas a divisor, iguais.
//
// **O que a coorte passa a montar**, para listada e deslistada:
//
// - a série de preço **na base da data**: a da fonte vezes o fator
//   `fechamento bruto ÷ fechamento da fonte` medido no último pregão até a
//   data, e o volume refeito do financeiro do COTAHIST;
// - a contagem de ações **da data**, do Formulário de Referência (A3.4), como
//   contagem corrente e como a contagem oficial que arbitra o divisor — o papel
//   que o registro da B3 tem no aplicativo;
// - o valor de mercado **da companhia**, espécie a espécie: a contagem de
//   ordinárias e de preferenciais vezes o fechamento bruto do papel mais
//   negociado de cada uma. É a convenção em que a unit mede `u` ações.
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import '../b3/proventos.dart';

/// Espécie de um papel pelo número do ticker.
enum Especie { ordinaria, preferencial, unit }

/// `ordinaria` para 3, `preferencial` de 4 a 8, `unit` para 11; `null` para o
/// resto — recibo, bônus, BDR.
Especie? especieDo(String ticker) {
  if (ticker.length < 5) return null;
  final n = int.tryParse(ticker.substring(4));
  if (n == null) return null;
  if (n == 3) return Especie.ordinaria;
  if (n >= 4 && n <= 8) return Especie.preferencial;
  if (n == 11) return Especie.unit;
  return null;
}

/// Os códigos de uma companhia: os conhecidos e, para a raiz de quatro letras
/// de cada um, os das espécies e da unit — `3` a `8` e `11`.
///
/// A FCA nem sempre declara o código de cada espécie: a Alupar declara só a
/// ALUP11, e a ALUP3 e a ALUP4 negociam. O papel que não existe simplesmente
/// não tem pregão no COTAHIST.
Set<String> codigosDaCompanhia(Iterable<String> conhecidos) => {
      for (final c in conhecidos) ...{
        c,
        if (c.length > 4)
          for (final n in const ['3', '4', '5', '6', '7', '8', '11'])
            '${c.substring(0, 4)}$n',
      },
    };

/// Pregões de [ticker] encadeados pelos códigos anteriores da mesma espécie.
///
/// A fonte publica a série inteira sob o código de hoje; o COTAHIST, sob o de
/// cada época. Entram os códigos que a companhia declarou na FCA com o mesmo
/// número de classe — `VVAR3` para a `BHIA3`. No pregão em que dois códigos
/// negociam, fica o de hoje.
List<Pregao> encadear(
  String ticker,
  Iterable<String> codigosDaCompanhia,
  Map<String, List<Pregao>> cotahist,
) {
  final classe = ticker.length > 4 ? ticker.substring(4) : '';
  final porDia = <DateTime, Pregao>{};
  final anteriores = [
    for (final c in codigosDaCompanhia)
      if (c != ticker && c.length > 4 && c.substring(4) == classe) c,
  ]..sort();
  for (final c in [...anteriores, ticker]) {
    for (final p in cotahist[c] ?? const <Pregao>[]) {
      porDia[p.date] = p;
    }
  }
  return porDia.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

/// Folga, em dias corridos, entre a data da coorte e o último pregão: além
/// disso o papel não negociava, e não há preço da data.
const int folgaDoPregao = 10;

/// O fator que leva a série da fonte à base de ações de [data].
///
/// `fechamento bruto ÷ fechamento da fonte` no último pregão do COTAHIST até
/// [data], medido no mesmo dia da fonte. Não se reconstrói pelos eventos do
/// registro: o fator é o que a fonte aplicou, e o registro da B3 repete evento
/// — a BBAS3 de 2018 tem fator 2 no preço e produto 8 no registro.
///
/// Devolve `null` sem pregão a até [folgaDoPregao] dias, ou sem fechamento da
/// fonte naquele dia.
({double fator, Pregao pregao})? fatorDeBase({
  required PriceSeries fonte,
  required List<Pregao> brutos,
  required DateTime data,
}) {
  final pregao = pregaoAte(brutos, data, folgaDias: folgaDoPregao);
  if (pregao == null || !(pregao.close > 0)) return null;
  final dia = DateTime.utc(pregao.date.year, pregao.date.month, pregao.date.day);
  for (final p in fonte.points.reversed) {
    final d = DateTime.utc(p.date.year, p.date.month, p.date.day);
    if (d.isAfter(dia)) continue;
    if (d.isBefore(dia)) return null;
    if (!(p.close > 0)) return null;
    final f = pregao.close / p.close;
    return f.isFinite && f > 0 ? (fator: f, pregao: pregao) : null;
  }
  return null;
}

/// A série da fonte na base de ações da data, pelo [fator] de [fatorDeBase].
///
/// O fechamento é multiplicado pelo fator. O volume é refeito do financeiro do
/// COTAHIST no mesmo dia — `financeiro ÷ fechamento na base da data` —, para que
/// `fechamento × volume` continue sendo o financeiro que a Porta 0 mede: o
/// volume da fonte não é ajustado, e o fechamento é. Dia sem COTAHIST mantém o
/// volume da fonte, que nesse caso só erra se houve evento entre ele e a data.
PriceSeries serieNaBaseDaData(
  PriceSeries fonte,
  List<Pregao> brutos,
  double fator,
) {
  final financeiro = <DateTime, double>{
    for (final p in brutos)
      if (p.financeiro != null) p.date: p.financeiro!,
  };
  return PriceSeries(
    ticker: fonte.ticker,
    points: [
      for (final p in fonte.points)
        () {
          final close = p.close * fator;
          final f = financeiro[DateTime.utc(p.date.year, p.date.month, p.date.day)];
          return PricePoint(
            date: p.date,
            close: close,
            adjustedClose: p.adjustedClose,
            volume: (f != null && close > 0) ? f / close : p.volume,
          );
        }(),
    ],
  );
}

/// Valor de mercado da companhia em [data], espécie a espécie.
class ValorDeMercado {
  /// Em reais.
  final double valor;

  /// Como saiu: `especies` com as duas espécies pelo preço delas,
  /// `umaEspecie` com a companhia de uma espécie só ou a espécie sem pregão
  /// pelo preço da outra, e `semDivisao` sem a divisão entre espécies.
  final String origem;

  const ValorDeMercado(this.valor, this.origem);

  /// Pregões considerados no financeiro que escolhe o papel de cada espécie.
  static const int pregoesDoFinanceiro = 21;

  /// - [acoes]: contagem total da data, somadas as espécies.
  /// - [fracaoOrdinarias]: ordinárias ÷ total na data, ou `null` sem divisão.
  /// - [papeis]: pregões brutos de cada papel da companhia, já encadeados.
  ///
  /// A preferencial com mais de uma classe listada — PNA e PNB — vai toda pelo
  /// preço da mais negociada: o formulário não separa a contagem entre elas. A
  /// unit não entra: ela é cesta das outras duas.
  ///
  /// Devolve `null` quando nenhum papel de espécie negociou até [folgaDoPregao]
  /// dias antes da data.
  static ValorDeMercado? naData({
    required double acoes,
    required double? fracaoOrdinarias,
    required Map<String, List<Pregao>> papeis,
    required DateTime data,
  }) {
    if (!(acoes > 0)) return null;
    ({double preco, double financeiro})? melhor(Especie e) {
      ({double preco, double financeiro})? m;
      for (final entrada in papeis.entries) {
        if (especieDo(entrada.key) != e) continue;
        final s = entrada.value;
        final ultimo = pregaoAte(s, data, folgaDias: folgaDoPregao);
        if (ultimo == null || !(ultimo.close > 0)) continue;
        // Posição do último pregão, por busca binária: a série é ordenada.
        var lo = 0, hi = s.length;
        while (lo < hi) {
          final m = (lo + hi) ~/ 2;
          if (s[m].date.isAfter(ultimo.date)) {
            hi = m;
          } else {
            lo = m + 1;
          }
        }
        final i = lo - 1;
        var fin = 0.0;
        for (var k = math.max(0, i - pregoesDoFinanceiro + 1); k <= i; k++) {
          fin += s[k].financeiro ?? 0;
        }
        if (m == null || fin > m.financeiro) {
          m = (preco: ultimo.close, financeiro: fin);
        }
      }
      return m;
    }

    final on = melhor(Especie.ordinaria);
    final pn = melhor(Especie.preferencial);
    if (on == null && pn == null) return null;
    final f = fracaoOrdinarias;
    if (f == null || !f.isFinite || f < 0 || f > 1) {
      final p = (on == null || (pn != null && pn.financeiro > on.financeiro))
          ? pn!.preco
          : on.preco;
      return ValorDeMercado(acoes * p, 'semDivisao');
    }
    final pOn = on?.preco ?? pn!.preco;
    final pPn = pn?.preco ?? on!.preco;
    // A fração vem de uma razão de contagens: a espécie única é a fração a
    // uma folga de 0 ou de 1, e não a igualdade exata.
    const folga = 1e-9;
    final umaSo = f >= 1 - folga || f <= folga || on == null || pn == null;
    return ValorDeMercado(
      acoes * (f * pOn + (1 - f) * pPn),
      umaSo ? 'umaEspecie' : 'especies',
    );
  }
}

/// Divisão do capital entre ordinárias e preferenciais ao longo do tempo, do
/// quadro de capital social do Formulário de Referência.
///
/// A mesma regra de data da contagem (`ShareCountHistory`): cada aprovação de
/// capital vale pela **primeira** declaração dela. Desdobramento e grupamento
/// não mudam a fração, e por isso a série é só das aprovações.
class ClassesDoCapital {
  ClassesDoCapital._(this.pontos);

  /// `(desde, fração de ordinárias)`, em ordem de data.
  final List<({DateTime desde, double fracao})> pontos;

  static ClassesDoCapital fromFre(Iterable<Map<String, String>> linhas) {
    for (final tipo in ShareCountHistory.tipos) {
      final porReferencia = <String, List<Map<String, String>>>{};
      for (final r in linhas) {
        if (r['Tipo_Capital']?.trim() != tipo) continue;
        (porReferencia['${r['Data_Referencia']}'] ??= []).add(r);
      }
      if (porReferencia.isEmpty) continue;
      // A maior versão de cada referência, em ordem de referência.
      final referencias = porReferencia.keys.toList()..sort();
      final pontos = <({DateTime desde, double fracao})>[];
      final vistas = <DateTime>[];
      for (final ref in referencias) {
        final doc = porReferencia[ref]!;
        final versao = doc
            .map((r) => int.tryParse(r['Versao'] ?? '') ?? 0)
            .fold<int>(0, math.max);
        for (final r in doc) {
          if ((int.tryParse(r['Versao'] ?? '') ?? 0) != versao) continue;
          final v = r['Data_Autorizacao_Aprovacao'];
          final aprovacao = (v == null || v.length < 10)
              ? null
              : DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
          final on = double.tryParse(r['Quantidade_Acoes_Ordinarias'] ?? '');
          final pn = double.tryParse(r['Quantidade_Acoes_Preferenciais'] ?? '');
          if (aprovacao == null || on == null || pn == null) continue;
          if (on < 0 || pn < 0 || on + pn <= 0) continue;
          if (vistas.any((a) => a.isAtSameMomentAs(aprovacao))) continue;
          vistas.add(aprovacao);
          pontos.add((desde: aprovacao, fracao: on / (on + pn)));
        }
      }
      pontos.sort((a, b) => a.desde.compareTo(b.desde));
      return ClassesDoCapital._(List.unmodifiable(pontos));
    }
    return ClassesDoCapital._(const []);
  }

  /// Lê a série gravada por `b3_deslistadas_contagem.dart`.
  static ClassesDoCapital fromJson(List<Object?>? lista) => ClassesDoCapital._([
        for (final p in (lista ?? const []).cast<Map<String, dynamic>>())
          (
            desde: DateTime.parse('${(p['desde'] as String).substring(0, 10)}T00:00:00Z'),
            fracao: (p['fracaoOrdinarias'] as num).toDouble(),
          ),
      ]);

  List<Map<String, Object>> toJson() => [
        for (final p in pontos)
          {
            'desde': p.desde.toIso8601String().substring(0, 10),
            'fracaoOrdinarias': p.fracao,
          },
      ];

  /// Fração de ordinárias em vigor em [data], ou a primeira declarada quando a
  /// data vem antes dela — a divisão entre espécies muda pouco, e sem ela o
  /// valor de mercado perde a espécie. `null` sem ponto nenhum.
  double? at(DateTime data) {
    if (pontos.isEmpty) return null;
    final d = DateTime.utc(data.year, data.month, data.day);
    var vigente = pontos.first.fracao;
    for (final p in pontos) {
      if (p.desde.isAfter(d)) break;
      vigente = p.fracao;
    }
    return vigente;
  }
}
