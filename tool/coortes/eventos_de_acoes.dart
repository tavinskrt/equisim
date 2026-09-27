// Os eventos de ações de uma companhia listada — desdobramento, grupamento e
// bonificação —, e o que eles fazem com a série da fonte e com a contagem por
// data das coortes (itens B29 e B30).
//
// **Quatro fontes, porque nenhuma basta.** O quadro de eventos do Formulário de
// Referência declara o fator pela contagem antes e depois, mas parou em 2022; o
// registro da B3 traz a data ex dos eventos recentes, e não de todos — a
// bonificação de 2024 da Klabin não está lá; o `DISMES` do COTAHIST marca todo
// evento, mas só se distingue de provento quando o fator é grande. A quarta é a
// contagem do próprio FRE: a mudança que nenhuma emissão por valor explica é
// candidata a evento, localizada no preço. Juntas, e sem repetir o mesmo
// evento, cobrem o que cada uma deixa de fora. **Candidato falso não custa
// nada**: evento só ajusta a série onde o salto dele está no preço.
//
// **O que a fonte de preços fez com cada um** se sabe pelo fator entre o
// fechamento bruto e o dela: no dia ex de um evento ajustado ele salta
// exatamente pelo fator, e no de um não ajustado fica parado. É uma conta sem
// ruído de mercado — os dois fechamentos andam juntos em todo pregão em que a
// fonte não mexeu —, e por isso quem tem o COTAHIST não precisa da regra do
// salto que o aplicativo usa (`CorporateEvents.completeAdjustment`).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import '../b3/proventos.dart';
import '../cvm/csv.dart';
import '../cvm/emissoes_fre.dart';

/// Os eventos de ações declarados e registrados, prontos para localizar.
class EventosDeAcoes {
  EventosDeAcoes._(this._declarados, this._registro, this._contagem,
      this._emissoes);

  /// Eventos do quadro do FRE, por CNPJ: aprovação e fator, distintos.
  final Map<String, List<({DateTime aprovacao, double fator})>> _declarados;

  /// Registro da B3, por raiz do código.
  final Map<String, B3Issuer> _registro;

  /// Mudanças da contagem do FRE, por CNPJ: data e razão.
  final Map<String, List<({DateTime data, double razao, double antes})>> _contagem;

  /// Emissões por valor do FRE, para separar a mudança de contagem que é
  /// emissão da que é evento de ações.
  final EmissoesFre? _emissoes;

