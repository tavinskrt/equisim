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
 *
 * Autenticacao: API key do Gemini, resolvida por `qa/env.ts`. Structured
 * Output com schema forcado pelo servidor e `temperature: 0`, o que torna o
 * veredito reproduzivel e permite usar o codigo de saida como gate.
 *
 * Codigo de saida:
 *   0  PASS  -- nenhum achado com severidade FAIL
 *   1  FAIL  -- ao menos um achado FAIL (bloqueia commit / CI)
 *   2  erro de execucao (nao autenticado, git indisponivel, modelo fora do ar)
 *
 * O codigo 2 e distinto do 1 de proposito: uma falha de infraestrutura nao deve
 * ser lida como reprovacao de codigo, nem o contrario.
 */
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { basename } from 'node:path';

import {
  collectDiff,
  collectFiles,
  repoRoot,
  type AuditTarget,
} from './qa/collect.ts';
import { validateReport, type QaFinding, type QaReport } from './qa/schema.ts';
import { SYSTEM_INSTRUCTION, buildInstructions } from './qa/rules.ts';
import {
  expandScreenshotPaths,
  loadScreenshots,
  screenshotInstructions,
} from './qa/screenshot.ts';
import { chooseModel } from './qa/choose.ts';
import {
  dequeue,
  enqueue,
  listPending,
  loadPending,
  pendingCount,
} from './qa/pending.ts';
import { ApiProvider } from './qa/providers/api.ts';
import { AgyProvider, isAgyAvailable } from './qa/providers/agy.ts';
import {
  ProviderError,
  type ProviderRequest,
  type ProviderUsage,
  type QaProvider,
} from './qa/providers/types.ts';

/**
 * Imagens por chamada na varredura visual.
 *
 * A auditoria visual so roda no backend `api` -- o `agy` nao transmite imagem --
 * e o tier gratuito da 20 requisicoes/DIA. Uma chamada por imagem tornaria
 * impossivel varrer qualquer diretorio de tamanho util: 30 telas esgotariam a
 * cota antes da metade.
 *
 * 4 e o meio-termo: agrupa o suficiente para caber na cota e mantem a atencao
 * do modelo dividida entre poucas telas, para que ele consiga citar evidencia
 * especifica de cada uma. Ajustavel por --batch.
 */
const DEFAULT_BATCH = 4;

/** Tentativas para erros transitorios (429/503, modelo sobrecarregado). */
const MAX_ATTEMPTS = 3;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

type Backend = 'api' | 'agy';

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
  timeout?: number;
  noAsk: boolean;
  batch: number;
  /** --backend foi passado? Pedido explicito nao degrada em silencio. */
  backendExplicit: boolean;
  pending: boolean;
  screenshots: string[];
}

