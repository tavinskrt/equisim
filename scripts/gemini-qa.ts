#!/usr/bin/env -S npx tsx
/**
 * Agente autonomo de QA -- auditoria financeira e de responsividade via Gemini.
 *
 * Uso:
 *   npx tsx scripts/gemini-qa.ts --diff
 *   npx tsx scripts/gemini-qa.ts --diff --staged
 *   npx tsx scripts/gemini-qa.ts --diff --base HEAD~3
 *   npx tsx scripts/gemini-qa.ts --file lib/presentation/backtest/backtest_page.dart
 *   npx tsx scripts/gemini-qa.ts --diff --dry-run              (nao chama o modelo)
 *   npx tsx scripts/gemini-qa.ts --file X --backend antigravity (auditoria profunda)
 *
 * Dois backends, com papeis distintos:
 *
 *   api (padrao)  API key + Structured Output forcado + temperature 0.
 *                 Deterministico e rapido. E o UNICO que funciona fora da IDE,
 *                 portanto o unico que sustenta o hook de pre-commit -- os
 *                 commits deste projeto saem pelo GitHub Desktop.
 *
 *   antigravity   Assinatura Google AI Pro via agentapi do Antigravity, sem
 *                 API key. So roda no terminal integrado da IDE. Para auditoria
 *                 profunda sob demanda, onde o modelo Pro compensa o tempo.
 *
 * Ver `scripts/qa/providers/types.ts` para o racional completo.
 *
 * Codigo de saida:
 *   0  PASS  -- nenhum achado com severidade FAIL
 *   1  FAIL  -- ao menos um achado FAIL (bloqueia commit / CI)
 *   2  erro de execucao (nao autenticado, git indisponivel, modelo fora do ar)
 *
 * O codigo 2 e distinto do 1 de proposito: uma falha de infraestrutura nao deve
 * ser lida como reprovacao de codigo, nem o contrario.
 */
import { writeFileSync } from 'node:fs';

import {
  collectDiff,
  collectFiles,
  repoRoot,
  type AuditTarget,
} from './qa/collect.ts';
import { validateReport, type QaFinding, type QaReport } from './qa/schema.ts';
import { SYSTEM_INSTRUCTION, buildInstructions } from './qa/rules.ts';
import { loadScreenshots, screenshotInstructions } from './qa/screenshot.ts';
import { ApiProvider } from './qa/providers/api.ts';
import { AntigravityProvider } from './qa/providers/antigravity.ts';
import {
  ProviderError,
  type ProviderRequest,
  type QaProvider,
} from './qa/providers/types.ts';

/** Tentativas para erros transitorios (429/503, modelo sobrecarregado). */
const MAX_ATTEMPTS = 3;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

type Backend = 'api' | 'antigravity';

interface Cli {
  backend: Backend;
  diff: boolean;
  staged: boolean;
  base: string;
  files: string[];
  dryRun: boolean;
  json?: string;
  model?: string;
  context: number;
  quiet: boolean;
  thinking?: number;
  screenshots: string[];
}

