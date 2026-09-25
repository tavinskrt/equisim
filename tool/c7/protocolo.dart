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

import '../regressao_condicional.dart' as habilidade;

/// Primeira coorte da réplica.
const String primeiraCoorte = '2025-12-31';

/// Datas de leitura fixadas pela decisão 129, antes de qualquer coorte nova.
final Map<int, DateTime> datasDeLeitura = {
  12: DateTime(2029, 9, 30),
  36: DateTime(2031, 9, 30),
};

/// Onde os selos moram: é versionado, e é essa a prova de quando foram feitos.
const String pastaDosSelos = 'docs/validacao/c7';

/// O que uma previsão selada guarda — e nada de desfecho. Os sinais das cinco
/// ordenações (o múltiplo de pares sai de `firmaSobreEbitda` e das grandezas
/// ao lado, com a mediana da própria coorte) e o que identifica a observação.
const List<String> camposSelados = [
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
class ProtocoloViolado implements Exception {
  ProtocoloViolado(this.mensagem);
  final String mensagem;
  @override
  String toString() => 'Protocolo do C7 violado: $mensagem';
}

/// O motor que produziu uma previsão.
class Motor {
  const Motor({required this.impressao, this.commit, this.limpo = true});

  /// Hash do manifesto das fontes do núcleo. Ver [impressaoDoMotor].
  final String impressao;

  /// `HEAD` no momento da selagem.
  final String? commit;

  /// `false` quando o núcleo tinha mudança não commitada: a impressão ainda
  /// identifica o motor, e o commit que a contém é o seguinte a `commit`.
  final bool limpo;

  Map<String, Object?> toJson() =>
      {'impressao': impressao, 'commitBase': commit, 'arvoreLimpa': limpo};

  static Motor fromJson(Map<String, dynamic> j) => Motor(
        impressao: j['impressao'] as String,
        commit: j['commitBase'] as String?,
        limpo: j['arvoreLimpa'] as bool? ?? true,
      );
}

Future<String> _git(List<String> args, {String? entrada}) async {
  final p = await Process.start('git', args);
  if (entrada != null) {
    p.stdin.write(entrada);
  }
  await p.stdin.close();
  final saida = await p.stdout.transform(utf8.decoder).join();
  final erro = await p.stderr.transform(utf8.decoder).join();
  if (await p.exitCode != 0) {
    throw ProtocoloViolado('git ${args.join(' ')} falhou: $erro');
  }
  return saida.trim();
}

/// Hash do git de um arquivo — o mesmo que o blob dele teria num commit.
Future<String> hashDoArquivo(String caminho) =>
    _git(['hash-object', caminho]);

/// A impressão do motor: o hash do manifesto `caminho hash` das fontes `.dart`
/// de `packages/equisim_core/lib`, em ordem de caminho.
Future<String> impressaoDoMotor(
    {String raiz = 'packages/equisim_core/lib'}) async {
  final fontes = [
    for (final f in Directory(raiz).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path.replaceAll('\\', '/'),
  ]..sort();
  final hashes =
      (await _git(['hash-object', '--stdin-paths'], entrada: fontes.join('\n')))
          .split('\n');
  if (hashes.length != fontes.length) {
    throw ProtocoloViolado('o git devolveu ${hashes.length} hashes para '
        '${fontes.length} fontes');
  }
  final manifesto = [
    for (var i = 0; i < fontes.length; i++) '${fontes[i]} ${hashes[i]}',
  ].join('\n');
  return _git(['hash-object', '--stdin'], entrada: '$manifesto\n');
}

/// O motor desta árvore de trabalho.
Future<Motor> motorAtual() async => Motor(
      impressao: await impressaoDoMotor(),
      commit: await _git(['rev-parse', 'HEAD']),
      limpo: (await _git(
              ['status', '--porcelain', '--', 'packages/equisim_core/lib']))
          .isEmpty,
    );

/// As previsões seladas de uma coorte, sem nenhum campo de desfecho.
List<Map<String, Object?>> previsoesDa(
    String coorte, List<Map<String, dynamic>> linhas) {
  final out = <Map<String, Object?>>[];
  for (final l in linhas) {
    if (l['coorte'] != coorte) continue;
    out.add({for (final c in camposSelados) c: l[c]});
  }
  out.sort((a, b) => (a['ticker']! as String).compareTo(b['ticker']! as String));
  for (final p in out) {
    if (p.keys.any((k) => k.startsWith('ret'))) {
      throw ProtocoloViolado('campo de desfecho numa previsão selada');
    }
  }
  return out;
}

/// O índice dos selos.
class Indice {
  Indice({this.motorPreRegistrado, List<Map<String, Object?>>? selos})
      : selos = selos ?? [];

  Motor? motorPreRegistrado;
  final List<Map<String, Object?>> selos;

  static File _arquivo(Directory pasta) => File('${pasta.path}/indice.json');

  static Indice ler(Directory pasta) {
    final f = _arquivo(pasta);
    if (!f.existsSync()) return Indice();
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return Indice(
      motorPreRegistrado: j['motorPreRegistrado'] == null
          ? null
          : Motor.fromJson(j['motorPreRegistrado'] as Map<String, dynamic>),
      selos: [
        for (final s in j['selos'] as List) (s as Map).cast<String, Object?>(),
      ],
    );
  }

  void gravar(Directory pasta) {
    pasta.createSync(recursive: true);
    _arquivo(pasta).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert({
      'protocolo': 'decisão 129, operacionalizada pela 133',
      'primeiraCoorte': primeiraCoorte,
      'datasDeLeitura': {
        for (final e in datasDeLeitura.entries)
          '${e.key}m': e.value.toIso8601String().substring(0, 10),
      },
      'motorPreRegistrado': motorPreRegistrado?.toJson(),
      'selos': selos,
    })}\n');
  }

  /// Os selos de um motor, por coorte.
  Map<String, Map<String, Object?>> daImpressao(String impressao) => {
        for (final s in selos)
          if (s['motor'] == impressao) s['coorte']! as String: s,
      };
}

/// Confere o hash de todo arquivo selado contra o índice. Um arquivo mexido
/// depois de selado é violação, e nada segue.
Future<void> conferirSelos(Directory pasta, Indice indice) async {
  for (final s in indice.selos) {
    final f = File('${pasta.path}/${s['arquivo']}');
    if (!f.existsSync()) {
      throw ProtocoloViolado('o selo ${s['arquivo']} sumiu');
    }
    final h = await hashDoArquivo(f.path);
    if (h != s['hash']) {
      throw ProtocoloViolado('o selo ${s['arquivo']} foi alterado depois de '
          'selado: hash $h, índice ${s['hash']}');
    }
  }
}

/// O que a selagem fez.
class Selagem {
  final List<String> seladas = [];
  final List<String> jaSeladas = [];

  /// Coortes já seladas cujas previsões, refeitas agora pelo mesmo motor, não
  /// batem com o selo — e quantas observações divergem. O selo não muda.
  final Map<String, int> divergentes = {};
  String serie = 'preRegistrado';
}

/// Sela as coortes de [linhas] que ainda não têm selo deste [motor].
///
/// Nunca reescreve um selo. A primeira selagem registra o motor
/// pré-registrado; um motor diferente dele sela numa segunda série.
Future<Selagem> selar({
  required List<Map<String, dynamic>> linhas,
  required Motor motor,
  required Directory pasta,
  required String hoje,
}) async {
  final indice = Indice.ler(pasta);
  await conferirSelos(pasta, indice);
  indice.motorPreRegistrado ??= motor;
  final pre = indice.motorPreRegistrado!.impressao == motor.impressao;
  final resultado = Selagem()..serie = pre ? 'preRegistrado' : 'motorDaData';

  final coortes = {
    for (final l in linhas) l['coorte']! as String,
  }.toList()
    ..sort();
  final antigas = coortes.where((c) => c.compareTo(primeiraCoorte) < 0);
  if (antigas.isNotEmpty) {
    throw ProtocoloViolado('coortes anteriores a $primeiraCoorte não são da '
        'réplica: ${antigas.join(', ')}');
  }
  final existentes = indice.daImpressao(motor.impressao);
  for (final c in coortes) {
    final previsoes = previsoesDa(c, linhas);
    final ja = existentes[c];
    if (ja != null) {
      resultado.jaSeladas.add(c);
      final selado = jsonDecode(
              File('${pasta.path}/${ja['arquivo']}').readAsStringSync())
          as Map<String, dynamic>;
      final antes = {
        for (final p in (selado['previsoes'] as List).cast<Map>())
          p['ticker']: jsonEncode(p),
      };
      final n = previsoes
          .where((p) => antes[p['ticker']] != jsonEncode(p))
          .length;
      if (n > 0) resultado.divergentes[c] = n;
      continue;
    }
    final nome = pre
        ? 'previsoes_$c.json'
        : 'previsoes_${c}_${motor.impressao.substring(0, 8)}.json';
    final f = File('${pasta.path}/$nome');
    if (f.existsSync()) {
      throw ProtocoloViolado('$nome existe sem entrada no índice');
    }
    pasta.createSync(recursive: true);
    f.writeAsStringSync('${const JsonEncoder.withIndent(' ').convert({
      'coorte': c,
      'serie': resultado.serie,
      'motor': motor.toJson(),
      'seladoEm': hoje,
      'observacoes': previsoes.length,
      'previsoes': previsoes,
    })}\n');
    indice.selos.add({
      'coorte': c,
      'arquivo': nome,
      'hash': await hashDoArquivo(f.path),
      'motor': motor.impressao,
      'serie': resultado.serie,
      'seladoEm': hoje,
      'observacoes': previsoes.length,
    });
    resultado.seladas.add(c);
  }
  indice.gravar(pasta);
  return resultado;
}

