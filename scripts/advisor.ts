/**
 * CONSELHEIRO -- o segundo agente do projeto.
 *
 *     npm run conselho -- --lente registro
 *
 * Le o projeto por dominio e devolve inventario, tensoes, alvo e sequencia. Nao
 * e o auditor e nao substitui o auditor: aquele caca defeito de correcao em
 * linha de codigo e BLOQUEIA; este examina relacao entre coisas e nao bloqueia
 * nada.
 *
 * ESTE PROGRAMA SAI COM CODIGO 0 EM QUALQUER CIRCUNSTANCIA, inclusive em falha
 * de rede, cota ou JSON invalido. Nao e descuido, e requisito: no instante em
 * que um conselho puder travar um `git push`, o gate inteiro passa a ser visto
 * como obstaculo e alguem o arranca. Ver a nota sobre `.githooks` no README dos
 * scripts -- nenhuma das camadas de hook chama este arquivo.
 *
 * Ele COMPARTILHA o transporte do auditor: `providers/`, `choose.ts`,
 * `models.ts` e `env.ts` entram sem alteracao. O que muda e o schema (via
 * `ProviderRequest.schema`), o rulebook e o coletor.
 */
import { existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { repoRoot } from './qa/collect.ts';
import { chooseModel } from './qa/choose.ts';
import { AgyProvider, isAgyAvailable } from './qa/providers/agy.ts';
import { API_FLASH_CASCADE, ApiProvider } from './qa/providers/api.ts';
import {
  ProviderError,
  type ProviderRequest,
  type ProviderUsage,
  type QaProvider,
} from './qa/providers/types.ts';
import { collectLens, type AdvisorTarget } from './qa/advisor/collect.ts';
import { openBoundaries } from './qa/advisor/postura.ts';
import { LENSES, SUGGESTED_ORDER, resolveLens } from './qa/advisor/lentes.ts';
import {
  buildAdvisorInstructions,
  buildAdvisorSystem,
  visualInstructions,
} from './qa/advisor/rules.ts';
import { loadScreenshots } from './qa/screenshot.ts';
import {
  ADVISOR_RESPONSE_SCHEMA,
  validateAdvisorReport,
  type AdvisorReport,
  type AdvisorSeverity,
} from './qa/advisor/schema.ts';

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

function severityTag(s: AdvisorSeverity): string {
  switch (s) {
    case 'ESTRUTURAL':
      return red(bold(' ESTRUTURAL '));
    case 'LOCAL':
      return yellow(bold('   LOCAL    '));
    default:
      return blue(bold(' POLIMENTO  '));
  }
}

/** Quebra texto em `width` colunas, recuando as linhas seguintes. */
function wrap(text: string, indent: number, width = 76): string {
  const limit = Math.max(24, width - indent);
  const prefix = ' '.repeat(indent);
  const lines: string[] = [];
  let current = '';
  for (const word of text.split(/\s+/).filter((p) => p !== '')) {
    if (current === '') current = word;
    else if (current.length + 1 + word.length <= limit) current += ' ' + word;
    else {
      lines.push(current);
      current = word;
    }
  }
  if (current !== '') lines.push(current);
  return lines.join('\n' + prefix);
}

function renderReport(
  report: AdvisorReport,
  target: AdvisorTarget,
  model: string,
  provider: QaProvider,
  usage?: ProviderUsage,
): void {
  const out = process.stdout;
  out.write('\n' + bold(`Conselheiro -- lente ${report.lente}`) + '\n');
  out.write(dim(`Alvo:    ${target.label}`) + '\n');
  out.write(dim(`Modelo:  ${model} via ${provider.name} -- ${provider.describeAuth()}`) + '\n');
  // Um parecer do ultimo degrau da cascata nao merece a mesma confianca do
  // primeiro, e quem le precisa saber disso ANTES de agir sobre o conteudo.
  // O degrau e deduzido do nome porque e o que a resposta informa: o campo
  // `modelVersion` traz a versao concreta que atendeu, nao o que foi pedido.
  const topo = API_FLASH_CASCADE[0] ?? '';
  if (provider.name === 'api' && topo !== '' && !model.startsWith(topo)) {
    // Prefixo MAIS LONGO, nao o primeiro que casa: `gemini-3.5-flash-lite`
    // comeca com `gemini-3.5-flash`, entao `findIndex` acusava o degrau 3
    // quando quem respondeu era o 4. Errar o degrau subestima o rebaixamento,
    // que e justamente o que este aviso existe para nao deixar passar.
    let rung = -1;
    let largest = 0;
    for (const [i, m] of API_FLASH_CASCADE.entries()) {
      if (model.startsWith(m) && m.length > largest) {
        largest = m.length;
        rung = i;
      }
    }
    out.write(
      yellow(
        `AVISO:   modelo rebaixado (degrau ${rung < 0 ? '?' : rung + 1} de ` +
          `${API_FLASH_CASCADE.length}). O topo da cascata nao respondeu.\n`,
      ) + dim('         Leia este parecer com menos confianca que o usual.\n'),
    );
  }
  if (usage) out.write(dim(`Tokens:  ${usage.totalTokens}`) + '\n');
  if (target.truncated) {
    out.write(yellow('AVISO:   material cortado por tamanho\n'));
  }

  out.write('\n' + dim('-'.repeat(76)) + '\n');
  out.write(bold(`\nINVENTARIO  (${report.inventory.length})\n\n`));
  for (const o of report.inventory) {
    out.write(`  ${bold(o.subject)}\n`);
    // `evidence` e impresso PRIMEIRO, e nunca omitido: e a unica coisa que
    // permite ao leitor conferir se o item existe no material ou foi deduzido.
    // Escondida, uma invencao passa por observacao -- foi o que aconteceu na
    // primeira execucao desta lente, que inventariou como "decisao registrada"
    // cinco numeros que nao existem em arquivo algum do repositorio.
    const anchor = o.evidence.replace(/\s+/g, ' ').trim();
    out.write(
      `      ${anchor === '' ? red('SEM ANCORA') : dim('citado    ')}  ` +
        `${wrap(anchor === '' ? '(o modelo nao copiou trecho algum)' : anchor, 17)}\n`,
    );
    out.write(`      ${dim('e')}           ${wrap(o.what_exists, 17)}\n`);
    out.write(`      ${dim('serve para')}  ${wrap(o.purpose, 17)}\n`);
    for (const c of o.competing) {
      out.write(`      ${dim('disputa')}     ${wrap(c, 17)}\n`);
    }
    out.write('\n');
  }

  out.write(dim('-'.repeat(76)) + '\n');
  out.write(bold(`\nTENSOES  (${report.tensions.length})\n\n`));
  if (report.tensions.length === 0) {
    out.write(
      green('  Nenhuma tensao. ') +
        dim('Um dominio que cumpre seu proposito esta pronto.\n\n'),
    );
  }
  for (const [i, t] of report.tensions.entries()) {
    out.write(`${severityTag(t.severity)} ${bold(`${i + 1}. ${t.subject}`)}\n`);
    out.write(`      ${dim('observa')}    ${wrap(t.observation, 17)}\n`);
    out.write(`      ${dim('evidencia')}  ${wrap(t.evidence.replace(/\s+/g, ' '), 17)}\n`);
    out.write(`      ${dim('custa')}      ${wrap(t.why_it_hurts, 17)}\n`);
    for (const [j, option] of t.options.entries()) {
      out.write(`      ${dim(`opcao ${j + 1}`)}    ${wrap(option, 17)}\n`);
    }
    out.write('\n');
  }

  if (report.proposal.trim() !== '') {
    out.write(dim('-'.repeat(76)) + '\n');
    out.write(bold('\nALVO\n\n'));
    out.write('  ' + wrap(report.proposal, 2) + '\n\n');
  }

  if (report.sequence.length > 0) {
    out.write(dim('-'.repeat(76)) + '\n');
    out.write(bold('\nSEQUENCIA\n\n'));
    for (const p of report.sequence) {
      out.write(`  ${bold(String(p.order).padStart(2))}. ${wrap(p.action, 6)}\n`);
      if (p.touches.length > 0) {
        out.write(`      ${dim('toca')}       ${wrap(p.touches.join(', '), 17)}\n`);
      }
      out.write(`      ${dim('pronto se')}  ${wrap(p.done_when, 17)}\n\n`);
    }
  }

  out.write(dim('-'.repeat(76)) + '\n');
  const structural = report.tensions.filter((t) => t.severity === 'ESTRUTURAL').length;
  out.write('\n' + wrap(report.summary, 0) + '\n\n');
  out.write(
    dim(
      `${structural} estrutural(is), ` +
        `${report.tensions.filter((t) => t.severity === 'LOCAL').length} local(is), ` +
        `${report.tensions.filter((t) => t.severity === 'POLIMENTO').length} polimento.\n`,
    ),
  );
  out.write(
    dim('Conselho nao bloqueia nada. Uma rodada endereca so as ESTRUTURAL.\n\n'),
  );
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface Cli {
  lens: string;
  backend: 'agy' | 'api';
  backendExplicit: boolean;
  model?: string;
  dryRun: boolean;
  noAsk: boolean;
  timeout?: number;
  help: boolean;
  /** Tema das capturas, para a lente `tela`. */
  theme: 'claro' | 'escuro';
  /** Largura das capturas, em dp. */
  width: number;
}

const USAGE = `
Conselheiro do Equisim -- le o projeto por lente e propoe.

  npm run conselho -- --lente <id>

Lentes:
${SUGGESTED_ORDER.map((id) => {
  const l = LENSES[id];
  const nota = l.needsScreenshots ? dim('  (precisa das capturas -- fase 03)') : '';
  return `  ${id.padEnd(10)} ${l.title}${nota}`;
}).join('\n')}

Opcoes:
  --lente <id>      qual lente executar (obrigatorio)
  --tema <t>        capturas: claro (padrao) ou escuro   [lente tela]
  --largura <dp>    capturas: 320, 390 (padrao) ou 1024  [lente tela]
  --backend <b>     agy (padrao, assinatura) ou api (API key)
  --model <nome>    modelo especifico; sem isso, pergunta em terminal
  --timeout <s>     teto local, em segundos
  --dry-run         monta o payload e imprime, sem chamar o modelo
  --no-ask          nao pergunta o modelo; usa o padrao do backend
  --help

Este programa NUNCA bloqueia: sai com codigo 0 mesmo em falha.
`;

function parseArgs(argv: string[]): Cli {
  const cli: Cli = {
    lens: '',
    backend: 'agy',
    backendExplicit: false,
    dryRun: false,
    noAsk: false,
    help: false,
    // 390 dp e o padrao porque e onde a interface aperta -- foi la que o
    // cabecalho da tabela saiu como "PESO POTENCI..." na primeira captura.
    // Tela folgada esconde problema de hierarquia; tela apertada o expoe.
    theme: 'claro',
    width: 390,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i] ?? '';
    const next = (): string => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`A opcao ${arg} exige um valor.`);
      return v;
    };
    switch (arg) {
      case '--lente':
        cli.lens = next();
        break;
      case '--backend': {
        const v = next();
        if (v !== 'agy' && v !== 'api') {
          throw new Error(`Backend desconhecido: "${v}". Use agy ou api.`);
        }
        cli.backend = v;
        cli.backendExplicit = true;
        break;
      }
      case '--model':
        cli.model = next();
        break;
      case '--timeout':
        cli.timeout = Number(next()) * 1000;
        break;
      case '--tema': {
        const v = next();
        if (v !== 'claro' && v !== 'escuro') {
          throw new Error(`Tema desconhecido: "${v}". Use claro ou escuro.`);
        }
        cli.theme = v;
        break;
      }
      case '--largura':
        cli.width = Number(next());
        break;
      case '--dry-run':
        cli.dryRun = true;
        break;
      case '--no-ask':
        cli.noAsk = true;
        break;
      case '--help':
      case '-h':
        cli.help = true;
        break;
      default:
        // Um id solto tambem serve: `npm run conselho -- registro`.
        if (!arg.startsWith('-') && cli.lens === '') cli.lens = arg;
        else throw new Error(`Opcao desconhecida: ${arg}`);
    }
  }
  return cli;
}

