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

    test('nenhum arquivo importa dependência proibida', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ não encontrado');

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
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final dependenciesBlock =
          RegExp(r'^dependencies:\s*$', multiLine: true).firstMatch(pubspec);
      expect(
        dependenciesBlock,
        isNull,
        reason: 'O núcleo deve permanecer sem dependências de runtime.',
      );
    });

    test('dart:math é permitido — é biblioteca do núcleo da linguagem', () {
      final file = File('lib/src/services/valuation/dcf.dart');
      expect(file.readAsStringSync(), contains("import 'dart:math'"));
    });
  });
}
