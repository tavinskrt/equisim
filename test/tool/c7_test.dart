// O protocolo da réplica fora da amostra (item C7): cada trava tem teste.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/c7/protocolo.dart';

const _motor = Motor(impressao: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _outro = Motor(impressao: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

/// As coortes do C7 de 31/12/2025 em diante, [n] trimestres.
List<String> _coortes(int n) => [
      for (var i = 0; i < n; i++)
        DateTime(2025, 12 + 3 * i + 1, 0).toIso8601String().substring(0, 10),
    ];

/// Observações sintéticas: o retorno segue o potencial com ruído, para a
/// leitura ter o que medir.
List<Map<String, dynamic>> _linhas(List<String> coortes,
    {int ativos = 40, bool comRetorno = false, int semente = 7}) {
  final rnd = math.Random(semente);
  // Gerador próprio para o desfecho: as previsões são as mesmas com ou sem
  // retorno, como num backtest refeito com a base de depois.
  final ruido = math.Random(semente + 1);
  return [
    for (final c in coortes)
      for (var a = 0; a < ativos; a++)
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
            if (comRetorno) 'ret12tot': 0.3 * up + ruido.nextDouble() * 0.2,
            if (comRetorno) 'ret36tot': 0.5 * up + ruido.nextDouble() * 0.4,
          };
        }(),
  ];
}

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('c7_'));
  tearDown(() => pasta.deleteSync(recursive: true));

  group('selagem', () {
    test('sela uma vez por coorte, sem campo de desfecho, com o hash no índice',
        () async {
      final linhas = _linhas(_coortes(3), comRetorno: true);
      final r = await selar(
          linhas: linhas, motor: _motor, pasta: pasta, hoje: '2026-09-24');
      expect(r.seladas, _coortes(3));
      expect(r.serie, 'preRegistrado');

      final indice = Indice.ler(pasta);
      expect(indice.motorPreRegistrado!.impressao, _motor.impressao);
      expect(indice.selos, hasLength(3));
      final selado = jsonDecode(
          File('${pasta.path}/previsoes_2025-12-31.json').readAsStringSync())
          as Map<String, dynamic>;
      final p = (selado['previsoes'] as List).first as Map<String, dynamic>;
      expect(p.keys.where((k) => k.startsWith('ret')), isEmpty,
          reason: 'o selo guarda previsão, e não desfecho');
      expect(indice.selos.first['hash'],
          await hashDoArquivo('${pasta.path}/previsoes_2025-12-31.json'));
    });

    test('selar de novo não reescreve: confere, e relata divergência', () async {
      final linhas = _linhas(_coortes(2));
      await selar(linhas: linhas, motor: _motor, pasta: pasta, hoje: 'd1');
      final antes =
          File('${pasta.path}/previsoes_2025-12-31.json').readAsStringSync();
      final mexidas = [
        for (final l in linhas)
          {...l, if (l['ticker'] == 'T0003') 'upside': 9.0},
      ];
      final r = await selar(
          linhas: mexidas, motor: _motor, pasta: pasta, hoje: 'd2');
      expect(r.seladas, isEmpty);
      expect(r.jaSeladas, _coortes(2));
      expect(r.divergentes, {'2025-12-31': 1, '2026-03-31': 1});
      expect(File('${pasta.path}/previsoes_2025-12-31.json').readAsStringSync(),
          antes);
    });

    test('um selo alterado depois de selado interrompe tudo', () async {
      await selar(
          linhas: _linhas(_coortes(1)), motor: _motor, pasta: pasta, hoje: 'd');
      final f = File('${pasta.path}/previsoes_2025-12-31.json');
      f.writeAsStringSync(f.readAsStringSync().replaceFirst('10.0', '11.0'));
      expect(
        () => selar(
            linhas: _linhas(_coortes(2)), motor: _motor, pasta: pasta, hoje: 'd'),
        throwsA(isA<ProtocoloViolado>()),
      );
    });

    test('coorte anterior a 31/12/2025 não é da réplica', () {
      expect(
        () => selar(
            linhas: _linhas(['2025-09-30']), motor: _motor, pasta: pasta, hoje: 'd'),
        throwsA(isA<ProtocoloViolado>()),
      );
    });

    test('motor diferente do pré-registrado sela em série própria', () async {
      await selar(
          linhas: _linhas(_coortes(1)), motor: _motor, pasta: pasta, hoje: 'd');
      final r = await selar(
          linhas: _linhas(_coortes(1)), motor: _outro, pasta: pasta, hoje: 'd');
      expect(r.serie, 'motorDaData');
      expect(r.seladas, ['2025-12-31']);
      expect(File('${pasta.path}/previsoes_2025-12-31_bbbbbbbb.json').existsSync(),
          isTrue);
      expect(Indice.ler(pasta).motorPreRegistrado!.impressao, _motor.impressao,
          reason: 'o pré-registrado não muda');
    });
  });

  group('leitura', () {
    test('antes da data, a situação — e nenhuma estatística', () async {
      await selar(
          linhas: _linhas(_coortes(3)), motor: _motor, pasta: pasta, hoje: 'd');
      final s = situacao(
          pasta: pasta,
          hoje: DateTime(2026, 9, 24),
          fimDosDados: DateTime(2027, 3, 30));
      expect(s['coortesSeladas'], _coortes(3));
      expect((s['12m'] as Map)['aberta'], isFalse);
      expect((s['12m'] as Map)['coortesMaduras'], 1,
          reason: 'só 31/12/2025 tem doze meses até 30/03/2027');
      expect(s.toString(), isNot(contains('media')));

      expect(
        () => ler(
            meses: 12,
            pasta: pasta,
            hoje: DateTime(2029, 9, 29),
            linhas: _linhas(_coortes(3), comRetorno: true)),
        throwsA(isA<ProtocoloViolado>()),
      );
    });

    test('na data, o instrumento do R3 sobre as previsões seladas', () async {
      final coortes = _coortes(12);
      await selar(
          linhas: _linhas(coortes), motor: _motor, pasta: pasta, hoje: 'd');
      // Os retornos chegam de um backtest posterior, com as mesmas previsões.
      final r = await ler(
        meses: 12,
        pasta: pasta,
        hoje: DateTime(2029, 9, 30),
        linhas: _linhas(coortes, comRetorno: true),
      );
      expect(r['previsoesRefeitasQueDivergem'], 0);
      final fm = ((r['leitura'] as Map)['famaMacBeth'] as Map)['potencialDadoBm']
          as Map;
      expect(fm['coortes'], 12);
      expect(fm['media'], greaterThan(0),
          reason: 'o retorno sintético segue o potencial');
      expect(fm.containsKey('passaR3'), isTrue);
    });

    test('juntar as coortes antigas às novas é recusado, e não filtrado',
        () async {
      await selar(
          linhas: _linhas(_coortes(2)), motor: _motor, pasta: pasta, hoje: 'd');
      expect(
        () => ler(
          meses: 12,
          pasta: pasta,
          hoje: DateTime(2030, 1, 1),
          linhas: [
            ..._linhas(_coortes(2), comRetorno: true),
            ..._linhas(['2025-09-30'], comRetorno: true),
          ],
        ),
        throwsA(isA<ProtocoloViolado>()),
      );
    });
  });

  test('a impressão do motor é estável e é a do git', () async {
    final a = await impressaoDoMotor();
    final b = await impressaoDoMotor();
    expect(a, b);
    expect(a, matches(RegExp(r'^[0-9a-f]{40}$')));
  });
}