/**
 * Saidas oferecidas quando a consulta estoura o teto.
 *
 * Sao as flags DESTE programa. O provider trazia as do auditor fixas, e o
 * conselheiro acabava recebendo `--base HEAD~1` e `--file` como conselho --
 * opcoes que a CLI dele nao tem.
 */
const TIMEOUT_OUTPUTS: readonly string[] = [
  'estreite o recorte:   --largura 390  (uma largura por vez)',
  'troque o tema:        --tema claro   (metade das imagens)',
  'aumente o teto:       --timeout 900',
];

/**
 * Teto de tempo do conselheiro, maior que o do auditor.
 *
 * O auditor usa 240s porque roda no `pre-push`, onde alguem espera com a
 * interface travada. Aqui ninguem espera: a consulta e sob demanda e fora de
 * hook. E a lente `tela` manda cinco imagens, que custam bem mais tempo que a
 * mesma pergunta em texto -- 240s a derrubava antes de responder.
 */
const ADVISOR_TIMEOUT_MS = 900_000;

function selectProvider(root: string, cli: Cli): QaProvider {
  if (cli.backend !== 'agy') {
    return new ApiProvider(
      root,
      undefined,
      cli.timeout ?? ADVISOR_TIMEOUT_MS,
      TIMEOUT_OUTPUTS,
      API_FLASH_CASCADE,
    );
  }
  if (isAgyAvailable()) return new AgyProvider(cli.timeout ?? ADVISOR_TIMEOUT_MS);

  if (cli.backendExplicit) {
    throw new Error(
      'O backend `agy` foi pedido, mas o CLI nao esta disponivel.\n' +
        '  Confirme com: agy --version',
    );
  }
  process.stderr.write(
    `${yellow('agy indisponivel')}; usando o backend api (API key).\n`,
  );
  return new ApiProvider(
    root,
    undefined,
    cli.timeout ?? ADVISOR_TIMEOUT_MS,
    TIMEOUT_OUTPUTS,
    API_FLASH_CASCADE,
  );
}