/// Duas previsões diferem? Por tolerância relativa, e nunca por igualdade de
/// `double` (regra R6); `null` só é igual a `null`.
bool _diferem(Object? a, Object? b) {
  if (a is num && b is num) {
    final escala = b.abs() > 1 ? b.abs() : 1;
    return (a - b).abs() > 1e-9 * escala;
  }
  return (a == null) != (b == null);
}

/// Soma [meses] ao último dia de um mês, ficando no último dia.
DateTime fimDoMes(DateTime d, int meses) =>
    DateTime(d.year, d.month + meses + 1, 0);

/// O que a leitura pode dizer antes da data: quantas coortes estão seladas e
/// quantas já têm o retorno do horizonte, sem estatística alguma.
Map<String, Object?> situacao({
  required Directory pasta,
  required DateTime hoje,
  required DateTime fimDosDados,
}) {
  final indice = Indice.ler(pasta);
  final pre = indice.motorPreRegistrado;
  final seladas = pre == null
      ? <String>[]
      : (indice.daImpressao(pre.impressao).keys.toList()..sort());
  return {
    'motorPreRegistrado': pre?.toJson(),
    'coortesSeladas': seladas,
    for (final e in datasDeLeitura.entries)
      '${e.key}m': {
        'dataDaLeitura': e.value.toIso8601String().substring(0, 10),
        'aberta': !hoje.isBefore(e.value),
        'coortesMaduras': seladas
            .where((c) =>
                !fimDoMes(DateTime.parse(c), e.key).isAfter(fimDosDados))
            .length,
      },
  };
}