  /// Lê o quadro de eventos do FRE e o registro da B3.
  ///
  /// Sem o FRE em disco, segue só com o registro e o `DISMES`: um evento a
  /// menos localizado é um ajuste a menos, e não um ajuste errado.
  static EventosDeAcoes ler({
    String pastaFre = 'data/cvm/fre',
    String registro = 'assets/b3/emissores.json',
    String contagemListadas = 'data/b3/listadas_contagem.json',
    EmissoesFre? emissoes,
  }) {
    final declarados = <String, List<({DateTime aprovacao, double fator})>>{};
    final pasta = Directory(pastaFre);
    if (pasta.existsSync()) {
      final vistos = <String>{};
      final arquivos = pasta
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'^fre_cia_aberta_capital_social_desdobramento_\d{4}\.csv$')
              .hasMatch(f.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in arquivos) {
        for (final r in lerCsvCvm(f)) {
          final cnpj = r['CNPJ_Companhia'];
          final aprov = DateTime.tryParse('${r['Data_Aprovacao']}T00:00:00Z');
          final antes =
              double.tryParse(r['Quantidade_Total_Acoes_Antes_Aprovacao'] ?? '');
          final depois =
              double.tryParse(r['Quantidade_Total_Acoes_Depois_Aprovacao'] ?? '');
          if (cnpj == null || aprov == null || antes == null || depois == null) {
            continue;
          }
          if (antes <= 0 || depois <= 0) continue;
          // Fator de 1 não é evento de ações: é o formulário repetindo a
          // contagem. E o mesmo evento se repete em toda versão do formulário.
          if (math.log(depois / antes).abs() < 1e-6) continue;
          if (!vistos.add('$cnpj|${_dia(aprov)}|$antes|$depois')) continue;
          (declarados[cnpj] ??= []).add((aprovacao: aprov, fator: depois / antes));
        }
      }
    }
    final arq = File(registro);
    final b3 = arq.existsSync()
        ? B3RegistryCodec.decodePackage(
            jsonDecode(arq.readAsStringSync()) as Map<String, dynamic>)
        : const <String, B3Issuer>{};
    final contagem = <String, List<({DateTime data, double razao, double antes})>>{};
    final arqContagem = File(contagemListadas);
    if (arqContagem.existsSync()) {
      final json = jsonDecode(arqContagem.readAsStringSync()) as Map<String, dynamic>;
      for (final e in json.entries) {
        final pontos = [
          for (final p in ((e.value as Map<String, dynamic>)['contagem'] as List)
              .cast<Map<String, dynamic>>())
            (
              desde: DateTime.parse('${p['desde']}T00:00:00Z'),
              acoes: (p['acoes'] as num).toDouble(),
            ),
        ]..sort((a, b) => a.desde.compareTo(b.desde));
        final mudancas = <({DateTime data, double razao, double antes})>[];
        for (var i = 1; i < pontos.length; i++) {
          final a = pontos[i - 1].acoes, b = pontos[i].acoes;
          if (a > 0 && b > 0 && math.log(b / a).abs() > 1e-6) {
            mudancas.add((data: pontos[i].desde, razao: b / a, antes: a));
          }
        }
        if (mudancas.isNotEmpty) contagem[e.key] = mudancas;
      }
    }
    return EventosDeAcoes._(declarados, b3, contagem, emissoes);
  }

  /// Os eventos de ações de [ticker], localizados no fechamento bruto dele.
  ///
  /// O mesmo evento vindo de duas fontes entra uma vez: dois eventos a até
  /// quinze dias um do outro são o mesmo, e dois de mesmo fator a até 120 dias
  /// também — a aprovação e a data ex de uma bonificação podem estar meses
  /// separadas, e a contagem do FRE a localiza na primeira troca de `DISMES`.
  /// Vale a fonte que chegou antes: o quadro do FRE e o registro da B3 dão a
  /// data ex; a contagem, só uma aproximação.
  ///
  /// [comContagem] falso deixa de fora a quarta fonte — a mudança de contagem
  /// do FRE —, para quem quer explicar justamente a contagem.
  List<ShareEvent> doPapel({
    required String? cnpj,
    required String ticker,
    required List<Pregao> brutos,
    bool comContagem = true,
  }) {
    final raw = [for (final p in brutos) p.raw];
    final out = <ShareEvent>[];
    void junta(ShareEvent e) {
      final repetido = out.any((x) {
        final dias = x.exDate.difference(e.exDate).inDays.abs();
        return dias <= 15 ||
            (dias <= 120 &&
                (math.log(x.factor) - math.log(e.factor)).abs() < 0.02);
      });
      if (!repetido) out.add(e);
    }

    // **Cada fonte com a sua prova** (decisão 136). O quadro do FRE declara o
    // fator e a aprovação, não a data ex: ela é o pregão em que o preço
    // confirma — a primeira troca de `DISMES` depois da aprovação, que é o que
    // `CorporateEvents.locate` devolve para fator pequeno, é muitas vezes um
    // provento, e a ASAI3 ganhava um evento de 0,935 num dia qualquer.
    for (final d in _declarados[cnpj] ?? const <({DateTime aprovacao, double fator})>[]) {
      final ev = _localizarNoPreco(brutos, d.aprovacao, d.fator);
      if (ev != null) junta(ev);
    }
    // O registro repete o evento por classe e por consulta — a BBAS3 de 2018
    // tem fator 2 no preço e produto 8 no registro: um por data.
    final raiz = ticker.length >= 4 ? ticker.substring(0, 4) : ticker;
    final datas = <String>{};
    for (final e in _registro[raiz]?.events ?? const <OfficialShareEvent>[]) {
      if (!(e.factor > 0) || !e.factor.isFinite) continue;
      if (!datas.add(_dia(e.exDate))) continue;
      junta(ShareEvent(
          exDate: DateTime.utc(e.exDate.year, e.exDate.month, e.exDate.day),
          factor: e.factor,
          observedRatio: 1 / e.factor));
    }
    // O `DISMES` com salto grande só é evento de ações se a contagem mudou
    // junto: a SYNE3 caiu 47% em 09/12/2024, com troca de `DISMES`, numa
    // redução de capital com devolução em dinheiro — e a contagem do FRE não
    // se moveu. Tomada por desdobramento, ela dobrava o retorno de quem a
    // atravessava.
    final mudancas = _contagem[cnpj] ??
        const <({DateTime data, double razao, double antes})>[];
    for (final ev in CorporateEvents.detect(raw)) {
      final contagemMudou = mudancas.any((m) =>
          m.data.difference(ev.exDate).inDays.abs() <= 400 &&
          (math.log(m.razao) - math.log(ev.factor)).abs() < 0.1);
      if (contagemMudou) junta(ev);
    }
    // A mudança de contagem que nenhuma emissão por valor explica: aumento de
    // 3% ou mais — bonificação, desdobramento —, ou redução à metade ou menos
    // — grupamento. Redução pequena é cancelamento de tesouraria, e não
    // evento. **Só entra se o preço a confirma** — troca de `DISMES` com o
    // salto do fator —, e não pelo primeiro salto parecido: a AMER3 caiu 38%
    // em 16/01/2023, na semana da fraude, e isso casava com uma mudança de
    // contagem de 1,62.
    if (!comContagem) {
      out.sort((a, b) => a.exDate.compareTo(b.exDate));
      return out;
    }
    final emitidas = cnpj == null || _emissoes == null
        ? const <ShareIssue>[]
        : _emissoes.conhecidas(cnpj, DateTime.utc(2100));
    for (final m in mudancas) {
      if (!(m.razao >= 1.03 || m.razao <= 0.5)) continue;
      final novas = m.antes * (m.razao - 1);
      final ehEmissao = emitidas.any((i) =>
          i.date.difference(m.data).inDays.abs() <= 60 &&
          (i.shares / novas - 1).abs() < 0.05);
      if (ehEmissao) continue;
      final ev = _localizarNoPreco(brutos, m.data, m.razao);
      if (ev != null) junta(ev);
    }
    out.sort((a, b) => a.exDate.compareTo(b.exDate));
    return out;
  }
}