// ---------------------------------------------------------------------------

async function run(): Promise<void> {
  const cli = parseArgs(process.argv.slice(2));
  if (cli.help || cli.lens === '') {
    process.stdout.write(USAGE);
    return;
  }

  const root = repoRoot(process.cwd());
  const lens = resolveLens(cli.lens);

  // Capturas, quando a lente as exige. Feito ANTES de montar o material para
  // que a ausencia apareca como mensagem acionavel, e nao como uma consulta de
  // minutos sobre imagem nenhuma.
  const screenshots = lens.needsScreenshots ? selectScreenshots(root, cli) : [];
  if (lens.needsScreenshots && cli.backend !== 'api') {
    if (cli.backendExplicit) {
      throw new Error(
        `A lente "${lens.id}" precisa de imagem, e o backend "${cli.backend}" nao a transmite.\n` +
          '  Use: --backend api',
      );
    }
    // Sem pedido explicito, trocar em silencio seria pior que trocar avisando:
    // o cabecalho do relatorio diz qual backend rodou, e a cota da API e
    // escassa o suficiente para o usuario querer saber que a gastou.
    process.stderr.write(
      dim('  lente visual: usando o backend api (o agy nao transmite imagem)\n'),
    );
    cli.backend = 'api';
  }

  const target = collectLens(root, lens);
  const images = screenshots.length > 0 ? loadScreenshots(screenshots) : [];
  // A fronteira de reconstrucao vem do REGISTRO, nao de configuracao: e uma
  // decisao aceita com `postura: reconstrucao`. Sem isso nao haveria como
  // saber depois por que meio repositorio virou acionavel, nem quando aquilo
  // deveria ter fechado.
  const boundaries = openBoundaries(root);
  const system = buildAdvisorSystem(lens, boundaries);
  const instructions =
    buildAdvisorInstructions(target) +
    (images.length > 0 ? visualInstructions(images.map((i) => i.label)) : '');

  if (cli.dryRun) {
    process.stdout.write(bold('\n=== SYSTEM INSTRUCTION ===\n\n') + system + '\n');
    process.stdout.write(bold('\n=== INSTRUCOES ===\n\n') + instructions + '\n');
    process.stdout.write(
      bold('\n=== MATERIAL ===\n\n') +
        dim(
          `${target.files.length} bloco(s), ${target.payload.length} caracteres` +
            (target.truncated ? ' (CORTADO)' : '') +
            '\n',
        ),
    );
    for (const f of target.files) process.stdout.write(dim(`  ${f}\n`));
    for (const i of images) {
      process.stdout.write(dim(`  [imagem] ${i.label}  ${Math.round(i.bytes / 1024)} KB\n`));
    }
    return;
  }

  const provider = selectProvider(root, cli);
  provider.preflight();

  const model =
    provider.name === 'agy'
      ? await chooseModel(target, {
          interactive:
            process.stdin.isTTY === true &&
            process.stdout.isTTY === true &&
            !cli.noAsk,
          explicitModel: cli.model,
        })
      : cli.model;

  const request: ProviderRequest = {
    system,
    instructions,
    material: `--- INICIO DO MATERIAL ---\n${target.payload}\n--- FIM DO MATERIAL ---\n`,
    model,
    schema: ADVISOR_RESPONSE_SCHEMA,
    screenshots: images.map((i) => i.part),
  };

  process.stdout.write(
    dim(
      `\nConsultando (${target.payload.length} caracteres` +
        (images.length > 0 ? `, ${images.length} imagem(ns)` : '') +
        '). Pode levar minutos.\n',
    ),
  );

  const { report, result } = await consult(provider, request, lens.id);
  const raw = saveRaw(root, lens.id, result.text);
  renderReport(report, target, result.model, provider, result.usage);
  process.stdout.write(dim(`Resposta crua: ${raw}\n\n`));
}

