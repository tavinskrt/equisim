// O protocolo da réplica fora da amostra (item C7): cada trava tem teste.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/c7/protocolo.dart';

const _engine = Engine(fingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _other = Engine(fingerprint: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

/// As coortes do C7 de 31/12/2025 em diante, [n] trimestres.
List<String> _cohorts(int n) => [
      for (var i = 0; i < n; i++)
        DateTime(2025, 12 + 3 * i + 1, 0).toIso8601String().substring(0, 10),
    ];

/// Observações sintéticas: o retorno segue o potencial com ruído, para a
/// leitura ter o que medir.
List<Map<String, dynamic>> _rows(List<String> cohorts,
    {int assets = 40, bool withReturn = false, int seed = 7}) {
  final rnd = math.Random(seed);
  // Gerador próprio para o desfecho: as previsões são as mesmas com ou sem
  // retorno, como num backtest refeito com a base de depois.
  final noise = math.Random(seed + 1);
  return [
    for (final c in cohorts)
      for (var a = 0; a < assets; a++)
        () {
          final up = rnd.nextDouble() * 2 - 1;
          return <String, dynamic>{
            'coorte': c,
            'ticker': 'T${a.toString().padLeft(3, '0')}3',
            'deslistada': false,
            'upside': up,
            'bookToMarket': rnd.nextDouble(),
            'earningsYield': rnd.nextDouble() * 0.2,
            'justo': 10 + up,
            'preco': 10.0,
            if (withReturn) 'ret12tot': 0.3 * up + noise.nextDouble() * 0.2,
            if (withReturn) 'ret36tot': 0.5 * up + noise.nextDouble() * 0.4,
          };
        }(),
  ];
}

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('c7_'));
  tearDown(() => folder.deleteSync(recursive: true));

  group('selagem', () {
    test('sela uma vez por coorte, sem campo de desfecho, com o hash no índice',
        () async {
      final rows = _rows(_cohorts(3), withReturn: true);
      final r = await seal(
          rows: rows, engine: _engine, folder: folder, today: '2026-09-24');
      expect(r.sealedCohorts, _cohorts(3));
      expect(r.series, 'preRegistrado');

      final index = Index.read(folder);
      expect(index.preRegisteredEngine!.fingerprint, _engine.fingerprint);
      expect(index.seals, hasLength(3));
      final sealedJson = jsonDecode(
          File('${folder.path}/previsoes_2025-12-31.json').readAsStringSync())
          as Map<String, dynamic>;
      final p = (sealedJson['previsoes'] as List).first as Map<String, dynamic>;
      expect(p.keys.where((k) => k.startsWith('ret')), isEmpty,
          reason: 'o selo guarda previsão, e não desfecho');
      expect(index.seals.first['hash'],
          await fileHash('${folder.path}/previsoes_2025-12-31.json'));
    });

    test('selar de novo não reescreve: confere, e relata divergência', () async {
      final rows = _rows(_cohorts(2));
      await seal(rows: rows, engine: _engine, folder: folder, today: 'd1');
      final before =
          File('${folder.path}/previsoes_2025-12-31.json').readAsStringSync();
      final changed = [
        for (final l in rows)
          {...l, if (l['ticker'] == 'T0003') 'upside': 9.0},
      ];
      final r = await seal(
          rows: changed, engine: _engine, folder: folder, today: 'd2');
      expect(r.sealedCohorts, isEmpty);
      expect(r.alreadySealed, _cohorts(2));
      expect(r.divergent, {'2025-12-31': 1, '2026-03-31': 1});
      expect(File('${folder.path}/previsoes_2025-12-31.json').readAsStringSync(),
          before);
    });

    test('um selo alterado depois de selado interrompe tudo', () async {
      await seal(
          rows: _rows(_cohorts(1)), engine: _engine, folder: folder, today: 'd');
      final f = File('${folder.path}/previsoes_2025-12-31.json');
      f.writeAsStringSync(f.readAsStringSync().replaceFirst('10.0', '11.0'));
      expect(
        () => seal(
            rows: _rows(_cohorts(2)), engine: _engine, folder: folder, today: 'd'),
        throwsA(isA<ProtocolViolated>()),
      );
    });

    test('coorte anterior a 31/12/2025 não é da réplica', () {
      expect(
        () => seal(
            rows: _rows(['2025-09-30']), engine: _engine, folder: folder, today: 'd'),
        throwsA(isA<ProtocolViolated>()),
      );
    });

    test('motor diferente do pré-registrado sela em série própria', () async {
      await seal(
          rows: _rows(_cohorts(1)), engine: _engine, folder: folder, today: 'd');
      final r = await seal(
          rows: _rows(_cohorts(1)), engine: _other, folder: folder, today: 'd');
      expect(r.series, 'motorDaData');
      expect(r.sealedCohorts, ['2025-12-31']);
      expect(File('${folder.path}/previsoes_2025-12-31_bbbbbbbb.json').existsSync(),
          isTrue);
      expect(Index.read(folder).preRegisteredEngine!.fingerprint, _engine.fingerprint,
          reason: 'o pré-registrado não muda');
    });
  });

  group('leitura', () {
    test('antes da data, a situação — e nenhuma estatística', () async {
      await seal(
          rows: _rows(_cohorts(3)), engine: _engine, folder: folder, today: 'd');
      final s = situation(
          folder: folder,
          today: DateTime(2026, 9, 24),
          dataEnd: DateTime(2027, 3, 30));
      expect(s['coortesSeladas'], _cohorts(3));
      expect((s['12m'] as Map)['aberta'], isFalse);
      expect((s['12m'] as Map)['coortesMaduras'], 1,
          reason: 'só 31/12/2025 tem doze meses até 30/03/2027');
      expect(s.toString(), isNot(contains('media')));

      expect(
        () => read(
            months: 12,
            folder: folder,
            today: DateTime(2029, 9, 29),
            rows: _rows(_cohorts(3), withReturn: true)),
        throwsA(isA<ProtocolViolated>()),
      );
    });

    test('na data, o instrumento do R3 sobre as previsões seladas', () async {
      final cohorts = _cohorts(12);
      await seal(
          rows: _rows(cohorts), engine: _engine, folder: folder, today: 'd');
      // Os retornos chegam de um backtest posterior, com as mesmas previsões.
      final r = await read(
        months: 12,
        folder: folder,
        today: DateTime(2029, 9, 30),
        rows: _rows(cohorts, withReturn: true),
      );
      expect(r['previsoesRefeitasQueDivergem'], 0);
      final fm = ((r['leitura'] as Map)['famaMacBeth'] as Map)['potencialDadoBm']
          as Map;
      expect(fm['coortes'], 12);
      expect(fm['media'], greaterThan(0),
          reason: 'o retorno sintético segue o potencial');
      expect(fm.containsKey('passaR3'), isTrue);
    });

    test('as duas versões: a pré-registrada é a leitura, a do motor da data '
        'vem ao lado', () async {
      final cohorts = _cohorts(12);
      await seal(
          rows: _rows(cohorts), engine: _engine, folder: folder, today: 'd');
      // O motor posterior prevê outra coisa (outra semente) e sela à parte.
      await seal(
          rows: _rows(cohorts, seed: 99),
          engine: _other,
          folder: folder,
          today: 'd');
      final s = situation(
          folder: folder,
          today: DateTime(2026, 9, 24),
          dataEnd: DateTime(2027, 3, 30));
      expect((s['motoresDaData'] as Map)[_other.fingerprint], cohorts);
      expect(s['coortesSeladas'], cohorts,
          reason: 'as coortes da leitura são as do pré-registrado');

      final r = await read(
        months: 12,
        folder: folder,
        today: DateTime(2029, 9, 30),
        rows: _rows(cohorts, withReturn: true),
      );
      final preRegistered = ((r['leitura'] as Map)['famaMacBeth']
          as Map)['potencialDadoBm'] as Map;
      final ofDate = (((r['motoresDaData'] as Map)[_other.fingerprint]
          as Map)['famaMacBeth'] as Map)['potencialDadoBm'] as Map;
      expect(preRegistered['coortes'], 12);
      expect(ofDate['coortes'], 12);
      expect((preRegistered['media'] as num) - (ofDate['media'] as num), isNot(0),
          reason: 'cada série lê as próprias previsões seladas');
      expect(r['previsoesRefeitasQueDivergem'], 0,
          reason: 'a divergência é medida contra o pré-registrado');
    });

    test('juntar as coortes antigas às novas é recusado, e não filtrado',
        () async {
      await seal(
          rows: _rows(_cohorts(2)), engine: _engine, folder: folder, today: 'd');
      expect(
        () => read(
          months: 12,
          folder: folder,
          today: DateTime(2030, 1, 1),
          rows: [
            ..._rows(_cohorts(2), withReturn: true),
            ..._rows(['2025-09-30'], withReturn: true),
          ],
        ),
        throwsA(isA<ProtocolViolated>()),
      );
    });
  });

  test('a impressão do motor é estável e é a do git', () async {
    final a = await engineFingerprint();
    final b = await engineFingerprint();
    expect(a, b);
    expect(a, matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  test('o motor pré-registrado do índice está num commit, e a árvore dele tem '
      'a mesma impressão', () async {
    // A série pré-registrada das coortes novas sai de um worktree desse commit
    // (decisão 138): se a impressão do índice não fosse achável no histórico,
    // não haveria de onde refazê-la.
    final preRegistered = Index.read(Directory(sealsDir)).preRegisteredEngine;
    expect(preRegistered, isNotNull, reason: 'o C7 tem selo desde 24/09/2026');
    final commit = await commitOfFingerprint(preRegistered!.fingerprint);
    expect(commit, isNotNull);
    expect(await commitFingerprint(commit!), preRegistered.fingerprint);
  });
}