/// Os eventos que a fonte de preços **não** ajustou, com a data ex em que o
/// salto está (item B29).
///
/// Para cada evento, procura a dez dias da data dada o pregão em que o bruto
/// salta pelo fator. Se nele o fator entre o bruto e a fonte também salta pelo
/// fator, a fonte ajustou; se fica parado, não ajustou, e o evento sai com esse
/// dia. Sem pregão que case — evento mal localizado, papel suspenso —, o evento
/// não sai: ajustar num dia errado inventaria o salto que se quer tirar.
List<ShareEvent> naoAjustadosPelaFonte(
  PriceSeries fonte,
  List<Pregao> brutos,
  List<ShareEvent> eventos,
) {
  if (eventos.isEmpty || brutos.length < 2 || fonte.isEmpty) return const [];
  final daFonte = <String, double>{
    for (final p in fonte.points)
      if (p.close > 0) _dia(p.date): p.close,
  };
  final out = <ShareEvent>[];
  for (final e in eventos) {
    final q = e.factor;
    // Abaixo de 2% o salto do evento não se separa de um pregão comum, e o
    // efeito dele na série é desse tamanho.
    if (!(q > 0) || !q.isFinite || math.log(q).abs() < 0.02) continue;
    final folga = math.log(q).abs() < math.log(1.6) ? 0.04 : 0.08;
    var ajustado = false;
    DateTime? diaSemAjuste;
    for (var i = 1; i < brutos.length; i++) {
      final b = brutos[i], a = brutos[i - 1];
      final dias = b.date.difference(e.exDate).inDays;
      if (dias < -10) continue;
      if (dias > 10) break;
      if (b.date.difference(a.date).inDays > 7) continue;
      final fa = daFonte[_dia(a.date)], fb = daFonte[_dia(b.date)];
      if (fa == null || fb == null || !(a.close > 0) || !(b.close > 0)) continue;
      final saltoDoBruto = math.log(b.close / a.close);
      final passoDoFator = math.log((b.close / fb) / (a.close / fa));
      if ((passoDoFator + math.log(q)).abs() < 0.01) {
        ajustado = true;
        break;
      }
      // Sem ajuste: o fator parado, o bruto caindo pelo fator e o `DISMES`
      // trocando no dia — sem a troca, uma queda comum de mercado passaria.
      if (passoDoFator.abs() < 0.005 &&
          b.distribuicao != a.distribuicao &&
          (saltoDoBruto + math.log(q)).abs() < folga) {
        diaSemAjuste ??= b.date;
      }
    }
    if (!ajustado && diaSemAjuste != null) {
      out.add(ShareEvent(
          exDate: DateTime.utc(
              diaSemAjuste.year, diaSemAjuste.month, diaSemAjuste.day),
          factor: q,
          observedRatio: e.observedRatio));
    }
  }
  return out;
}

