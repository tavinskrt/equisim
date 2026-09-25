// A leitura da réplica fora da amostra (item C7, decisões 129 e 133).
//
// **Antes da data fixada, só a situação**: quantas coortes estão seladas e
// quantas já têm o retorno do horizonte — nenhuma estatística. **Na data**, o
// critério da decisão 96 sobre as previsões seladas do motor pré-registrado,
// pela mesma função que mede o R3, com os retornos de um backtest `--c7` feito
// com a base de então.
//
// Uso:
//   dart run tool/c7_leitura.dart                        # situação
//   dart run tool/c7_leitura.dart --ler 12 \
//       [--fim-dos-dados AAAA-MM-DD] [--hoje AAAA-MM-DD]  # a partir de 30/09/2029
import 'dart:convert';
import 'dart:io';

import 'c7/protocolo.dart';

Future<void> main(List<String> args) async {
  String? valor(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final hoje = DateTime.parse(
      valor('--hoje') ?? DateTime.now().toIso8601String().substring(0, 10));
  final fimDosDados = DateTime.parse(valor('--fim-dos-dados') ?? '2026-09-04');
  final pasta = Directory(pastaDosSelos);
  final ler = valor('--ler');

  if (ler == null) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(
        situacao(pasta: pasta, hoje: hoje, fimDosDados: fimDosDados)));
    return;
  }
  final fonte = File('data/c7/coortes.json');
  if (!fonte.existsSync()) {
    stderr.writeln('Falta ${fonte.path}, com os retornos: rode o backtest em '
        'modo --c7 com --fim-dos-dados da base de hoje.');
    exit(2);
  }
  try {
    final meses = int.parse(ler);
    final leitura = await lerDoArquivo(meses, pasta, hoje, fonte);
    final saida = File('${pasta.path}/leitura_${meses}m.json');
    saida.writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(leitura)}\n');
    final fm = ((leitura['leitura'] as Map)['famaMacBeth']
        as Map)['potencialDadoBm'] as Map?;
    stdout.writeln('== C7, $meses meses ==');
    stdout.writeln('  potencial dado o B/M: ${fm?['media']}  t corrigido '
        '${fm?['tSobreposicao']} / ${fm?['criticoSobreposicao']}  '
        'Newey-West ${fm?['tNeweyWest']}  passa: ${fm?['passaR3'] ?? false}');
    stdout.writeln('  previsões refeitas que divergem do selo: '
        '${leitura['previsoesRefeitasQueDivergem']}');
    stdout.writeln('  escrito ${saida.path}');
  } on ProtocoloViolado catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}

Future<Map<String, dynamic>> lerDoArquivo(
        int meses, Directory pasta, DateTime hoje, File fonte) =>
    ler(
      meses: meses,
      pasta: pasta,
      hoje: hoje,
      linhas: (jsonDecode(fonte.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>(),
    );
