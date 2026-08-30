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
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { repoRoot } from './qa/collect.ts';
import { chooseModel } from './qa/choose.ts';
import { AgyProvider, isAgyAvailable } from './qa/providers/agy.ts';
import { ApiProvider } from './qa/providers/api.ts';
import {
  ProviderError,
  type ProviderRequest,
  type ProviderUsage,
  type QaProvider,
} from './qa/providers/types.ts';
import { collectLente, type AdvisorTarget } from './qa/advisor/collect.ts';
import { LENTES, ORDEM_SUGERIDA, resolverLente } from './qa/advisor/lentes.ts';
import {
  buildAdvisorInstructions,
  buildAdvisorSystem,
} from './qa/advisor/rules.ts';
import {
  ADVISOR_RESPONSE_SCHEMA,
  validateAdvisorReport,
  type AdvisorReport,
  type Severidade,
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

function gravidadeTag(s: Severidade): string {
  switch (s) {
    case 'ESTRUTURAL':
      return red(bold(' ESTRUTURAL '));
    case 'LOCAL':
      return yellow(bold('   LOCAL    '));
    default:
      return blue(bold(' POLIMENTO  '));
  }
}

/** Quebra texto em `largura` colunas, recuando as linhas seguintes. */
function wrap(text: string, indent: number, largura = 76): string {
  const limite = Math.max(24, largura - indent);
  const prefixo = ' '.repeat(indent);
  const linhas: string[] = [];
  let atual = '';
  for (const palavra of text.split(/\s+/).filter((p) => p !== '')) {
    if (atual === '') atual = palavra;
    else if (atual.length + 1 + palavra.length <= limite) atual += ' ' + palavra;
    else {
      linhas.push(atual);
      atual = palavra;
    }
  }
  if (atual !== '') linhas.push(atual);
  return linhas.join('\n' + prefixo);
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
    const ancora = o.evidence.replace(/\s+/g, ' ').trim();
    out.write(
      `      ${ancora === '' ? red('SEM ANCORA') : dim('citado    ')}  ` +
        `${wrap(ancora === '' ? '(o modelo nao copiou trecho algum)' : ancora, 17)}\n`,
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
    out.write(`${gravidadeTag(t.severity)} ${bold(`${i + 1}. ${t.subject}`)}\n`);
    out.write(`      ${dim('observa')}    ${wrap(t.observation, 17)}\n`);
    out.write(`      ${dim('evidencia')}  ${wrap(t.evidence.replace(/\s+/g, ' '), 17)}\n`);
    out.write(`      ${dim('custa')}      ${wrap(t.why_it_hurts, 17)}\n`);
    for (const [j, opcao] of t.options.entries()) {
      out.write(`      ${dim(`opcao ${j + 1}`)}    ${wrap(opcao, 17)}\n`);
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
  const estruturais = report.tensions.filter((t) => t.severity === 'ESTRUTURAL').length;
  out.write('\n' + wrap(report.summary, 0) + '\n\n');
  out.write(
    dim(
      `${estruturais} estrutural(is), ` +
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
  lente: string;
  backend: 'agy' | 'api';
  backendExplicit: boolean;
  model?: string;
  dryRun: boolean;
  noAsk: boolean;
  timeout?: number;
  help: boolean;
}

const USO = `
Conselheiro do Equisim -- le o projeto por lente e propoe.

  npm run conselho -- --lente <id>

Lentes:
${ORDEM_SUGERIDA.map((id) => {
  const l = LENTES[id];
  const nota = l.precisaDeCapturas ? dim('  (precisa das capturas -- fase 03)') : '';
  return `  ${id.padEnd(10)} ${l.titulo}${nota}`;
}).join('\n')}

Opcoes:
  --lente <id>      qual lente executar (obrigatorio)
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
    lente: '',
    backend: 'agy',
    backendExplicit: false,
    dryRun: false,
    noAsk: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i] ?? '';
    const proximo = (): string => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`A opcao ${arg} exige um valor.`);
      return v;
    };
    switch (arg) {
      case '--lente':
        cli.lente = proximo();
        break;
      case '--backend': {
        const v = proximo();
        if (v !== 'agy' && v !== 'api') {
          throw new Error(`Backend desconhecido: "${v}". Use agy ou api.`);
        }
        cli.backend = v;
        cli.backendExplicit = true;
        break;
      }
      case '--model':
        cli.model = proximo();
        break;
      case '--timeout':
        cli.timeout = Number(proximo()) * 1000;
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
        if (!arg.startsWith('-') && cli.lente === '') cli.lente = arg;
        else throw new Error(`Opcao desconhecida: ${arg}`);
    }
  }
  return cli;
}

function selectProvider(root: string, cli: Cli): QaProvider {
  if (cli.backend !== 'agy') return new ApiProvider(root, undefined, cli.timeout);
  if (isAgyAvailable()) return new AgyProvider(cli.timeout);

  if (cli.backendExplicit) {
    throw new Error(
      'O backend `agy` foi pedido, mas o CLI nao esta disponivel.\n' +
        '  Confirme com: agy --version',
    );
  }
  process.stderr.write(
    `${yellow('agy indisponivel')}; usando o backend api (API key).\n`,
  );
  return new ApiProvider(root, undefined, cli.timeout);
}

// ---------------------------------------------------------------------------

async function run(): Promise<void> {
  const cli = parseArgs(process.argv.slice(2));
  if (cli.help || cli.lente === '') {
    process.stdout.write(USO);
    return;
  }

  const root = repoRoot(process.cwd());
  const lente = resolverLente(cli.lente);

  if (lente.precisaDeCapturas) {
    process.stdout.write(
      `\n${yellow('Lente indisponivel')}  "${lente.id}" depende de capturas de tela.\n` +
        dim('  Elas sao geradas na fase 03 (npm run ui:capturar), e so trafegam\n') +
        dim('  pelo backend api -- o agy nao transmite imagem.\n\n'),
    );
    return;
  }

  const target = collectLente(root, lente);
  const system = buildAdvisorSystem(lente);
  const instructions = buildAdvisorInstructions(target);

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
  };

  process.stdout.write(
    dim(`\nConsultando (${target.payload.length} caracteres). Pode levar minutos.\n`),
  );

  const { report, result } = await consultar(provider, request, lente.id);
  const bruto = salvarBruto(root, lente.id, result.text);
  renderReport(report, target, result.model, provider, result.usage);
  process.stdout.write(dim(`Resposta crua: ${bruto}\n\n`));
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
function salvarBruto(root: string, lente: string, texto: string): string {
  const dir = join(root, '.conselho');
  mkdirSync(dir, { recursive: true });
  const carimbo = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const caminho = join(dir, `${lente}-${carimbo}.json`);
  writeFileSync(caminho, texto, 'utf8');
  return caminho;
}

/** Quantas vezes insistir numa falha classificada como transitoria. */
const MAX_TENTATIVAS = 3;

/**
 * Executa com repeticao em falha transitoria.
 *
 * Existe pelo mesmo motivo que o `audit()` do auditor: o `agy` e um agente, e
 * as vezes erra o formato da propria chamada de ferramenta que embrulha a saida
 * estruturada. O provider ja classifica isso como transitorio -- ignorar a
 * classificacao e jogar fora uma consulta de minutos por um erro que a segunda
 * tentativa costuma nao cometer.
 */
async function consultar(
  provider: QaProvider,
  request: ProviderRequest,
  lente: Parameters<typeof validateAdvisorReport>[1],
): Promise<{ report: AdvisorReport; result: Awaited<ReturnType<QaProvider['run']>> }> {
  let ultimo: unknown;

  for (let tentativa = 1; tentativa <= MAX_TENTATIVAS; tentativa++) {
    try {
      const result = await provider.run(request);
      return {
        report: validateAdvisorReport(JSON.parse(result.text), lente),
        result,
      };
    } catch (error) {
      ultimo = error;
      const transitorio = error instanceof ProviderError && error.transient;
      if (tentativa < MAX_TENTATIVAS && transitorio) {
        const espera = 2 ** tentativa * 1000;
        process.stderr.write(
          dim(`  tentativa ${tentativa} falhou (transitorio); nova em ${espera}ms\n`),
        );
        await new Promise((r) => setTimeout(r, espera));
        continue;
      }
      break;
    }
  }
  throw ultimo;
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
    const detalhe = error instanceof Error ? error.message : String(error);
    process.stderr.write(`\n${red(bold('CONSULTA NAO CONCLUIDA'))}\n`);
    process.stderr.write(`  ${detalhe}\n`);
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
