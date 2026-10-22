// O protocolo da réplica fora da amostra (item C7, decisões 129 e 133).
//
// **O que ele garante.** A única via pela qual o R3 poderia vir a passar é dado
// que nenhuma decisão do motor viu, lido pelo instrumento que já existe, nas
// datas fixadas antes de vê-lo. Três coisas estragariam isso, e cada uma tem
// uma trava aqui:
//
// 1. **mexer na previsão depois de ver o desfecho** — as previsões de cada
//    coorte são **seladas** num arquivo que nunca é reescrito, com o hash do
//    git dele no índice, antes de o retorno existir; a leitura usa a previsão
//    selada, e não uma refeita;
// 2. **espiar antes da data** — a leitura recusa aplicar o critério antes de
//    30/09/2029 (12 meses) e 30/09/2031 (36 meses), e até lá diz só quantas
//    coortes já estão seladas e maduras;
// 3. **juntar as coortes antigas para passar** — só entra coorte a partir de
//    31/12/2025, e a leitura recusa observação anterior em vez de filtrá-la
//    em silêncio.
//
// **O motor é identificado pela impressão**, e não por data: o hash do git de
// cada fonte de `packages/equisim_core/lib`, num manifesto ordenado, e o hash
// do manifesto. É o mesmo hash que o git dá aos blobs, e por isso a impressão
// de um selo pode ser reencontrada em qualquer commit futuro. Quando o motor
// muda, a selagem segue numa segunda série — «motor da data» —, e a série do
// motor pré-registrado precisa ser produzida por ele, num `git worktree` do
// commit que o índice registra.
import 'dart:convert';
import 'dart:io';

import '../regressao_condicional.dart' as skill;

/// Primeira coorte da réplica.
const String firstCohort = '2025-12-31';

/// Datas de leitura fixadas pela decisão 129, antes de qualquer coorte nova.
final Map<int, DateTime> readingDates = {
  12: DateTime(2029, 9, 30),
  36: DateTime(2031, 9, 30),
};

/// Onde os selos moram: é versionado, e é essa a prova de quando foram feitos.
const String sealsDir = 'docs/validacao/c7';

/// O que uma previsão selada guarda — e nada de desfecho. Os sinais das cinco
/// ordenações (o múltiplo de pares sai de `firmaSobreEbitda` e das grandezas
/// ao lado, com a mediana da própria coorte) e o que identifica a observação.
const List<String> sealedFields = [
  'coorte',
  'ticker',
  'deslistada',
  'setor',
  'preco',
  'justo',
  'upside',
  'modelo',
  'recusa',
  'bookToMarket',
  'earningsYield',
  'firmaSobreEbitda',
  'ebitda',
  'dividaLiquida',
  'lucro',
  'patrimonio',
  'valorDeMercado',
  'liquidez',
  'volatilidade',
  'ke',
  'fimDoExercicio',
];

/// Falha do protocolo: o que foi pedido quebraria uma das três travas.
class ProtocolViolated implements Exception {
  ProtocolViolated(this.message);
  final String message;
  @override
  String toString() => 'Protocolo do C7 violado: $message';
}

/// O motor que produziu uma previsão.
class Engine {
  const Engine({required this.fingerprint, this.commit, this.clean = true});

  /// Hash do manifesto das fontes do núcleo. Ver [engineFingerprint].
  final String fingerprint;

  /// `HEAD` no momento da selagem.
  final String? commit;

  /// `false` quando o núcleo tinha mudança não commitada: a impressão ainda
  /// identifica o motor, e o commit que a contém é o seguinte a `commit`.
  final bool clean;

  Map<String, Object?> toJson() =>
      {'impressao': fingerprint, 'commitBase': commit, 'arvoreLimpa': clean};

  static Engine fromJson(Map<String, dynamic> j) => Engine(
        fingerprint: j['impressao'] as String,
        commit: j['commitBase'] as String?,
        clean: j['arvoreLimpa'] as bool? ?? true,
      );
}

Future<String> _git(List<String> args,
    {String? entry, String? directory}) async {
  final p = await Process.start('git', args, workingDirectory: directory);
  if (entry != null) {
    p.stdin.write(entry);
  }
  await p.stdin.close();
  final output = await p.stdout.transform(utf8.decoder).join();
  final error = await p.stderr.transform(utf8.decoder).join();
  if (await p.exitCode != 0) {
    throw ProtocolViolated('git ${args.join(' ')} falhou: $error');
  }
  return output.trim();
}

/// Hash do git de um arquivo — o mesmo que o blob dele teria num commit.
Future<String> fileHash(String path) =>
    _git(['hash-object', path]);