function parseArgs(argv: string[]): Cli {
  const cli: Cli = {
    backend: 'agy',
    diff: false,
    staged: false,
    base: 'HEAD~1',
    files: [],
    dryRun: false,
    context: 5,
    quiet: false,
    noAsk: false,
    batch: DEFAULT_BATCH,
    backendExplicit: false,
    pending: false,
    screenshots: [],
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case '--backend': {
        const value = argv[++i];
        if (value !== 'api' && value !== 'agy') {
          throw new Error('--backend aceita apenas `api` ou `agy`.');
        }
        cli.backend = value;
        cli.backendExplicit = true;
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
      case '--timeout': {
        const value = argv[++i];
        if (!value) throw new Error('--timeout exige um numero de segundos');
        cli.timeout = Number.parseInt(value, 10) * 1000;
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
      case '--pending':
        cli.pending = true;
        break;
      case '--batch': {
        const value = argv[++i];
        const parsed = Number.parseInt(value ?? '', 10);
        if (!Number.isInteger(parsed) || parsed < 1) {
          throw new Error('--batch exige um inteiro positivo');
        }
        cli.batch = parsed;
        break;
      }
      case '--no-ask':
        cli.noAsk = true;
        break;
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

  if (
    !cli.pending &&
    !cli.diff &&
    cli.files.length === 0 &&
    cli.screenshots.length === 0
  ) {
    throw new Error(
      'Informe o alvo da auditoria: --diff (ou --staged), --file <caminho>\n' +
        'ou --screenshot <imagem>. Use --help para ver todas as opcoes.',
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
      '  --pending              audita o que ficou na fila por falta de cota',
      '  --screenshot <img|dir> auditoria visual multimodal (repetivel).',
      '                         Diretorio e varrido recursivamente.',
      '                         Combina com --diff/--file, ou roda sozinha.',
      '                         PNG, JPEG, WebP ou HEIC.',
      '',
      'Opcoes:',
      '  --backend <agy|api>    agy (padrao) = assinatura Google AI Pro, sem',
      '                           API key, acesso a familia Pro e cota alta.',
      '                         api = API key. Schema forcado pelo servidor e',
      '                           temperature 0, mas 20 req/dia no gratuito.',
      '  --model <nome>         modelo (padrao depende do backend).',
      '                         Ex.: gemini-3.7-flash, gemini-3.1-pro-preview',
      '  --base <ref>           ref base do diff (padrao: HEAD~1)',
      '  --context <n>          linhas de contexto no diff (padrao: 5)',
      '  --thinking <n>         teto de raciocinio do modelo, em tokens.',
      '                         Menor = mais rapido, menos profundo.',
      '                         0 desliga, -1 remove o teto (padrao).',
      '  --timeout <s>          teto de tempo por chamada, em segundos.',
      '                         Padrao 240. Diff grande pode precisar de mais.',
      '  --json <caminho>       grava o relatorio bruto em JSON',
      '  --batch <n>            imagens por chamada na varredura (padrao 4).',
      '                         Cada chamada consome 1 requisicao da cota.',
      '  --no-ask               nao pergunta o modelo; usa o padrao do backend.',
      '                         Implicito quando nao ha terminal (hook, CI).',
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
  usage?: ProviderUsage,
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
    if (usage) {
      process.stdout.write(
        dim(
          usage.inputTokens > 0
            ? `Consumo: ${usage.totalTokens} tokens ` +
              `(${usage.inputTokens} entrada, ${usage.outputTokens} saida, ` +
              `${usage.thinkingTokens} raciocinio)`
            : `Consumo: ${usage.totalTokens} tokens no total`,
        ) + '\n',
      );
    }

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
): Promise<{ report: QaReport; model: string; usage?: ProviderUsage }> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const result = await provider.run(request);
      // O schema e forcado pelo servidor, entao JSON invalido aqui significa
      // resposta truncada ou filtrada -- nao formato mal pedido. Repetir o
      // mesmo prompt nao mudaria nada; a falha sobe.
      return {
        report: validateReport(JSON.parse(result.text)),
        model: result.model,
        usage: result.usage,
      };
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

/**
 * Drena a fila de auditorias adiadas por cota.
 *
 * Cada entrada e reauditada com o payload EXATO que foi liberado -- por isso a
 * fila guarda o instantaneo, e nao o intervalo de commits.
 *
 * Uma entrada so sai da fila quando foi efetivamente auditada, aprovada ou
 * reprovada. Se a cota acabar de novo no meio da drenagem, o restante fica para
 * a proxima e a saida e 2, nao 1: nao auditar nao e reprovar.
 */
async function drainPending(root: string, cli: Cli): Promise<number> {
  const queue = listPending(root);
  if (queue.length === 0) {
    process.stdout.write(
      `\n${green(bold('NADA PENDENTE'))}  a fila esta vazia.\n\n`,
    );
    return 0;
  }

  process.stdout.write(
    `\n${bold(`Fila de auditorias pendentes: ${queue.length}`)}\n`,
  );

  const provider = selectProvider(root, cli);
  provider.preflight();

  let failed = 0;
  let blocked = 0;

  for (const meta of queue) {
    const loaded = loadPending(root, meta.id);
    if (!loaded) continue;

    process.stdout.write(
      `\n${dim(`[${meta.id}] adiada em ${meta.queuedAt} -- ${meta.label}`)}\n`,
    );

    const request: ProviderRequest = {
      system: SYSTEM_INSTRUCTION,
      instructions: loaded.instructions,
      material: loaded.payload,
      model: cli.model,
    };

    try {
      const { report, model, usage } = await audit(provider, request);
      dequeue(root, meta.id);
      const target: AuditTarget = {
        mode: meta.mode,
        label: meta.label,
        payload: loaded.payload,
        files: meta.files,
        truncated: false,
      };
      renderReport(report, target, provider, model, cli, usage);
      if (report.status === 'FAIL') failed++;
    } catch (error) {
      const quota = error instanceof ProviderError && error.quota;
      const message = error instanceof Error ? error.message : String(error);
      if (quota) {
        process.stdout.write(
          `${yellow('cota esgotada de novo; o restante da fila fica para depois')}\n`,
        );
        blocked++;
        break;
      }
      process.stderr.write(`${red('falhou')}: ${message}\n`);
      blocked++;
    }
  }

  const left = pendingCount(root);
  process.stdout.write(
    `\n${dim('-'.repeat(72))}\n` +
      `drenadas com veredito: ${queue.length - left}   ainda na fila: ${left}\n\n`,
  );

  if (failed > 0) return 1;
  return blocked > 0 ? 2 : 0;
}

/**
 * Varredura visual de um diretorio, em lotes.
 *
 * Por que em lotes, e nao uma chamada por imagem: a auditoria visual so roda no
 * backend `api` -- o `agy` nao transmite imagem -- e o tier gratuito da 20
 * requisicoes por DIA. Um diretorio de 30 telas esgotaria a cota na metade.
 *
 * Por que nao tudo numa chamada so: a atencao do modelo se dilui, e o rulebook
 * exige evidencia especifica por achado ("rotulo cortado no canto inferior
 * esquerdo"). Com dezenas de imagens juntas, os achados viram genericos e
 * deixam de ser acionaveis.
 *
 * Se a cota acabar no meio, os lotes restantes vao para a fila de pendencias e
 * a saida e 2 -- nao auditar nao e reprovar. `npm run qa:pending` retoma.
 */
async function sweepScreenshots(
  root: string,
  cli: Cli,
  provider: QaProvider,
  target: AuditTarget,
  imagePaths: string[],
): Promise<number> {
  provider.preflight();

  const batches: string[][] = [];
  for (let i = 0; i < imagePaths.length; i += cli.batch) {
    batches.push(imagePaths.slice(i, i + cli.batch));
  }

  process.stdout.write(
    `\n${bold('Varredura visual')}\n` +
      dim(
        `${imagePaths.length} imagem(ns) em ${batches.length} lote(s) de ` +
          `ate ${cli.batch}. Cada lote consome 1 requisicao da cota.`,
      ) +
      '\n',
  );

  const all: QaFinding[] = [];
  let totalTokens = 0;
  let queued = 0;
  let lastModel = '';

  for (const [index, batch] of batches.entries()) {
    const screenshots = loadScreenshots(batch);
    const labels = screenshots.map((s) => s.label);

    process.stdout.write(
      dim(`\n[${index + 1}/${batches.length}] ${labels.join(', ')}`) + '\n',
    );

    const request: ProviderRequest = {
      system: SYSTEM_INSTRUCTION,
      instructions: buildInstructions(target) + screenshotInstructions(labels),
      material:
        `--- INICIO DO MATERIAL AUDITADO ---\n${target.payload}\n` +
        '--- FIM DO MATERIAL AUDITADO ---\n',
      model: cli.model,
      screenshots: screenshots.map((s) => s.part),
    };

    try {
      const { report, model, usage } = await audit(provider, request);
      lastModel = model;
      totalTokens += usage?.totalTokens ?? 0;
      all.push(...report.findings);
      process.stdout.write(
        dim(
          `      ${report.findings.length} achado(s)` +
            (usage ? `, ${usage.totalTokens} tokens` : ''),
        ) + '\n',
      );
    } catch (error) {
      // QUALQUER falha aqui enfileira o restante -- nao so a de cota.
      //
      // Aprendido na pratica: um 503 no lote 3 de 4 derrubava a varredura por
      // excecao, jogando fora os achados dos lotes 1 e 2 e as requisicoes de
      // cota que eles ja tinham consumido. Preservar o trabalho feito importa
      // mais do que distinguir a causa; a causa entra na mensagem.
      {
        const quota = error instanceof ProviderError && error.quota;
        const detail = error instanceof Error ? error.message : String(error);

        // Enfileira ESTE lote e todos os seguintes, um por vez, para que a
        // drenagem retome exatamente de onde parou.
        for (const remaining of batches.slice(index)) {
          const shots = loadScreenshots(remaining);
          const names = shots.map((s) => s.label);
          const { queued: ok } = enqueue(
            root,
            {
              label: `varredura visual: ${names.join(', ')}`,
              mode: 'screenshot',
              files: remaining,
              head: currentHead(root),
              reason: quota ? 'cota esgotada' : 'falha transitoria',
            },
            target.payload,
            buildInstructions(target) + screenshotInstructions(names),
          );
          if (ok) queued++;
        }

        process.stdout.write(
          `\n${yellow(bold(quota ? 'COTA ESGOTADA' : 'FALHA NO LOTE'))} ` +
            `no lote ${index + 1} de ${batches.length}.\n` +
            dim(`  ${detail.split('\n')[0]}\n`) +
            dim(`  ${queued} lote(s) enfileirado(s); os anteriores foram preservados.\n`) +
            dim('  Retome com: npm run qa:pending\n') +
            '\n',
        );
        break;
      }
    }
  }

  const merged: QaReport = {
    findings: all,
    status: all.some((f) => f.severity === 'FAIL') ? 'FAIL' : 'PASS',
    summary:
      `Varredura de ${imagePaths.length} tela(s) em ${batches.length} lote(s). ` +
      `${all.length} achado(s) no total.` +
      (queued > 0 ? ` ${queued} lote(s) ficaram pendentes por cota.` : ''),
  };

  const sweepTarget: AuditTarget = {
    ...target,
    label: `varredura visual de ${imagePaths.length} imagem(ns)`,
    // Nomes, nao caminhos absolutos: uma lista de 30 caminhos completos torna
    // o cabecalho ilegivel, e o achado ja identifica o arquivo por nome.
    files: imagePaths.map((p) => basename(p)),
  };

  // O backend `api` nao reporta consumo por chamada. Exibir "0 tokens" seria
  // pior que omitir: parece medicao, e e ausencia de medicao.
  // O `--json` tambem vale aqui. Ignorar a flag em silencio numa varredura e
  // pior que noutro lugar: e justamente o modo em que mais achados se acumulam,
  // e onde perder o relatorio custa varias requisicoes de cota para refazer.
  if (cli.json) {
    writeFileSync(cli.json, JSON.stringify(merged, null, 2), 'utf8');
    process.stderr.write(dim(`relatorio bruto gravado em ${cli.json}
`));
  }

  renderReport(
    merged,
    sweepTarget,
    provider,
    lastModel || '(nenhum)',
    cli,
    totalTokens > 0
      ? { inputTokens: 0, outputTokens: 0, thinkingTokens: 0, totalTokens }
      : undefined,
  );

  if (merged.status === 'FAIL') return 1;
  return queued > 0 ? 2 : 0;
}

/** Commit corrente, so para diagnostico na entrada da fila. */
function currentHead(root: string): string {
  try {
    return execFileSync('git', ['rev-parse', '--short', 'HEAD'], {
      cwd: root,
      encoding: 'utf8',
    }).trim();
  } catch {
    return '(desconhecido)';
  }
}

/**
 * Escolhe o backend, degradando quando o `agy` nao esta disponivel.
 *
 * A assimetria e deliberada:
 *
 *   padrao implicito  -> avisa e cai para `api`. Um projeto instalado pelo
 *                        toolkit numa maquina sem Antigravity precisa auditar,
 *                        nao morrer na largada.
 *   --backend agy     -> falha. Quem pediu explicitamente precisa saber que
 *                        nao foi atendido; degradar caladamente entregaria um
 *                        veredito de outro modelo sob o nome do pedido.
 */
function selectProvider(root: string, cli: Cli): QaProvider {
  if (cli.backend !== 'agy') {
    return new ApiProvider(root, cli.thinking, cli.timeout);
  }
  if (isAgyAvailable()) return new AgyProvider(cli.timeout);

  if (cli.backendExplicit) {
    throw new Error(
      'O backend `agy` foi pedido, mas o CLI nao esta disponivel nesta maquina.\n' +
        '  Confirme com: agy --version\n' +
        '  Ele acompanha o Antigravity; aponte outro caminho com AGY_PATH.\n\n' +
        '  Para auditar com API key: --backend api',
    );
  }

  process.stderr.write(
    `${yellow('agy indisponivel')}; usando o backend api (API key).\n` +
      dim('  O tier gratuito da 20 requisicoes/dia. Instale o Antigravity\n') +
      dim('  para auditar pela assinatura, sem esse teto.\n'),
  );
  return new ApiProvider(root, cli.thinking, cli.timeout);
}

async function main(): Promise<number> {
  const cli = parseArgs(process.argv.slice(2));
  const root = repoRoot(process.cwd());

  if (cli.pending) return drainPending(root, cli);

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

  const provider = selectProvider(root, cli);

  const imagePaths = expandScreenshotPaths(cli.screenshots);

  // Varredura de diretorio vira varias chamadas; uma so imagem segue o caminho
  // normal, sem o cabecalho de lote.
  if (imagePaths.length > cli.batch) {
    return sweepScreenshots(root, cli, provider, target, imagePaths);
  }

  const screenshots = loadScreenshots(imagePaths);

  const instructions =
    buildInstructions(target) +
    (screenshots.length > 0
      ? screenshotInstructions(screenshots.map((s) => s.label))
      : '');

  // A escolha do modelo vem DEPOIS da coleta, para que a pergunta possa mostrar
  // o tamanho real do alvo -- e antes do dry-run nao ser necessario, por isso o
  // seletor e pulado quando so vamos imprimir o payload.
  const chosenModel =
    provider.name === 'agy' && !cli.dryRun
      ? await chooseModel(target, {
          interactive:
            process.stdin.isTTY === true &&
            process.stdout.isTTY === true &&
            !cli.noAsk &&
            !cli.quiet,
          explicitModel: cli.model,
        })
      : cli.model;

  const request: ProviderRequest = {
    system: SYSTEM_INSTRUCTION,
    instructions,
    material:
      `--- INICIO DO MATERIAL AUDITADO ---\n${target.payload}\n` +
      '--- FIM DO MATERIAL AUDITADO ---\n',
    model: chosenModel,
    screenshots: screenshots.map((s) => s.part),
  };

  if (cli.dryRun) {
    process.stdout.write(bold('\n=== SYSTEM INSTRUCTION ===\n\n'));
    process.stdout.write(request.system + '\n');
    process.stdout.write(bold('\n=== INSTRUCOES ===\n\n'));
    process.stdout.write(request.instructions + '\n');
    // O material E o ponto do dry-run: sem ele nao da para conferir o que
    // seria enviado, nem se a coleta pegou os arquivos certos.
    process.stdout.write(bold('\n=== MATERIAL ===\n\n'));
    process.stdout.write(request.material + '\n');
    if (request.screenshots && request.screenshots.length > 0) {
      process.stdout.write(
        dim(`[${request.screenshots.length} imagem(ns) anexada(s), nao exibida(s)]\n`),
      );
    }
    process.stdout.write(
      dim(
        `\n[dry-run] modelo=${cli.model ?? 'padrao'}, ` +
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

  let audited;
  try {
    audited = await audit(provider, request);
  } catch (error) {
    // Cota esgotada nao pode travar o trabalho -- mas tambem nao pode sumir.
    // Guardamos o payload exato para reauditar depois com `--pending`.
    if (error instanceof ProviderError && error.quota) {
      const { queued, id } = enqueue(
        root,
        {
          label: target.label,
          mode: target.mode,
          files: target.files,
          head: currentHead(root),
          reason: 'cota esgotada',
        },
        request.material,
        request.instructions,
      );
      process.stderr.write(
        `\n${yellow(bold('COTA ESGOTADA'))}\n${error.message}\n\n` +
          (queued
            ? `${dim(`Auditoria enfileirada [${id}]. Quando a cota voltar:`)}\n` +
              '    npm run qa:pending\n\n'
            : `${dim(`Este mesmo material ja estava na fila [${id}].`)}\n\n`),
      );
      return 2;
    }
    throw error;
  }
  const { report, model, usage } = audited;

  if (cli.json) {
    writeFileSync(cli.json, JSON.stringify(report, null, 2), 'utf8');
    process.stderr.write(dim(`relatorio bruto gravado em ${cli.json}\n`));
  }

  renderReport(report, target, provider, model, cli, usage);

  const waiting = pendingCount(root);
  if (waiting > 0) {
    process.stdout.write(
      dim(
        `${waiting} auditoria(s) aguardando cota. Rode: npm run qa:pending`,
      ) + '\n\n',
    );
  }
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