/// A leitura de um horizonte, pelo instrumento do R3, sobre as previsões
/// **seladas** do motor pré-registrado e os retornos realizados de [linhas].
///
/// Recusa antes da data fixada, recusa observação anterior à primeira coorte
/// e recusa selo alterado. Diz quantas previsões refeitas em [linhas] divergem
/// das seladas — a leitura usa as seladas de qualquer jeito.
Future<Map<String, dynamic>> ler({
  required int meses,
  required Directory pasta,
  required DateTime hoje,
  required List<Map<String, dynamic>> linhas,
}) async {
  final data = datasDeLeitura[meses];
  if (data == null) throw ProtocoloViolado('horizonte $meses não registrado');
  if (hoje.isBefore(data)) {
    throw ProtocoloViolado('a leitura de $meses meses está fixada para '
        '${data.toIso8601String().substring(0, 10)}; antes disso só a '
        'situação pode ser consultada');
  }
  final indice = Indice.ler(pasta);
  await conferirSelos(pasta, indice);
  final pre = indice.motorPreRegistrado;
  if (pre == null) throw ProtocoloViolado('nenhuma coorte selada');

  final antigas = linhas.where(
      (l) => (l['coorte']! as String).compareTo(primeiraCoorte) < 0);
  if (antigas.isNotEmpty) {
    throw ProtocoloViolado('juntar coortes anteriores a $primeiraCoorte às '
        'novas é proibido (decisão 129)');
  }
  final campo = 'ret${meses}tot';
  final retorno = {
    for (final l in linhas) '${l['coorte']}|${l['ticker']}': l,
  };

  final observacoes = <Map<String, Object?>>[];
  var divergentes = 0;
  final selos = indice.daImpressao(pre.impressao);
  for (final c in selos.keys.toList()..sort()) {
    final selado = jsonDecode(
            File('${pasta.path}/${selos[c]!['arquivo']}').readAsStringSync())
        as Map<String, dynamic>;
    for (final p in (selado['previsoes'] as List).cast<Map<String, dynamic>>()) {
      final r = retorno['$c|${p['ticker']}'];
      if (r != null && _diferem(r['upside'], p['upside'])) divergentes++;
      observacoes.add({...p, campo: r?[campo]});
    }
  }
  return {
    'horizonteEmMeses': meses,
    'motorPreRegistrado': pre.toJson(),
    'previsoesRefeitasQueDivergem': divergentes,
    'leitura': habilidade.horizonteDaHabilidade(observacoes, campo,
        defasagem: meses ~/ 3 - 1),
  };
}