/// A impressão do motor: o hash do manifesto `caminho hash` das fontes `.dart`
/// de `packages/equisim_core/lib`, em ordem de caminho.
Future<String> engineFingerprint(
    {String root = 'packages/equisim_core/lib'}) async {
  final sources = [
    for (final f in Directory(root).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path.replaceAll('\\', '/'),
  ]..sort();
  final hashes =
      (await _git(['hash-object', '--stdin-paths'], entry: sources.join('\n')))
          .split('\n');
  if (hashes.length != sources.length) {
    throw ProtocolViolated('o git devolveu ${hashes.length} hashes para '
        '${sources.length} fontes');
  }
  final manifesto = [
    for (var i = 0; i < sources.length; i++) '${sources[i]} ${hashes[i]}',
  ].join('\n');
  return _git(['hash-object', '--stdin'], entry: '$manifesto\n');
}

/// A impressão do núcleo **num commit**, pela árvore dele — a mesma conta de
/// [engineFingerprint] sobre uma árvore de trabalho limpa naquele commit.
Future<String> commitFingerprint(String commit,
    {String root = 'packages/equisim_core/lib'}) async {
  final output = await _git(['ls-tree', '-r', commit, '--', root]);
  final sources = <({String path, String hash})>[];
  for (final l in output.split('\n')) {
    final tab = l.indexOf('\t');
    if (tab < 0) continue;
    final path = l.substring(tab + 1);
    if (!path.endsWith('.dart')) continue;
    final fields = l.substring(0, tab).split(' ');
    if (fields.length < 3) continue;
    sources.add((path: path, hash: fields[2]));
  }
  sources.sort((a, b) => a.path.compareTo(b.path));
  final manifesto =
      [for (final f in sources) '${f.path} ${f.hash}'].join('\n');
  return _git(['hash-object', '--stdin'], entry: '$manifesto\n');
}

/// O commit **mais antigo** cujo núcleo tem a impressão [fingerprint], ou `null`
/// quando ela ainda não está em commit nenhum.
///
/// A impressão só muda quando o núcleo muda, e por isso basta olhar os commits
/// que o tocaram; o primeiro que casa é o que a introduziu, e todo commit
/// seguinte que não tocou o núcleo tem a mesma.
Future<String?> commitOfFingerprint(String fingerprint) async {
  final commits = (await _git(
          ['log', '--reverse', '--format=%H', '--', 'packages/equisim_core/lib']))
      .split('\n')
      .where((c) => c.trim().isNotEmpty);
  for (final c in commits) {
    if (await commitFingerprint(c) == fingerprint) return c;
  }
  return null;
}

/// O motor desta árvore de trabalho.
Future<Engine> currentEngine() async => Engine(
      fingerprint: await engineFingerprint(),
      commit: await _git(['rev-parse', 'HEAD']),
      clean: (await _git(
              ['status', '--porcelain', '--', 'packages/equisim_core/lib']))
          .isEmpty,
    );

/// As previsões seladas de uma coorte, sem nenhum campo de desfecho.
List<Map<String, Object?>> predictionsOf(
    String cohort, List<Map<String, dynamic>> rows) {
  final out = <Map<String, Object?>>[];
  for (final l in rows) {
    if (l['coorte'] != cohort) continue;
    out.add({for (final c in sealedFields) c: l[c]});
  }
  out.sort((a, b) => (a['ticker']! as String).compareTo(b['ticker']! as String));
  for (final p in out) {
    if (p.keys.any((k) => k.startsWith('ret'))) {
      throw ProtocolViolated('campo de desfecho numa previsão selada');
    }
  }
  return out;
}

/// O índice dos selos.
class Index {
  Index({this.preRegisteredEngine, List<Map<String, Object?>>? seals})
      : seals = seals ?? [];

  Engine? preRegisteredEngine;
  final List<Map<String, Object?>> seals;

  static File _file(Directory folder) => File('${folder.path}/indice.json');

  static Index read(Directory folder) {
    final f = _file(folder);
    if (!f.existsSync()) return Index();
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return Index(
      preRegisteredEngine: j['motorPreRegistrado'] == null
          ? null
          : Engine.fromJson(j['motorPreRegistrado'] as Map<String, dynamic>),
      seals: [
        for (final s in j['selos'] as List) (s as Map).cast<String, Object?>(),
      ],
    );
  }

  void save(Directory folder) {
    folder.createSync(recursive: true);
    _file(folder).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert({
      'protocolo': 'decisão 129, operacionalizada pela 133',
      'primeiraCoorte': firstCohort,
      'datasDeLeitura': {
        for (final e in readingDates.entries)
          '${e.key}m': e.value.toIso8601String().substring(0, 10),
      },
      'motorPreRegistrado': preRegisteredEngine?.toJson(),
      'selos': seals,
    })}\n');
  }

  /// Os selos de um motor, por coorte.
  Map<String, Map<String, Object?>> ofFingerprint(String fingerprint) => {
        for (final s in seals)
          if (s['motor'] == fingerprint) s['coorte']! as String: s,
      };
}

