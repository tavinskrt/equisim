import { tryParseInt } from '../src/core';
import { errln, outln } from './lib/files';
import { defaultSample, ValidationContext, writeReport } from './validation/context';
import { InferenceExport } from './validation/inference-export';
import { Invariants } from './validation/invariants';
import { OutOfSampleValidation } from './validation/out-of-sample';
import { PythonExport } from './validation/python-export';
import { SensitivityReports } from './validation/sensitivity';

/**
 * Executor de validação do Equisim.
 *
 * Reusa **exatamente** a mesma camada de domínio e de dados que o aplicativo:
 * os mesmos repositórios, os mesmos mapeadores, o mesmo motor financeiro.
 * Não há reimplementação paralela, e por isso os números destes relatórios
 * são os mesmos que o aplicativo produz.
 *
 * Uso:
 *   npm run tool -- validate [comando] [opções]
 *
 * Comandos:
 *   invariantes   Identidades que o motor precisa satisfazer
 *   sensibilidade Impacto das premissas no preço justo
 *   exportar      Séries e métricas para conferência em Python
 *   inferencia    Primitivas estatísticas do núcleo, para conferência externa
 *   tudo          Todos os anteriores
 *
 * Opções:
 *   --limit=N     Quantos ativos da amostra usar (padrão: 20)
 *   --out=DIR     Diretório de saída (padrão: docs/validacao)
 *   --verbose     Registra cada requisição
 */
export async function main(args: string[]): Promise<void> {
  const command = args.length === 0 ? 'tudo' : args[0]!;
  const options = parseOptions(args);

  const outputDir = options.get('out') ?? 'docs/validacao';
  const limit = tryParseInt(options.get('limit') ?? '') ?? 20;
  const verbose = args.includes('--verbose');

  if (command === 'ajuda' || command === '--help' || command === '-h') {
    printUsage();
    return;
  }

  const known = new Set(['invariantes', 'sensibilidade', 'exportar', 'fora-da-amostra', 'inferencia', 'tudo']);
  if (!known.has(command)) {
    errln(`Comando desconhecido: ${command}\n`);
    printUsage();
    process.exit(64);
  }

  const sample = defaultSample.slice(0, Math.max(0, limit));
  const ctx = ValidationContext.create({ outputDir, verbose });

  const started = performance.now();
  outln('Equisim — executor de validação');
  outln(`Amostra: ${sample.length} ativos · saída: ${outputDir}`);
  outln('');

  try {
    if (command === 'invariantes' || command === 'tudo') {
      outln('▸ Invariantes do motor');
      const checks = await Invariants.runAll(ctx);
      writeReport(`${outputDir}/invariantes.md`, Invariants.report(checks));
      const failed = checks.filter((c) => !c.passed);
      if (failed.length === 0) {
        outln(`  ${checks.length} invariantes aprovadas.`);
      } else {
        outln(`  ⚠️  ${failed.length} de ${checks.length} falharam:`);
        for (const check of failed) outln(`     ✗ ${check.name} — ${check.detail}`);
      }
      outln('');
    }

    if (command === 'sensibilidade' || command === 'tudo') {
      outln('▸ Sensibilidade às premissas');
      // Amostra reduzida: cada ativo dispara dez avaliações completas.
      const points = await SensitivityReports.run(ctx, sample.slice(0, 8));
      writeReport(`${outputDir}/sensibilidade.md`, SensitivityReports.report(points));
      outln('');
    }

    if (command === 'exportar' || command === 'tudo') {
      outln('▸ Exportação para conferência em Python');
      await PythonExport.run(ctx, { symbols: sample.slice(0, 10), outputDir });
      outln('');
    }

    if (command === 'inferencia' || command === 'tudo') {
      outln('> Primitivas estatisticas — exportacao para conferencia');
      InferenceExport.run({ outputDir });
      outln('');
    }

    if (command === 'fora-da-amostra') {
      outln('▸ Validação fora da amostra — árvore de portas');
      await OutOfSampleValidation.run(ctx, { outputDir, limit });
      outln('');
    }

    outln(`Concluído em ${((performance.now() - started) / 1000).toFixed(1)}s.`);
  } finally {
    await ctx.dispose();
  }
}

function parseOptions(args: readonly string[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const arg of args) {
    if (!arg.startsWith('--')) continue;
    const separator = arg.indexOf('=');
    if (separator < 0) continue;
    out.set(arg.slice(2, separator), arg.slice(separator + 1));
  }
  return out;
}

function printUsage(): void {
  outln(`Executor de validação do Equisim

  npm run tool -- validate [comando] [opções]

Comandos:
  invariantes     Identidades que o motor precisa satisfazer
  sensibilidade   Impacto das premissas no preço justo
  exportar        Séries e métricas para conferência em Python
  tudo            Todos os anteriores (padrão)

Opções:
  --limit=N       Ativos da amostra a usar (padrão: 20)
  --out=DIR       Diretório de saída (padrão: docs/validacao)
  --verbose       Registra cada requisição

A credencial vem do .env da raiz ou da variável de ambiente BRAPI_TOKEN.
O cache em arquivo torna as execuções seguintes rápidas e reprodutíveis.
`);
}