/**
 * Grava a resposta crua antes de renderizar.
 *
 * Uma consulta custa minutos e cota, e o relatorio impresso e uma REDUCAO dela.
 * Sem o bruto no disco, conferir depois se um item tinha ancora exige rodar de
 * novo -- foi o que aconteceu na primeira execucao da lente `registro`, quando
 * a duvida sobre itens inventados nao pode ser resolvida porque so restava o
 * texto formatado.
 */
function saveRaw(root: string, lens: string, text: string): string {
  const dir = join(root, '.conselho');
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const filePath = join(dir, `${lens}-${stamp}.json`);
  writeFileSync(filePath, text, 'utf8');
  return filePath;
}

/**
 * Escolhe quais capturas enviar.
 *
 * NAO manda as trinta. O objeto desta lente e a RELACAO entre as telas -- se um
 * rotulo descreve o que abre, se a hierarquia e a mesma de tela para tela --, e
 * isso se ve comparando os cinco alvos lado a lado numa mesma largura e num
 * mesmo tema. Trinta imagens misturando larguras e temas gastariam cota para
 * dificultar exatamente a comparacao que interessa.
 *
 * Largura e tema viram parametro em vez de constante porque a pergunta muda com
 * eles: 390 mostra o aperto, 1024 mostra a distribuicao do espaco.
 */