function parseArgs(argv: string[]): Cli {
  const cli: Cli = {
    backend: 'api',
    diff: false,
    staged: false,
    base: 'HEAD~1',
    files: [],
    dryRun: false,
    context: 5,
    quiet: false,
    screenshots: [],
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case '--backend': {
        const value = argv[++i];
        if (value !== 'api' && value !== 'antigravity') {
          throw new Error('--backend aceita apenas `api` ou `antigravity`.');
        }
        cli.backend = value;
        break;
      }
      case '--diff':
        cli.diff = true;
        break;
      case '--staged':
        cli.diff = true;
        cli.staged = true;
        break;
      case '--base': {
        const value = argv[++i];
        if (!value) throw new Error('--base exige um ref (ex.: --base HEAD~3)');
        cli.base = value;
        break;
      }
      case '--file': {
        const value = argv[++i];
        if (!value) throw new Error('--file exige um caminho');
        cli.files.push(value);
        break;
      }
      case '--json': {
        const value = argv[++i];
        if (!value) throw new Error('--json exige um caminho de saida');
        cli.json = value;
        break;
      }
      case '--model': {
        const value = argv[++i];
        if (!value) throw new Error('--model exige um nome de modelo');
        cli.model = value;
        break;
      }
      case '--screenshot': {
        const value = argv[++i];
        if (!value) throw new Error('--screenshot exige um caminho de imagem');
        cli.screenshots.push(value);
        break;
      }
      case '--thinking': {
        const value = argv[++i];
        if (!value) throw new Error('--thinking exige um numero de tokens');
        cli.thinking = Number.parseInt(value, 10);
        break;
      }
      case '--context': {
        const value = argv[++i];
        if (!value) throw new Error('--context exige um numero de linhas');
        cli.context = Number.parseInt(value, 10);
        break;
      }
      case '--dry-run':
        cli.dryRun = true;
        break;
      case '--quiet':
        cli.quiet = true;
        break;
      case '--help':
      case '-h':
        printUsage();
        process.exit(0);
      // eslint-disable-next-line no-fallthrough
      default:
        throw new Error(`Argumento desconhecido: ${arg}`);
    }
  }

  if (!cli.diff && cli.files.length === 0 && cli.screenshots.length === 0) {
    throw new Error(
      'Informe o alvo da auditoria: --diff (ou --staged), --file <caminho>\n' +
        'ou --screenshot <imagem>. Use --help para ver todas as opcoes.',
    );
  }
  if (cli.screenshots.length > 0 && cli.backend !== 'api') {
    throw new Error(
      'Auditoria visual exige o backend multimodal: adicione --backend api.\n' +
        'A agentapi do Antigravity nao tem canal para anexar imagem.',
    );
  }
  if (cli.diff && cli.files.length > 0) {
    throw new Error('--diff e --file sao mutuamente exclusivos.');
  }
  return cli;
}

function printUsage(): void {
  process.stdout.write(
    [
      'Agente de QA (Gemini) -- auditoria financeira e de responsividade',
      '',
      'Alvo (obrigatorio, escolha um):',
      '  --diff                 audita o diff contra o ref base (padrao HEAD~1)',
      '  --staged               audita apenas o que esta em staging',
      '  --file <caminho>       audita o arquivo integral (repetivel)',
      '  --screenshot <img>     auditoria visual multimodal (repetivel).',
      '                         Combina com --diff/--file, ou roda sozinha.',
      '                         Requer backend api. PNG, JPEG, WebP, HEIC.',
      '',
      'Opcoes:',
      '  --backend <api|antigravity>',
      '                         api (padrao) = API key, schema forcado, rapido.',
      '                           Unico que funciona em hook/CI/GitHub Desktop.',
      '                         antigravity = plano Google AI Pro, sem API key.',
      '                           So roda no terminal integrado da IDE.',
      '  --model <nome>         sobrepoe o modelo padrao do backend.',
      '                         api: gemini-3.5-flash, gemini-3.7-flash, ...',
      '                         antigravity: pro | flash | flash_lite',
      '  --base <ref>           ref base do diff (padrao: HEAD~1)',
      '  --context <n>          linhas de contexto no diff (padrao: 5)',
      '  --thinking <n>         teto de raciocinio do modelo, em tokens.',
      '                         Menor = mais rapido, menos profundo.',
      '                         0 desliga, -1 remove o teto. So no backend api.',
      '  --json <caminho>       grava o relatorio bruto em JSON',
      '  --dry-run              monta o payload e imprime, sem chamar o modelo',
      '  --quiet                imprime apenas o veredito final',
      '  -h, --help             esta ajuda',
      '',
      'Saida: 0 = PASS, 1 = FAIL, 2 = erro de execucao.',
      '',
    ].join('\n'),
  );
}

// ---------------------------------------------------------------------------
// Apresentacao
// ---------------------------------------------------------------------------

const useColor = process.stdout.isTTY === true && !process.env.NO_COLOR;
const paint = (code: string, text: string): string =>
  useColor ? `\u001b[${code}m${text}\u001b[0m` : text;

const bold = (t: string) => paint('1', t);
const dim = (t: string) => paint('2', t);
const red = (t: string) => paint('31', t);
const green = (t: string) => paint('32', t);
const yellow = (t: string) => paint('33', t);
const blue = (t: string) => paint('34', t);