/// A contagem do FRE em [t] com os eventos que ele ainda não absorveu
/// (item B30).
///
/// O quadro de eventos do FRE parou em 2022, e daí em diante a contagem só muda
/// quando a companhia corrige o formulário — o que pode levar mais de um ano.
/// Enquanto isso a coorte dividia pela contagem de antes do evento, com o preço
/// de depois: a BBAS3 de 30/06/2024 saía com metade do valor de mercado e o
/// dobro do potencial.
///
/// **Só age quando a contagem está parada**: nenhuma mudança, por fator
/// nenhum, de 400 dias antes do evento até a data. Se ela mudou, o formulário
/// tratou o evento — a aprovação costuma vir antes da data ex, e às vezes
/// junto com outra operação —, e a contagem fica como veio.
({double? acoes, List<ShareEvent> aplicados}) acoesComEventos(
  List<({DateTime desde, double acoes})> contagem,
  DateTime t,
  List<ShareEvent> eventos,
) {
  final dia = DateTime.utc(t.year, t.month, t.day);
  if (contagem.isEmpty) return (acoes: null, aplicados: const []);
  // A contagem precisa cobrir a data do evento: um evento anterior ao primeiro
  // formulário — o registro da B3 guarda eventos de 1989 — já está nela.
  final inicio = contagem.first.desde;
  double? acoes;
  double? anterior;
  final mudancas = <({DateTime data, double razao})>[];
  for (final p in contagem) {
    if (p.desde.isAfter(dia)) break;
    if (anterior != null && anterior > 0 && p.acoes > 0) {
      final r = p.acoes / anterior;
      if (math.log(r).abs() > 1e-6) {
        mudancas.add((data: p.desde, razao: r));
      }
    }
    anterior = p.acoes;
    acoes = p.acoes;
  }
  if (acoes == null) return (acoes: null, aplicados: const []);
  final aplicados = <ShareEvent>[];
  var ajustada = acoes;
  for (final e in eventos) {
    final ex = DateTime.utc(e.exDate.year, e.exDate.month, e.exDate.day);
    if (ex.isAfter(dia)) continue;
    if (!(e.factor > 0) || math.log(e.factor).abs() < 0.02) continue;
    // Só evento recente: a contagem do FRE começa em 2010, e o valor dela já
    // traz os eventos anteriores — uma data de aprovação antiga no primeiro
    // ponto não quer dizer contagem de antes do evento. Três anos cobrem com
    // folga o atraso de correção medido.
    if (ex.isBefore(DateTime.utc(2011)) ||
        ex.isBefore(DateTime.utc(dia.year - 3, dia.month, dia.day))) {
      continue;
    }
    if (!inicio.isBefore(ex)) continue;
    // **Parada de verdade**: nenhuma mudança da contagem, por fator nenhum, de
    // 400 dias antes do evento até a data. Se ela mudou, o formulário tratou o
    // evento, ainda que junto com outra coisa — a AERI3 registrou o grupamento
    // de 20 para 1 antes da data ex e junto com uma emissão, com razão 0,081,
    // e aplicar o evento de novo tirava 95% do valor de mercado.
    final mexeu = mudancas.any((m) =>
        m.data.isAfter(ex.subtract(const Duration(days: 400))));
    if (mexeu) continue;
    ajustada *= e.factor;
    aplicados.add(e);
  }
  return (acoes: ajustada, aplicados: aplicados);
}

