// B28 e B29 — empacota os eventos de capital de cada ativo para o aplicativo.
//
// Duas listas por ativo do universo, no pacote `assets/cvm/capital.json`:
//
// - **as emissões por valor** do Formulário de Referência conhecidas na data de
//   referência, desde 2023 — a cascata soma ao patrimônio da ponte as que caem
//   depois do balanço usado (item B28);
// - **os eventos de ações** — desdobramento, grupamento e bonificação — desde
//   2019, que cobrem a janela de cinco anos do beta: do quadro do FRE,
//   localizados no preço bruto, do registro da B3 e do `DISMES` do COTAHIST. O
//   preparo completa com eles o ajuste que a fonte de preços deixou de fazer
//   (item B29), e só onde a série dela ainda mostra o salto.
//
// **A data do pacote é declarada, e não lida do relógio**, como nos outros
// pacotes versionados: o mesmo formulário tem de dar o mesmo arquivo.
// `--agora` usa o dia, para quando os dados forem atualizados.
//
// Uso:
//   python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
//   python tool/b3_baixar.py
//   dart run tool/capital_empacotar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'coortes/eventos_de_acoes.dart';
import 'cvm/codigos_fca.dart';
import 'cvm/emissoes_fre.dart';

const _saida = 'assets/cvm/capital.json';

/// A data de referência do pacote: o dia em que o FRE e o COTAHIST em disco
/// foram conferidos.
final _referencia = DateTime.utc(2026, 9, 24);

/// Desde quando entram as emissões: o balanço mais antigo que o aplicativo usa
/// é o do exercício anterior ao último, e o de 2023 cobre com folga.
final _emissoesDesde = DateTime.utc(2023, 1, 1);

/// Desde quando entram os eventos: a janela do beta tem cinco anos.
final _eventosDesde = DateTime.utc(2019, 1, 1);

void main(List<String> args) {
  final agora = DateTime.now();
  final data = args.contains('--agora')
      ? DateTime.utc(agora.year, agora.month, agora.day)
      : _referencia;
  final emissoes = EmissoesFre.ler();
  if (emissoes == null) {
    stderr.writeln('sem data/cvm/fre. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre');
    exitCode = 2;
    return;
  }
  final universo = (jsonDecode(
          File('docs/validacao/universo.json').readAsStringSync()) as List)
      .map((e) => (e as Map<String, dynamic>)['ticker'] as String)
      .toList();
  final ponte = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
          as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  final fca = CodigosFca.ler();
  final codigos = <String, Set<String>>{
    for (final t in universo)
      t: codigosDaCompanhia({t, ...?fca.porCnpj[ponte[t]]}),
  };
  final bruto = lerCotahistBruto({for (final c in codigos.values) ...c});
  final eventos = EventosDeAcoes.ler(emissoes: emissoes);

  final pacote = <String, CapitalEvents>{};
  var comEmissao = 0, comEvento = 0, nEmissoes = 0, nEventos = 0;
  for (final t in universo) {
    final cnpj = ponte[t];
    final brutos = encadear(t, codigos[t] ?? {t}, bruto);
    final todos = eventos.doPapel(cnpj: cnpj, ticker: t, brutos: brutos);
    // O quadro de aumentos do FRE, até 2023, e a variação do capital
    // integralizado que nenhum evento confirmado no preço explica, depois.
    final daEmissao = cnpj == null
        ? const <ShareIssue>[]
        : [
            for (final i in [
              ...emissoes.conhecidas(cnpj, data),
              ...emissoesSemEvento(
                  emissoes.pelaVariacaoDoCapital(cnpj, data),
                  brutos,
                  eventos.doPapel(
                      cnpj: cnpj, ticker: t, brutos: brutos, comContagem: false)),
            ])
              if (!i.date.isBefore(_emissoesDesde)) i,
          ];
    final doPapel = [
      for (final e in todos)
        if (!e.exDate.isBefore(_eventosDesde)) e,
    ];
    final c = CapitalEvents(issues: daEmissao, shareEvents: doPapel);
    if (c.isEmpty) continue;
    pacote[t] = c;
    if (daEmissao.isNotEmpty) comEmissao++;
    if (doPapel.isNotEmpty) comEvento++;
    nEmissoes += daEmissao.length;
    nEventos += doPapel.length;
  }
  File(_saida).writeAsStringSync(
      '${const JsonEncoder.withIndent(' ').convert(CapitalEventsCodec.encodePackage(pacote, geradoEm: data))}\n');
  stdout.writeln('${universo.length} ativos: $comEmissao com emissão por valor '
      '($nEmissoes), $comEvento com evento de ações ($nEventos)');
  stdout.writeln('escrito $_saida');
}