function selectScreenshots(root: string, cli: Cli): string[] {
  const dir = join(root, 'docs', 'telas', cli.theme);
  if (!existsSync(dir)) {
    throw new Error(
      `Nao ha capturas em docs/telas/${cli.theme}/.\n` +
        '  Gere com: npm run ui:capturar\n' +
        '  Elas nao sao versionadas -- todo clone comeca sem elas.',
    );
  }
  const chosen = readdirSync(dir)
    .filter((f) => f.endsWith(`@${cli.width}.png`))
    .sort()
    .map((f) => join(dir, f));

  if (chosen.length === 0) {
    throw new Error(
      `Ha capturas em docs/telas/${cli.theme}/, mas nenhuma em ${cli.width}dp.\n` +
        `  Disponiveis: ${[...new Set(readdirSync(dir).map((f) => f.replace(/^.*@/, '').replace('.png', '')))].join(', ')}dp`,
    );
  }
  return chosen;
}

/** Quantas vezes insistir numa falha classificada como transitoria. */
const MAX_ATTEMPTS = 3;

/**
 * Executa com repeticao em falha transitoria.
 *
 * Existe pelo mesmo motivo que o `audit()` do auditor: o `agy` e um agente, e
 * as vezes erra o formato da propria chamada de ferramenta que embrulha a saida
 * estruturada. O provider ja classifica isso como transitorio -- ignorar a
 * classificacao e jogar fora uma consulta de minutos por um erro que a segunda
 * tentativa costuma nao cometer.
 */
async function consult(
  provider: QaProvider,
  request: ProviderRequest,
  lens: Parameters<typeof validateAdvisorReport>[1],
): Promise<{ report: AdvisorReport; result: Awaited<ReturnType<QaProvider['run']>> }> {
  let last: unknown;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const result = await provider.run(request);
      return {
        report: validateAdvisorReport(JSON.parse(result.text), lens),
        result,
      };
    } catch (error) {
      last = error;
      const transient = error instanceof ProviderError && error.transient;
      if (attempt < MAX_ATTEMPTS && transient) {
        const delayMs = 2 ** attempt * 1000;
        process.stderr.write(
          dim(`  tentativa ${attempt} falhou (transitorio); nova em ${delayMs}ms\n`),
        );
        await new Promise((r) => setTimeout(r, delayMs));
        continue;
      }
      break;
    }
  }
  throw last;
}

/**
 * O envelope que garante o codigo 0.
 *
 * Toda falha e reportada com detalhe no stderr e ENGOLIDA. Um conselho que
 * falha nao pode ser confundido com uma reprovacao, e nenhum fluxo de trabalho
 * deve parar porque a rede caiu no meio de uma consulta opcional.
 */
run()
  .catch((error: unknown) => {
    const detail = error instanceof Error ? error.message : String(error);
    process.stderr.write(`\n${red(bold('CONSULTA NAO CONCLUIDA'))}\n`);
    process.stderr.write(`  ${detail}\n`);
    if (error instanceof ProviderError && error.quota) {
      process.stderr.write(
        dim('  Cota esgotada. Diferente do auditor, aqui nao ha fila: o\n') +
          dim('  conselho e sob demanda, entao repetir amanha custa nada.\n'),
      );
    }
    process.stderr.write(dim('\n  Nada foi bloqueado. Este agente nunca reprova.\n\n'));
  })
  .finally(() => {
    process.exitCode = 0;
  });