function severityTag(severity: QaFinding['severity']): string {
  switch (severity) {
    case 'FAIL':
      return red(bold(' FAIL '));
    case 'WARN':
      return yellow(bold(' WARN '));
    default:
      return blue(bold(' INFO '));
  }
}

/** Quebra de linha simples para caber em terminal de 100 colunas. */
function wrap(text: string, indent: number): string {
  const width = 100 - indent;
  const words = text.trim().split(/\s+/);
  const out: string[] = [];
  let line = '';
  for (const word of words) {
    if (line.length + word.length + 1 > width) {
      out.push(line);
      line = word;
    } else {
      line = line === '' ? word : `${line} ${word}`;
    }
  }
  if (line !== '') out.push(line);
  return out.join('\n' + ' '.repeat(indent));
}

function renderFinding(finding: QaFinding, index: number): string {
  const lines: string[] = [];
  const location =
    finding.line > 0 ? `${finding.file}:${finding.line}` : finding.file;

  lines.push('');
  lines.push(`${severityTag(finding.severity)} ${bold(`${index}. ${finding.title}`)}`);
  lines.push(`        ${dim(location)}  ${dim(`[${finding.category}]`)}`);
  lines.push('');
  lines.push(
    `        ${dim('evidencia')}  ` +
      finding.evidence.trim().replace(/\n/g, '\n                   '),
  );
  lines.push(`        ${dim('porque   ')}  ${wrap(finding.rationale, 19)}`);
  lines.push(`        ${dim('falha em ')}  ${wrap(finding.failure_scenario, 19)}`);
  lines.push(`        ${dim('correcao ')}  ${wrap(finding.suggested_fix, 19)}`);
  return lines.join('\n');
}

function renderReport(
  report: QaReport,
  target: AuditTarget,
  provider: QaProvider,
  model: string,
  cli: Cli,
): void {
  const fails = report.findings.filter((f) => f.severity === 'FAIL');
  const warns = report.findings.filter((f) => f.severity === 'WARN');
  const infos = report.findings.filter((f) => f.severity === 'INFO');

  if (!cli.quiet) {
    process.stdout.write('\n' + bold('Agente de QA -- Gemini') + '\n');
    process.stdout.write(dim(`Alvo:    ${target.label}`) + '\n');
    process.stdout.write(
      dim(
        `Escopo:  ${target.files.length} arquivo(s)` +
          (target.files.length > 0 ? ` -- ${target.files.join(', ')}` : ''),
      ) + '\n',
    );
    process.stdout.write(
      dim(`Modelo:  ${model} via ${provider.name} -- ${provider.describeAuth()}`) +
        '\n',
    );

    const ordered = [...fails, ...warns, ...infos];
    ordered.forEach((f, i) => process.stdout.write(renderFinding(f, i + 1) + '\n'));

    process.stdout.write('\n' + dim('-'.repeat(72)) + '\n');
    process.stdout.write(wrap(report.summary, 0) + '\n\n');
  }

  const counts = `${fails.length} FAIL / ${warns.length} WARN / ${infos.length} INFO`;

  if (fails.length > 0) {
    process.stdout.write(`${red(bold('REPROVADO'))}  ${counts}\n`);
    process.stdout.write(
      dim('Corrija os achados FAIL e rode novamente. WARN nao bloqueia.') + '\n\n',
    );
  } else {
    process.stdout.write(`${green(bold('APROVADO'))}  ${counts}\n\n`);
  }
}

// ---------------------------------------------------------------------------
// Orquestracao
// ---------------------------------------------------------------------------

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

async function audit(
  provider: QaProvider,
  request: ProviderRequest,
): Promise<{ report: QaReport; model: string }> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const result = await provider.run(request);
      try {
        return { report: validateReport(JSON.parse(result.text)), model: result.model };
      } catch (parseError) {
        // Backends sem schema forcado pelo servidor (antigravity) podem devolver
        // JSON sujo -- modo de falha esperado, recuperavel apontando o erro ao
        // modelo. O backend `api` nao implementa `repair` de proposito: se o
        // schema forcado falhou, insistir no mesmo prompt nao muda nada.
        if (typeof provider.repair !== 'function') throw parseError;

        const detail =
          parseError instanceof Error ? parseError.message : String(parseError);
        process.stderr.write(
          dim(`  resposta invalida (${detail}); pedindo correcao do formato\n`),
        );
        const repaired = await provider.repair(request, result.text, detail);
        return {
          report: validateReport(JSON.parse(repaired.text)),
          model: repaired.model,
        };
      }
    } catch (error) {
      lastError = error;
      const transient = error instanceof ProviderError && error.transient;
      if (attempt < MAX_ATTEMPTS && transient) {
        const backoff = 2 ** attempt * 1000;
        process.stderr.write(
          dim(`  tentativa ${attempt} falhou (transitorio); nova em ${backoff}ms\n`),
        );
        await sleep(backoff);
        continue;
      }
      throw error;
    }
  }
  throw lastError;
}

