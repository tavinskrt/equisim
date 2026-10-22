import 'dart:io';

import 'package:test/test.dart';

/// Guarda arquitetural: o núcleo de domínio deve permanecer Dart puro.
///
/// Esta é a diferença entre convenção e garantia. Sem este teste, "o domínio
/// não importa Flutter" é uma regra que alguém quebra em seis meses sem que
/// ninguém perceba; com ele, quebrar a regra derruba o build.
///
/// Também é o que permite ao CLI de validação reusar exatamente o mesmo motor
/// que roda no aplicativo.
///
/// Os caminhos partem da raiz do repositório, de onde o `flutter test` roda.
/// O teste morava dentro do pacote, e lia `lib/` e `pubspec.yaml` relativos a
/// ele; daqui, esses mesmos nomes seriam os do aplicativo — que importa
/// Flutter e declara dependências —, e a guarda passaria a vigiar o pacote
/// errado. Por isso o caminho é explícito, e o primeiro teste confere que o
/// pubspec lido é mesmo o do núcleo.
const _core = 'packages/equisim_core';

void main() {
  group('Pureza do núcleo de domínio', () {
    final forbidden = <String, String>{
      'package:flutter': 'Flutter não pode entrar no domínio.',
      'dart:ui': 'dart:ui é específico de renderização.',
      'dart:html': 'dart:html é específico de navegador.',
      'dart:js': 'dart:js é específico de navegador e incompatível com Wasm.',
      'package:http': 'Acesso a rede pertence à camada de dados.',
      'package:dio': 'Acesso a rede pertence à camada de dados.',
      'package:cloud_firestore': 'Persistência pertence à camada de dados.',
      'package:firebase': 'Persistência pertence à camada de dados.',
      'package:drift': 'Persistência pertence à camada de dados.',
      'package:shared_preferences': 'Persistência pertence à camada de dados.',
    };

    test('o pacote lido é o núcleo', () {
      final pubspec = File('$_core/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: equisim_core'));
    });

    test('nenhum arquivo importa dependência proibida', () {
      final libDir = Directory('$_core/lib');
      expect(libDir.existsSync(), isTrue, reason: '$_core/lib não encontrado');

      final violations = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (!line.startsWith('import ') && !line.startsWith('export ')) {
            continue;
          }
          for (final entry in forbidden.entries) {
            if (line.contains("'${entry.key}") ||
                line.contains('"${entry.key}')) {
              violations.add(
                '${entity.path}:${i + 1} → ${entry.key}. ${entry.value}',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Violações de pureza:\n${violations.join('\n')}',
      );
    });

    test('pubspec não declara dependências de runtime', () {
      final pubspec = File('$_core/pubspec.yaml').readAsStringSync();
      final dependenciesBlock =
          RegExp(r'^dependencies:\s*$', multiLine: true).firstMatch(pubspec);
      expect(
        dependenciesBlock,
        isNull,
        reason: 'O núcleo deve permanecer sem dependências de runtime.',
      );
    });

    test('dart:math é permitido — é biblioteca do núcleo da linguagem', () {
      // O exemplo é `inference.dart`, que precisa de `dart:math` para a t de
      // Student e a beta incompleta. Antes era `dcf.dart`, que deixou de
      // importar a biblioteca quando o desconto passou a acumular fator ano a
      // ano em vez de elevar uma taxa única a t.
      final file = File('$_core/lib/src/services/valuation/inference.dart');
      expect(file.readAsStringSync(), contains("import 'dart:math'"));
    });
  });
}
