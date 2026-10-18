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

const _output = 'assets/cvm/capital.json';

/// A data de referência do pacote: o dia em que o FRE e o COTAHIST em disco
/// foram conferidos.
final _reference = DateTime.utc(2026, 9, 24);

/// Desde quando entram as emissões: o balanço mais antigo que o aplicativo usa
/// é o do exercício anterior ao último, e o de 2023 cobre com folga.
final _issuancesSince = DateTime.utc(2023, 1, 1);

/// Desde quando entram os eventos: a janela do beta tem cinco anos.
final _eventsSince = DateTime.utc(2019, 1, 1);

void main(List<String> args) {
  final now = DateTime.now();
  final date = args.contains('--agora')
      ? DateTime.utc(now.year, now.month, now.day)
      : _reference;
  final issuances = FreIssuances.read();
  if (issuances == null) {
    stderr.writeln('sem data/cvm/fre. Rode antes:');
    stderr.writeln('  python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre');
    exitCode = 2;
    return;
  }
  final universe = (jsonDecode(
          File('docs/validacao/universo.json').readAsStringSync()) as List)
      .map((e) => (e as Map<String, dynamic>)['ticker'] as String)
      .toList();
  final bridge = ((jsonDecode(File('docs/validacao/ponte_cvm.json')
          .readAsStringSync()) as Map<String, dynamic>)['ponte']
          as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  final fca = FcaCodes.read();
  final codes = <String, Set<String>>{
    for (final t in universe)
      t: companyCodes({t, ...?fca.byCnpj[bridge[t]]}),
  };
  final raw = readRawCotahist({for (final c in codes.values) ...c});
  final events = ShareEvents.read(issuances: issuances);

  final package = <String, CapitalEvents>{};
  var withIssuance = 0, withEvent = 0, issuanceCount = 0, eventCount = 0;
  for (final t in universe) {
    final cnpj = bridge[t];
    final rawSessions = chain(t, codes[t] ?? {t}, raw);
    final all = events.ofSecurity(cnpj: cnpj, ticker: t, rawSessions: rawSessions);
    // O quadro de aumentos do FRE, até 2023, e a variação do capital
    // integralizado que nenhum evento confirmado no preço explica, depois.
    final ofIssuance = cnpj == null
        ? const <ShareIssue>[]
        : [
            for (final i in [
              ...issuances.known(cnpj, date),
              ...issuancesWithoutEvent(
                  issuances.byCapitalChange(cnpj, date),
                  rawSessions,
                  events.ofSecurity(
                      cnpj: cnpj, ticker: t, rawSessions: rawSessions, withCount: false)),
            ])
              if (!i.date.isBefore(_issuancesSince)) i,
          ];
    final ofSecurity = [
      for (final e in all)
        if (!e.exDate.isBefore(_eventsSince)) e,
    ];
    final c = CapitalEvents(issues: ofIssuance, shareEvents: ofSecurity);
    if (c.isEmpty) continue;
    package[t] = c;
    if (ofIssuance.isNotEmpty) withIssuance++;
    if (ofSecurity.isNotEmpty) withEvent++;
    issuanceCount += ofIssuance.length;
    eventCount += ofSecurity.length;
  }
  File(_output).writeAsStringSync(
      '${const JsonEncoder.withIndent(' ').convert(CapitalEventsCodec.encodePackage(package, generatedAt: date))}\n');
  stdout.writeln('${universe.length} ativos: $withIssuance com emissão por valor '
      '($issuanceCount), $withEvent com evento de ações ($eventCount)');
  stdout.writeln('escrito $_output');
}
