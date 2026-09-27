// A série do motor pré-registrado do C7, produzida pelo commit dele (item C7,
// decisões 133 e 138).
//
// **Quando o motor muda, a selagem do dia sela a série «motor da data».** A
// série pré-registrada das coortes novas tem de sair do motor que selou
// primeiro — e o motor não é só o núcleo: é o pipeline inteiro daquele commit,
// com as ferramentas que montavam as coortes. Este programa acha o commit pela
// impressão do índice, monta um `git worktree` dele fora do repositório, liga a
// base bruta — que o git não versiona — por junção, roda nele o backtest em
// modo `--c7` e sela o resultado com a impressão pré-registrada.
//
// **É também a prova de que o selo se reproduz.** As coortes já seladas são
// refeitas pelo mesmo commit, sobre a mesma base, e conferidas contra o selo:
// divergência zero é o motor pré-registrado reproduzido ao último dígito.
//
// Uso, a cada trimestre fechado, **depois** de `tool/c7_selar.dart`:
//   dart run tool/c7_preregistrado.dart [--fim-dos-dados AAAA-MM-DD] [--hoje AAAA-MM-DD]
import 'dart:convert';
import 'dart:io';

import 'c7/protocolo.dart';

/// O que o backtest lê e o git não versiona: pastas ligadas por junção, e
/// arquivos copiados — o cache da fonte de mercado é escrito pelo backtest, e
/// cada árvore precisa do seu.
const _pastasDaBase = ['data/b3', 'data/cvm', 'data/tesouro', 'data/gabarito'];
const _arquivosDaBase = [
  'data/cvm_exercicios.json',
  'data/cvm_versoes.json',
  'docs/validacao/validation_cache.sqlite',
];

Future<void> main(List<String> args) async {
  String? valor(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final pasta = Directory(pastaDosSelos);
  final indice = Indice.ler(pasta);
  final pre = indice.motorPreRegistrado;
  if (pre == null) {
    stderr.writeln('Nenhuma coorte selada: rode antes tool/c7_selar.dart.');
    exit(2);
  }
  final commit = await commitDaImpressao(pre.impressao);
  if (commit == null) {
    stderr.writeln('O núcleo de impressão ${pre.impressao} ainda não está em '
        'commit nenhum. Commite a selagem antes: o worktree precisa do commit.');
    exit(2);
  }
  stdout.writeln('motor pré-registrado: ${pre.impressao.substring(0, 12)}… '
      'no commit ${commit.substring(0, 7)}');

  final raiz = Directory.current.path;
  final arvore = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}equisim_c7_${commit.substring(0, 8)}');
  if (!arvore.existsSync()) {
    await _rodar('git', ['worktree', 'add', '--detach', arvore.path, commit], raiz);
  }
  for (final p in _pastasDaBase) {
    final destino = Directory('$raiz/$p');
    final link = '${arvore.path}/$p';
    if (!destino.existsSync() || FileSystemEntity.typeSync(link) != FileSystemEntityType.notFound) {
      continue;
    }
    Directory(link).parent.createSync(recursive: true);
    if (Platform.isWindows) {
      await _rodar('cmd', ['/c', 'mklink', '/J', link.replaceAll('/', r'\'),
          destino.path.replaceAll('/', r'\')], raiz);
    } else {
      Link(link).createSync(destino.path);
    }
  }
  for (final a in _arquivosDaBase) {
    final origem = File('$raiz/$a');
    if (!origem.existsSync()) continue;
    final copia = File('${arvore.path}/$a')..parent.createSync(recursive: true);
    origem.copySync(copia.path);
  }

  await _rodar('flutter', ['pub', 'get'], arvore.path);
  final fim = valor('--fim-dos-dados');
  // A credencial da fonte de mercado vai pelo ambiente do processo, e não por
  // cópia do `.env`: segredo não se espalha em pasta temporária.
  final token = _doEnv('$raiz/.env', 'BRAPI_TOKEN');
  await _rodar(
    'dart',
    [
      'run',
      'tool/backtest_valuation.dart',
      '--montagem',
      'aplicativo',
      '--com-deslistadas',
      '--trimestral',
      '--c7',
      if (fim != null) ...['--fim-dos-dados', fim],
    ],
    arvore.path,
    ambiente: {'BRAPI_TOKEN': ?token},
  );

  final fonte = File('${arvore.path}/data/c7/coortes.json');
  final linhas =
      (jsonDecode(fonte.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final hoje =
      valor('--hoje') ?? DateTime.now().toIso8601String().substring(0, 10);
  try {
    final r = await selar(
      linhas: linhas,
      motor: Motor(impressao: pre.impressao, commit: commit),
      pasta: pasta,
      hoje: hoje,
    );
    stdout.writeln('== Série pré-registrada, pelo commit ${commit.substring(0, 7)} ==');
    stdout.writeln('  seladas agora: '
        '${r.seladas.isEmpty ? 'nenhuma' : r.seladas.join(', ')}');
    stdout.writeln('  já seladas, conferidas: '
        '${r.jaSeladas.isEmpty ? 'nenhuma' : r.jaSeladas.join(', ')}');
    if (r.divergentes.isEmpty && r.jaSeladas.isNotEmpty) {
      stdout.writeln('  o selo se reproduz: nenhuma previsão refeita diverge');
    }
    for (final e in r.divergentes.entries) {
      stdout.writeln('  ! ${e.key}: ${e.value} previsões refeitas divergem do '
          'selo — o selo não muda, e a divergência precisa de explicação');
    }
  } on ProtocoloViolado catch (e) {
    stderr.writeln(e);
    exit(1);
  }
  stdout.writeln('  worktree mantido em ${arvore.path} — '
      'git worktree remove --force para apagar');
}

/// O valor de [chave] no arquivo `.env` em [caminho], ou `null`.
String? _doEnv(String caminho, String chave) {
  final f = File(caminho);
  if (!f.existsSync()) return null;
  for (final linha in f.readAsLinesSync()) {
    final t = linha.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i <= 0 || t.substring(0, i).trim() != chave) continue;
    final v = t.substring(i + 1).trim();
    return v.isEmpty ? null : v;
  }
  return null;
}

Future<void> _rodar(String exe, List<String> args, String diretorio,
    {Map<String, String>? ambiente}) async {
  final p = await Process.start(exe, args,
      workingDirectory: diretorio, runInShell: true, environment: ambiente);
  // As duas saídas ao mesmo tempo: o backtest escreve o progresso no erro, e
  // ler uma depois da outra travaria quando o buffer do erro enchesse.
  await Future.wait([stdout.addStream(p.stdout), stderr.addStream(p.stderr)]);
  final codigo = await p.exitCode;
  if (codigo != 0) {
    stderr.writeln('$exe ${args.join(' ')} falhou ($codigo) em $diretorio');
    exit(1);
  }
}
