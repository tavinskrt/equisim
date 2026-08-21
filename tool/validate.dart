import 'dart:io';

import 'validation/context.dart';
import 'validation/data_quality.dart';
import 'validation/invariants.dart';
import 'validation/python_export.dart';
import 'validation/sensitivity.dart';

/// Executor de validação do Equisim.
///
/// Reusa **exatamente** a mesma camada de domínio e de dados que o aplicativo:
/// os mesmos repositórios, os mesmos mapeadores, o mesmo motor financeiro.
/// Não há reimplementação paralela, e por isso os números destes relatórios
/// são os mesmos que o aplicativo produz.
///
/// Uso:
///   dart run tool/validate.dart [comando] [opções]
///
/// Comandos:
///   invariantes   Identidades que o motor precisa satisfazer
///   qualidade     Portão de qualidade dos proventos
///   divergencia   Fluxo de proventos × adjustedClose da fonte
///   sensibilidade Impacto das premissas no preço justo
///   exportar      Séries e métricas para conferência em Python
///   tudo          Todos os anteriores
///
/// Opções:
///   --limit=N     Quantos ativos da amostra usar (padrão: 20)
///   --out=DIR     Diretório de saída (padrão: docs/validacao)
///   --verbose     Registra cada requisição
Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'tudo' : args.first;
  final options = _parseOptions(args);

  final outputDir = options['out'] ?? 'docs/validacao';
  final limit = int.tryParse(options['limit'] ?? '') ?? 20;
  final verbose = args.contains('--verbose');

  if (command == 'ajuda' || command == '--help' || command == '-h') {
    _printUsage();
    return;
  }

  const known = {
    'invariantes',
    'qualidade',
    'divergencia',
    'sensibilidade',
    'exportar',
    'tudo'
  };
  if (!known.contains(command)) {
    stderr.writeln('Comando desconhecido: $command\n');
    _printUsage();
    exit(64);
  }

  final sample = defaultSample.take(limit).toList();
  final ctx = ValidationContext.create(outputDir: outputDir, verbose: verbose);

  final stopwatch = Stopwatch()..start();
  stdout
    ..writeln('Equisim — executor de validação')
    ..writeln('Amostra: ${sample.length} ativos · saída: $outputDir')
    ..writeln('');

  try {
    if (command == 'invariantes' || command == 'tudo') {
      stdout.writeln('▸ Invariantes do motor');
      final checks = await Invariants.runAll(ctx);
      writeReport('$outputDir/invariantes.md', Invariants.report(checks));
      final failed = checks.where((c) => !c.passed).toList();
      if (failed.isEmpty) {
        stdout.writeln('  ${checks.length} invariantes aprovadas.');
      } else {
        stdout.writeln('  ⚠️  ${failed.length} de ${checks.length} falharam:');
        for (final check in failed) {
          stdout.writeln('     ✗ ${check.name} — ${check.detail}');
        }
      }
      stdout.writeln('');
    }

    if (command == 'qualidade' || command == 'tudo') {
      stdout.writeln('▸ Portão de qualidade dos proventos');
      final rows =
          await DataQualityReports.runQualityGate(ctx, symbols: sample);
      writeReport(
        '$outputDir/qualidade_proventos.md',
        DataQualityReports.qualityReport(rows),
      );
      stdout.writeln('');
    }

    if (command == 'divergencia' || command == 'tudo') {
      stdout.writeln('▸ Divergência contra o adjustedClose');
      final rows =
          await DataQualityReports.runDivergenceScan(ctx, symbols: sample);
      writeReport(
        '$outputDir/divergencia_adjusted_close.md',
        DataQualityReports.divergenceReport(rows),
      );
      stdout.writeln('');
    }

    if (command == 'sensibilidade' || command == 'tudo') {
      stdout.writeln('▸ Sensibilidade às premissas');
      // Amostra reduzida: cada ativo dispara dez avaliações completas.
      final points = await SensitivityReports.run(
        ctx,
        symbols: sample.take(8).toList(),
      );
      writeReport(
        '$outputDir/sensibilidade.md',
        SensitivityReports.report(points),
      );
      stdout.writeln('');
    }

    if (command == 'exportar' || command == 'tudo') {
      stdout.writeln('▸ Exportação para conferência em Python');
      await PythonExport.run(
        ctx,
        symbols: sample.take(10).toList(),
        outputDir: outputDir,
      );
      stdout.writeln('');
    }

    stopwatch.stop();
    stdout.writeln(
      'Concluído em ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s.',
    );
  } finally {
    await ctx.dispose();
  }
}

Map<String, String> _parseOptions(List<String> args) {
  final out = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final separator = arg.indexOf('=');
    if (separator < 0) continue;
    out[arg.substring(2, separator)] = arg.substring(separator + 1);
  }
  return out;
}

void _printUsage() {
  stdout.writeln('''
Executor de validação do Equisim

  dart run tool/validate.dart [comando] [opções]

Comandos:
  invariantes     Identidades que o motor precisa satisfazer
  qualidade       Portão de qualidade dos proventos
  divergencia     Fluxo de proventos × adjustedClose da fonte
  sensibilidade   Impacto das premissas no preço justo
  exportar        Séries e métricas para conferência em Python
  tudo            Todos os anteriores (padrão)

Opções:
  --limit=N       Ativos da amostra a usar (padrão: 20)
  --out=DIR       Diretório de saída (padrão: docs/validacao)
  --verbose       Registra cada requisição

A credencial vem do .env da raiz ou da variável de ambiente BRAPI_TOKEN.
O cache em arquivo torna as execuções seguintes rápidas e reprodutíveis.
''');
}
