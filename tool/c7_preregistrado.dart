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
const _baseDirs = ['data/b3', 'data/cvm', 'data/tesouro', 'data/gabarito'];
const _baseFiles = [
  'data/cvm_exercicios.json',
  'data/cvm_versoes.json',
  'docs/validacao/validation_cache.sqlite',
];

Future<void> main(List<String> args) async {
  String? value(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final folder = Directory(sealsDir);
  final index = Index.read(folder);
  final preRegistered = index.preRegisteredEngine;
  if (preRegistered == null) {
    stderr.writeln('Nenhuma coorte selada: rode antes tool/c7_selar.dart.');
    exit(2);
  }
  final commit = await commitOfFingerprint(preRegistered.fingerprint);
  if (commit == null) {
    stderr.writeln('O núcleo de impressão ${preRegistered.fingerprint} ainda não está em '
        'commit nenhum. Commite a selagem antes: o worktree precisa do commit.');
    exit(2);
  }
  stdout.writeln('motor pré-registrado: ${preRegistered.fingerprint.substring(0, 12)}… '
      'no commit ${commit.substring(0, 7)}');

  final root = Directory.current.path;
  final tree = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}equisim_c7_${commit.substring(0, 8)}');
  if (!tree.existsSync()) {
    await _run('git', ['worktree', 'add', '--detach', tree.path, commit], root);
  }
  for (final p in _baseDirs) {
    final destination = Directory('$root/$p');
    final link = '${tree.path}/$p';
    if (!destination.existsSync() || FileSystemEntity.typeSync(link) != FileSystemEntityType.notFound) {
      continue;
    }
    Directory(link).parent.createSync(recursive: true);
    if (Platform.isWindows) {
      await _run('cmd', ['/c', 'mklink', '/J', link.replaceAll('/', r'\'),
          destination.path.replaceAll('/', r'\')], root);
    } else {
      Link(link).createSync(destination.path);
    }
  }
  for (final a in _baseFiles) {
    final origin = File('$root/$a');
    if (!origin.existsSync()) continue;
    final copy = File('${tree.path}/$a')..parent.createSync(recursive: true);
    origin.copySync(copy.path);
  }

  await _run('flutter', ['pub', 'get'], tree.path);
  final end = value('--fim-dos-dados');
  // A credencial da fonte de mercado vai pelo ambiente do processo, e não por
  // cópia do `.env`: segredo não se espalha em pasta temporária.
  final token = _fromEnv('$root/.env', 'BRAPI_TOKEN');
  await _run(
    'dart',
    [
      'run',
      'tool/backtest_valuation.dart',
      '--montagem',
      'aplicativo',
      '--com-deslistadas',
      '--trimestral',
      '--c7',
      if (end != null) ...['--fim-dos-dados', end],
    ],
    tree.path,
    environment: {'BRAPI_TOKEN': ?token},
  );

  final source = File('${tree.path}/data/c7/coortes.json');
  final rows =
      (jsonDecode(source.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final today =
      value('--hoje') ?? DateTime.now().toIso8601String().substring(0, 10);
  try {
    final r = await seal(
      rows: rows,
      engine: Engine(fingerprint: preRegistered.fingerprint, commit: commit),
      folder: folder,
      today: today,
    );
    stdout.writeln('== Série pré-registrada, pelo commit ${commit.substring(0, 7)} ==');
    stdout.writeln('  seladas agora: '
        '${r.sealedCohorts.isEmpty ? 'nenhuma' : r.sealedCohorts.join(', ')}');
    stdout.writeln('  já seladas, conferidas: '
        '${r.alreadySealed.isEmpty ? 'nenhuma' : r.alreadySealed.join(', ')}');
    if (r.divergent.isEmpty && r.alreadySealed.isNotEmpty) {
      stdout.writeln('  o selo se reproduz: nenhuma previsão refeita diverge');
    }
    for (final e in r.divergent.entries) {
      stdout.writeln('  ! ${e.key}: ${e.value} previsões refeitas divergem do '
          'selo — o selo não muda, e a divergência precisa de explicação');
    }
  } on ProtocolViolated catch (e) {
    stderr.writeln(e);
    exit(1);
  }
  stdout.writeln('  worktree mantido em ${tree.path} — '
      'git worktree remove --force para apagar');
}

/// O valor de [key] no arquivo `.env` em [path], ou `null`.
String? _fromEnv(String path, String key) {
  final f = File(path);
  if (!f.existsSync()) return null;
  for (final row in f.readAsLinesSync()) {
    final t = row.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i <= 0 || t.substring(0, i).trim() != key) continue;
    final v = t.substring(i + 1).trim();
    return v.isEmpty ? null : v;
  }
  return null;
}

Future<void> _run(String exe, List<String> args, String directory,
    {Map<String, String>? environment}) async {
  final p = await Process.start(exe, args,
      workingDirectory: directory, runInShell: true, environment: environment);
  // As duas saídas ao mesmo tempo: o backtest escreve o progresso no erro, e
  // ler uma depois da outra travaria quando o buffer do erro enchesse.
  await Future.wait([stdout.addStream(p.stdout), stderr.addStream(p.stderr)]);
  final code = await p.exitCode;
  if (code != 0) {
    stderr.writeln('$exe ${args.join(' ')} falhou ($code) em $directory');
    exit(1);
  }
}