/// Confere o hash de todo arquivo selado contra o índice. Um arquivo mexido
/// depois de selado é violação, e nada segue.
Future<void> checkSeals(Directory folder, Index index) async {
  for (final s in index.seals) {
    final f = File('${folder.path}/${s['arquivo']}');
    if (!f.existsSync()) {
      throw ProtocolViolated('o selo ${s['arquivo']} sumiu');
    }
    final h = await fileHash(f.path);
    if (h != s['hash']) {
      throw ProtocolViolated('o selo ${s['arquivo']} foi alterado depois de '
          'selado: hash $h, índice ${s['hash']}');
    }
  }
}

/// O que a selagem fez.
class Sealing {
  final List<String> sealedCohorts = [];
  final List<String> alreadySealed = [];

  /// Coortes já seladas cujas previsões, refeitas agora pelo mesmo motor, não
  /// batem com o selo — e quantas observações divergem. O selo não muda.
  final Map<String, int> divergent = {};
  String series = 'preRegistrado';
}

/// Sela as coortes de [rows] que ainda não têm selo deste [engine].
///
/// Nunca reescreve um selo. A primeira selagem registra o motor
/// pré-registrado; um motor diferente dele sela numa segunda série.
Future<Sealing> seal({
  required List<Map<String, dynamic>> rows,
  required Engine engine,
  required Directory folder,
  required String today,
}) async {
  final index = Index.read(folder);
  await checkSeals(folder, index);
  index.preRegisteredEngine ??= engine;
  final preRegistered = index.preRegisteredEngine!.fingerprint == engine.fingerprint;
  final result = Sealing()..series = preRegistered ? 'preRegistrado' : 'motorDaData';

  final cohorts = {
    for (final l in rows) l['coorte']! as String,
  }.toList()
    ..sort();
  final oldVersions = cohorts.where((c) => c.compareTo(firstCohort) < 0);
  if (oldVersions.isNotEmpty) {
    throw ProtocolViolated('coortes anteriores a $firstCohort não são da '
        'réplica: ${oldVersions.join(', ')}');
  }
  final existing = index.ofFingerprint(engine.fingerprint);
  for (final c in cohorts) {
    final predictions = predictionsOf(c, rows);
    final alreadyThere = existing[c];
    if (alreadyThere != null) {
      result.alreadySealed.add(c);
      final sealedJson = jsonDecode(
              File('${folder.path}/${alreadyThere['arquivo']}').readAsStringSync())
          as Map<String, dynamic>;
      final before = {
        for (final p in (sealedJson['previsoes'] as List).cast<Map>())
          p['ticker']: jsonEncode(p),
      };
      final n = predictions
          .where((p) => before[p['ticker']] != jsonEncode(p))
          .length;
      if (n > 0) result.divergent[c] = n;
      continue;
    }
    final name = preRegistered
        ? 'previsoes_$c.json'
        : 'previsoes_${c}_${engine.fingerprint.substring(0, 8)}.json';
    final f = File('${folder.path}/$name');
    if (f.existsSync()) {
      throw ProtocolViolated('$name existe sem entrada no índice');
    }
    folder.createSync(recursive: true);
    f.writeAsStringSync('${const JsonEncoder.withIndent(' ').convert({
      'coorte': c,
      'serie': result.series,
      'motor': engine.toJson(),
      'seladoEm': today,
      'observacoes': predictions.length,
      'previsoes': predictions,
    })}\n');
    index.seals.add({
      'coorte': c,
      'arquivo': name,
      'hash': await fileHash(f.path),
      'motor': engine.fingerprint,
      'serie': result.series,
      'seladoEm': today,
      'observacoes': predictions.length,
    });
    result.sealedCohorts.add(c);
  }
  index.save(folder);
  return result;
}

/// Duas previsões diferem? Por tolerância relativa, e nunca por igualdade de
/// `double` (regra R6); `null` só é igual a `null`.
bool _differ(Object? a, Object? b) {
  if (a is num && b is num) {
    final scale = b.abs() > 1 ? b.abs() : 1;
    return (a - b).abs() > 1e-9 * scale;
  }
  return (a == null) != (b == null);
}

/// Soma [months] ao último dia de um mês, ficando no último dia.
DateTime endOfMonth(DateTime d, int months) =>
    DateTime(d.year, d.month + months + 1, 0);