/// O pregão, de 30 dias antes de [d] a 150 depois, em que o `DISMES` troca e o
/// fechamento bruto se divide pelo fator [q]; `null` sem ele.
ShareEvent? _localizarNoPreco(List<Pregao> brutos, DateTime d, double q) {
  final folga = math.log(q).abs() < math.log(1.6) ? 0.06 : 0.08;
  for (var i = 1; i < brutos.length; i++) {
    final b = brutos[i], a = brutos[i - 1];
    final dias = b.date.difference(d).inDays;
    if (dias < -30) continue;
    if (dias > 150) break;
    if (b.date.difference(a.date).inDays > 7) continue;
    if (b.distribuicao == a.distribuicao) continue;
    if (!(a.close > 0) || !(b.close > 0)) continue;
    final razao = b.close / a.close;
    if ((math.log(razao) + math.log(q)).abs() < folga) {
      return ShareEvent(
          exDate: DateTime.utc(b.date.year, b.date.month, b.date.day),
          factor: q,
          observedRatio: razao);
    }
  }
  return null;
}

String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

/// As variações de capital do FRE que nenhum evento de ações explica, como
/// emissões **sem valor declarado** (item B28): a cascata não as soma, e diz
/// quanto o preço justo mudaria se fossem emissão por valor.
///
/// A bonificação também aumenta o capital — capitaliza reserva —, e o que a
/// separa da emissão é o registro da B3, quando ele a tem, ou o preço: no dia
/// ex, o fechamento bruto se divide pela razão entre as contagens, e o `DISMES`
/// do COTAHIST troca. Uma queda comum de
/// mercado não troca o `DISMES`, e um provento troca mas não cai pela razão. A
/// busca vai de 30 dias antes da aprovação a 150 depois — a data ex costuma vir
/// depois dela, e a contagem do FRE às vezes é corrigida antes. A KLBN11 de
/// 2024 aparece no FRE como R$ 1,6 bilhão de capital com 10% de ações novas:
/// é a bonificação de 07/05/2024, com o bruto caindo 7,6% e o `DISMES` trocando
/// no dia, e fica de fora.
///
/// - [eventos]: os eventos do quadro do FRE, do registro da B3 e do `DISMES` —
///   **sem** a mudança de contagem, que se explicaria a si mesma.
List<ShareIssue> emissoesSemEvento(
  List<({ShareIssue emissao, double razao})> candidatas,
  List<Pregao> brutos,
  List<ShareEvent> eventos,
) =>
    [
      for (final c in candidatas)
        if (!_saltoDeEvento(brutos, c.emissao.date, c.razao) &&
            !eventos.any((e) =>
                e.exDate.difference(c.emissao.date).inDays.abs() <= 150 &&
                (math.log(e.factor) - math.log(c.razao)).abs() < 0.03))
          ShareIssue(
            date: c.emissao.date,
            amount: c.emissao.amount,
            shares: c.emissao.shares,
            declared: false,
          ),
    ];

bool _saltoDeEvento(List<Pregao> brutos, DateTime d, double q) {
  // Com a troca de `DISMES` exigida, a folga pode ser a da detecção: a
  // bonificação de 20% da POMO4 caiu 20% no dia ex, e não 16,7%.
  final folga = math.log(q).abs() < math.log(1.6) ? 0.06 : 0.08;
  for (var i = 1; i < brutos.length; i++) {
    final b = brutos[i], a = brutos[i - 1];
    final dias = b.date.difference(d).inDays;
    if (dias < -30) continue;
    if (dias > 150) break;
    if (b.date.difference(a.date).inDays > 7) continue;
    if (b.distribuicao == a.distribuicao) continue;
    if (!(a.close > 0) || !(b.close > 0)) continue;
    if ((math.log(b.close / a.close) + math.log(q)).abs() < folga) return true;
  }
  return false;
}