async function main(): Promise<number> {
  const cli = parseArgs(process.argv.slice(2));
  const root = repoRoot(process.cwd());

  const visualOnly = !cli.diff && cli.files.length === 0;

  const target: AuditTarget = cli.diff
    ? collectDiff(root, {
        staged: cli.staged,
        base: cli.base,
        contextLines: cli.context,
      })
    : visualOnly
      ? {
          mode: 'screenshot',
          label: `${cli.screenshots.length} captura(s) de tela`,
          payload: '(auditoria visual: nenhum codigo anexado)',
          files: [],
          truncated: false,
        }
      : collectFiles(root, cli.files);

  // Um diff vazio nao e reprovacao: nada mudou, nada a auditar. Mas se ha
  // captura de tela, existe material mesmo sem codigo.
  if (target.payload.trim() === '' && cli.screenshots.length === 0) {
    process.stdout.write(
      `\n${green(bold('APROVADO'))}  nada para auditar ` +
        `(${target.label} nao produziu conteudo).\n\n`,
    );
    return 0;
  }

  const provider: QaProvider =
    cli.backend === 'antigravity'
      ? new AntigravityProvider()
      : new ApiProvider(root, cli.thinking);

  // So o backend antigravity precisa do schema em texto: o `api` recebe o
  // schema forcado pelo servidor.
  const screenshots = loadScreenshots(cli.screenshots);

  const instructions =
    buildInstructions(target, provider.name === 'antigravity') +
    (screenshots.length > 0
      ? screenshotInstructions(screenshots.map((s) => s.label))
      : '');

  const request: ProviderRequest = {
    system: SYSTEM_INSTRUCTION,
    instructions,
    material:
      `--- INICIO DO MATERIAL AUDITADO ---\n${target.payload}\n` +
      '--- FIM DO MATERIAL AUDITADO ---\n',
    model: cli.model,
    screenshots: screenshots.map((s) => s.part),
  };

  if (cli.dryRun) {
    process.stdout.write(bold('\n=== SYSTEM INSTRUCTION ===\n\n'));
    process.stdout.write(request.system + '\n');
    process.stdout.write(bold('\n=== INSTRUCOES ===\n\n'));
    process.stdout.write(request.instructions + '\n');
    process.stdout.write(
      dim(
        `\n[dry-run] backend=${provider.name}, ` +
          `${target.payload.length} caracteres de material, ` +
          `${target.files.length} arquivo(s). Nenhuma chamada ao modelo foi feita.\n\n`,
      ),
    );
    return 0;
  }

  provider.preflight();

  if (!cli.quiet) {
    process.stderr.write(
      dim(`\nauditando ${target.label} via ${provider.describeAuth()}...\n`),
    );
  }

  const { report, model } = await audit(provider, request);

  if (cli.json) {
    writeFileSync(cli.json, JSON.stringify(report, null, 2), 'utf8');
    process.stderr.write(dim(`relatorio bruto gravado em ${cli.json}\n`));
  }

  renderReport(report, target, provider, model, cli);
  return report.status === 'FAIL' ? 1 : 0;
}

// Define `process.exitCode` em vez de chamar `process.exit()`. Com handles
// assincronos ainda abertos, o encerramento abrupto dispara uma assercao do
// libuv no Windows -- `UV_HANDLE_CLOSING` -- que poluiria a saida do hook de
// pre-commit. Deixar o loop de eventos drenar preserva o codigo de saida.
main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`\n${red(bold('ERRO DE EXECUCAO'))}\n${message}\n\n`);
    process.exitCode = 2;
  });