/// O que a leitura pode dizer antes da data: quantas coortes estão seladas e
/// quantas já têm o retorno do horizonte, sem estatística alguma.
Map<String, Object?> situation({
  required Directory folder,
  required DateTime today,
  required DateTime dataEnd,
}) {
  final index = Index.read(folder);
  final preRegistered = index.preRegisteredEngine;
  final sealedCohorts = preRegistered == null
      ? <String>[]
      : (index.ofFingerprint(preRegistered.fingerprint).keys.toList()..sort());
  final byEngine = <String, List<String>>{};
  for (final s in index.seals) {
    (byEngine[s['motor']! as String] ??= []).add(s['coorte']! as String);
  }
  return {
    'motorPreRegistrado': preRegistered?.toJson(),
    'coortesSeladas': sealedCohorts,
    // As séries de motores posteriores ao pré-registrado (decisão 133).
    'motoresDaData': {
      for (final e in byEngine.entries)
        if (e.key != preRegistered?.fingerprint) e.key: e.value..sort(),
    },
    for (final e in readingDates.entries)
      '${e.key}m': {
        'dataDaLeitura': e.value.toIso8601String().substring(0, 10),
        'aberta': !today.isBefore(e.value),
        'coortesMaduras': sealedCohorts
            .where((c) =>
                !endOfMonth(DateTime.parse(c), e.key).isAfter(dataEnd))
            .length,
      },
  };
}

/// A leitura de um horizonte, pelo instrumento do R3, sobre as previsões
/// **seladas** do motor pré-registrado e os retornos realizados de [rows].
///
/// Recusa antes da data fixada, recusa observação anterior à primeira coorte
/// e recusa selo alterado. Diz quantas previsões refeitas em [rows] divergem
/// das seladas — a leitura usa as seladas de qualquer jeito.
Future<Map<String, dynamic>> read({
  required int months,
  required Directory folder,
  required DateTime today,
  required List<Map<String, dynamic>> rows,
}) async {
  final date = readingDates[months];
  if (date == null) throw ProtocolViolated('horizonte $months não registrado');
  if (today.isBefore(date)) {
    throw ProtocolViolated('a leitura de $months meses está fixada para '
        '${date.toIso8601String().substring(0, 10)}; antes disso só a '
        'situação pode ser consultada');
  }
  final index = Index.read(folder);
  await checkSeals(folder, index);
  final preRegistered = index.preRegisteredEngine;
  if (preRegistered == null) throw ProtocolViolated('nenhuma coorte selada');

  final oldVersions = rows.where(
      (l) => (l['coorte']! as String).compareTo(firstCohort) < 0);
  if (oldVersions.isNotEmpty) {
    throw ProtocolViolated('juntar coortes anteriores a $firstCohort às '
        'novas é proibido (decisão 129)');
  }
  final field = 'ret${months}tot';
  final returnRate = {
    for (final l in rows) '${l['coorte']}|${l['ticker']}': l,
  };

  /// As previsões seladas de um motor, com o retorno realizado ao lado.
  ({List<Map<String, Object?>> obs, int divergent}) ofSeries(String fingerprint) {
    final observations = <Map<String, Object?>>[];
    var divergent = 0;
    final seals = index.ofFingerprint(fingerprint);
    for (final c in seals.keys.toList()..sort()) {
      final sealedJson = jsonDecode(
              File('${folder.path}/${seals[c]!['arquivo']}').readAsStringSync())
          as Map<String, dynamic>;
      for (final p
          in (sealedJson['previsoes'] as List).cast<Map<String, dynamic>>()) {
        final r = returnRate['$c|${p['ticker']}'];
        if (r != null && _differ(r['upside'], p['upside'])) divergent++;
        observations.add({...p, field: r?[field]});
      }
    }
    return (obs: observations, divergent: divergent);
  }

  final preRegisteredSeries = ofSeries(preRegistered.fingerprint);
  // **As duas versões, como a decisão 129 pede**: a do motor pré-registrado é
  // a leitura do C7; a de cada motor posterior, selada em série própria, vem ao
  // lado — para que a réplica não vire reajuste, e para que se veja o que as
  // correções depois do selo fizeram.
  final others = <String>{
    for (final s in index.seals)
      if (s['motor'] != preRegistered.fingerprint) s['motor']! as String,
  }.toList()
    ..sort();
  return {
    'horizonteEmMeses': months,
    'motorPreRegistrado': preRegistered.toJson(),
    'previsoesRefeitasQueDivergem': preRegisteredSeries.divergent,
    'leitura': skill.skillHorizon(preRegisteredSeries.obs, field,
        lag: months ~/ 3 - 1),
    'motoresDaData': {
      for (final m in others)
        m: skill.skillHorizon(ofSeries(m).obs, field,
            lag: months ~/ 3 - 1),
    },
  };
}
