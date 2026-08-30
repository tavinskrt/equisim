/**
 * Backend `agy` -- CLI do Antigravity, autenticado pela assinatura Google AI Pro.
 *
 * Por que ele existe: a API `generativelanguage.googleapis.com` cobra cota por
 * chave, e no tier gratuito da uma cota de 20 requisicoes/dia e ZERO para a
 * familia Pro. O `agy` fala com a mesma familia de modelos pela ASSINATURA, sem
 * API key -- inclusive `gemini-3.1-pro-*`, que na API exigiria billing.
 *
 * Fatos verificados na v1.1.22, todos executando o binario:
 *
 *   - `agy` esta no PATH de qualquer shell, nao so do terminal da IDE. Isso e o
 *     que o torna utilizavel em hook de git e em CI -- diferente da `agentapi`,
 *     que exigia variaveis que a IDE nunca injeta.
 *   - `agy -p` NAO le a entrada padrao. Verificado: responde como se nada
 *     tivesse chegado. Por isso o material vai por `--input-format stream-json`.
 *   - O formato NDJSON de entrada e:
 *         {"event":"user","message":{"role":"user","content":[{"type":"text",...}]}}
 *     Descoberto pela mensagem de erro do proprio binario, que rejeita qualquer
 *     outra forma com 'stream input message is missing the "event" field'.
 *   - `-p` consome o argumento seguinte. Quando combinado com outras flags e
 *     obrigatorio escrever `-p=''`, senao o CLI toma a flag como prompt.
 *   - `--json-schema` aceita caminho de arquivo e devolve `structured_output`
 *     ja parseado no evento `result`. Nao ha heuristica de extracao aqui.
 *
 * LIMITE CONHECIDO: `agy` e um agente, nao um endpoint. Ele tem ferramentas de
 * escrita (`replace_file_content`, `sed_file`, `run_command`). Um auditor nao
 * pode escrever no repositorio que julga, entao a contencao e requisito -- ver
 * `CONTAINMENT` abaixo.
 */
import { execFileSync, spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { QA_RESPONSE_SCHEMA, toJsonSchema } from '../schema.ts';
import {
  ProviderError,
  type ProviderRequest,
  type ProviderResult,
  type ProviderUsage,
  type QaProvider,
} from './types.ts';

/**
 * Modelo padrao. `-high` porque o gargalo desta cadeia nunca foi velocidade:
 * medimos 13s com `gemini-3.1-pro-low` contra 32-115s pela API. Sobra orcamento
 * de tempo para comprar profundidade.
 */
export const AGY_DEFAULT_MODEL = 'gemini-3.1-pro-high';

/** Teto local. O `--print-timeout` do proprio CLI e de 5 min por padrao. */
const TIMEOUT_MS = 600_000;

/**
 * Contencao. Tres camadas, porque nenhuma isolada e suficiente:
 *
 *   1. instrucao explicita no prompt de nao usar ferramenta alguma;
 *   2. AUSENCIA de `--dangerously-skip-permissions` -- sem TTY, um pedido de
 *      permissao nao tem como ser aprovado;
 *   3. `--sandbox`, que restringe execucao de terminal.
 *
 * A Fase B do plano prova isso empiricamente comparando `git status` antes e
 * depois. Ate la, trate como intencao, nao como garantia.
 */
const CONTAINMENT = [
  'REGRAS DE EXECUCAO, absolutas:',
  '- NAO use ferramenta alguma. Nao leia arquivos, nao rode comandos, nao',
  '  edite nada, nao pesquise na web. Todo o material de que voce precisa ja',
  '  esta neste prompt.',
  '- NAO escreva nem modifique arquivo algum, em nenhuma circunstancia.',
  '- Responda em UM turno, apenas com o objeto JSON do schema fornecido.',
].join('\n');

/**
 * O `agy` esta instalado e executavel nesta maquina?
 *
 * Executa em vez de so procurar no PATH: um arquivo presente porem quebrado
 * (instalacao parcial, permissao, arquitetura errada) passaria por um teste de
 * existencia e falharia depois, no meio da auditoria, com mensagem cifrada.
 *
 * O custo e ~200ms, irrelevante ao lado de uma auditoria de minutos, e paga por
 * si ao permitir que um projeto sem Antigravity caia no backend `api` em vez de
 * quebrar.
 */
export function isAgyAvailable(): boolean {
  try {
    execFileSync(agyExecutable(), ['--version'], {
      timeout: 10_000,
      stdio: 'ignore',
      windowsHide: true,
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Backend pela CLI do Antigravity, autenticado pela assinatura Google AI Pro.
 *
 * E o padrao do projeto: alcanca a familia Pro sem API key nem billing, e a
 * cota e a da assinatura. Em troca abre mao de parte do determinismo -- o
 * schema nao e forcado pelo servidor, entao o JSON chega as vezes sujo e e
 * saneado antes da validacao.
 *
 * Fala com o processo por NDJSON no stdout, o que permite medir consumo de
 * tokens: sendo cota de assinatura, nao ha painel de billing a consultar.
 */
export class AgyProvider implements QaProvider {
  readonly name = 'agy' as const;

  private readonly timeoutMs: number;

  constructor(timeoutMs = TIMEOUT_MS) {
    this.timeoutMs = timeoutMs;
  }

  describeAuth(): string {
    return 'assinatura Google AI Pro (agy CLI, sem API key)';
  }

  preflight(): void {
    // A verificacao real e a falha do spawn: checar `command -v` aqui duplicaria
    // logica de plataforma sem ganho. O erro do spawn ja e acionavel.
  }

  async run(request: ProviderRequest): Promise<ProviderResult> {
    if (request.screenshots && request.screenshots.length > 0) {
      throw new ProviderError(
        'O backend `agy` ainda nao transmite imagem. Para auditoria visual:\n' +
          '    npm run qa:visual -- <img> --backend api',
      );
    }

    const model = request.model ?? AGY_DEFAULT_MODEL;
    const dir = mkdtempSync(join(tmpdir(), 'equisim-agy-'));
    const schemaPath = join(dir, 'schema.json');
    // `--json-schema` exige JSON Schema padrao, nao o formato do SDK: a
    // conversao trata o enum `Type`, que serializa em MAIUSCULAS.
    const schema = toJsonSchema(request.schema ?? QA_RESPONSE_SCHEMA);
    writeFileSync(schemaPath, JSON.stringify(schema, null, 2), 'utf8');

    // `agy` nao tem canal separado de instrucao de sistema: tudo vai numa unica
    // mensagem de usuario.
    const prompt = [
      request.system,
      '',
      CONTAINMENT,
      '',
      request.instructions,
      '',
      request.material,
    ].join('\n');

    const { text, usage } = await this.invoke(prompt, schemaPath, model);
    return { text, model: `agy:${model}`, usage };
  }

  private invoke(
    prompt: string,
    schemaPath: string,
    model: string,
  ): Promise<AgyOutcome> {
    return new Promise<AgyOutcome>((resolve, reject) => {
      const args = [
        '--input-format',
        'stream-json',
        '--output-format',
        'stream-json',
        '--json-schema',
        schemaPath,
        '--model',
        model,
        '--sandbox',
        // Sem isto vale o padrao da CLI, de 5 minutos -- e o teto local abaixo
        // nunca chega a disparar, porque o processo ja foi morto. Passa a ser o
        // MESMO valor, para que exista um teto so e ele seja o nosso. Sem esse
        // alinhamento, um alvo grande em `-high` morre num limite que ninguem
        // escolheu, com mensagem de timeout generica.
        '--print-timeout',
        `${Math.round(this.timeoutMs / 1000)}s`,
        // Precisa ser `-p=` colado: solto, o CLI toma a proxima flag como prompt.
        '-p=',
      ];

      const child = spawn(agyExecutable(), args, {
        stdio: ['pipe', 'pipe', 'pipe'],
        windowsHide: true,
      });

      let stdout = '';
      let stderr = '';
      let settled = false;

      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        child.kill();
        reject(
          new ProviderError(
            `O agy nao respondeu em ${this.timeoutMs / 1000}s.`,
            true,
          ),
        );
      }, this.timeoutMs);

      child.stdout.on('data', (c: Buffer) => {
        stdout += c.toString('utf8');
      });
      child.stderr.on('data', (c: Buffer) => {
        stderr += c.toString('utf8');
      });

      child.on('error', (error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        reject(
          new ProviderError(
            `Falha ao executar o agy: ${error.message}\n` +
              'Confirme a instalacao com: agy --version',
          ),
        );
      });

      child.on('close', () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        try {
          resolve(extractResult(stdout, stderr));
        } catch (error) {
          reject(error);
        }
      });

      child.stdin.on('error', () => {
        // EPIPE se o CLI fecha stdin antes de consumirmos tudo; `close` trata.
      });
      child.stdin.end(
        `${JSON.stringify({
          event: 'user',
          message: { role: 'user', content: [{ type: 'text', text: prompt }] },
        })}\n`,
        'utf8',
      );
    });
  }
}

/** Padroes que indicam cota esgotada, e nao defeito do codigo nem falha de rede. */
const QUOTA_PATTERNS =
  /quota|rate.?limit|exhaust|too many requests|\b429\b|limit reached|usage limit/i;

/**
 * Classifica a mensagem de erro como cota esgotada.
 *
 * @param message Texto do erro, como o CLI o reportou.
 * @returns `true` quando repetir agora e inutil e o payload deve ir para a fila
 *   de pendencias.
 */
export function isQuotaError(message: string): boolean {
  return QUOTA_PATTERNS.test(message);
}

/**
 * Falhas internas do agente, recuperaveis por nova tentativa.
 *
 * Medido na Fase B: 1 em 3 execucoes identicas falhou com "improperly formatted
 * function call". E o modelo errando a sintaxe da propria chamada de ferramenta,
 * nao defeito do codigo auditado nem indisponibilidade. O proprio CLI anuncia
 * "Retries remaining", ou seja, ele tambem considera recuperavel -- mas quando
 * esgota as dele, a falha sobe para ca e precisa ser tentada de novo.
 */
const RETRYABLE_PATTERNS =
  /improperly formatted|malformed|function call|internal error|unavailable|timeout|temporar/i;

/**
 * Classifica a mensagem de erro como recuperavel por nova tentativa.
 *
 * @param message Texto do erro, como o CLI o reportou.
 * @returns `true` quando vale repetir imediatamente.
 */
export function isRetryable(message: string): boolean {
  return RETRYABLE_PATTERNS.test(message);
}

/**
 * No Windows o `spawn` sem shell nao aplica PATHEXT, entao `agy` sozinho nao
 * resolve. Nomear o `.exe` permite dispensar `shell: true`, que concatenaria os
 * argumentos sem escapar.
 */
function agyExecutable(): string {
  if (process.env.AGY_PATH) return process.env.AGY_PATH;
  return process.platform === 'win32' ? 'agy.exe' : 'agy';
}

/** O que a leitura do fluxo NDJSON extraiu de uma execucao do `agy`. */
export interface AgyOutcome {
  /** Relatorio como texto JSON, ainda nao validado. */
  text: string;
  /** Consumo de tokens, quando o fluxo o reportou. */
  usage?: ProviderUsage;
}

/**
 * Le o fluxo NDJSON e devolve o relatorio como texto JSON, com o consumo.
 *
 * O evento `result` traz `structured_output` ja parseado quando `--json-schema`
 * foi aceito. Reserializamos para manter o contrato do `ProviderResult`, que e
 * texto -- o custo e irrelevante e evita um caminho especial no runner.
 */
export function extractResult(stdout: string, stderr = ''): AgyOutcome {
  let last: Record<string, unknown> | undefined;

  for (const line of stdout.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '') continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      continue; // Linha de log solta; o fluxo continua.
    }
    const event = parsed as Record<string, unknown>;
    if (event.event === 'result') {
      last = event.result as Record<string, unknown>;
    }
  }

  if (!last) {
    throw new ProviderError(
      'O agy nao emitiu evento `result`.\n' +
        `stderr: ${stderr.trim().slice(0, 500) || '(vazio)'}`,
      true,
    );
  }

  if (last.status !== 'SUCCESS') {
    const detail = String(last.error ?? last.status ?? 'erro desconhecido');
    if (isQuotaError(detail)) {
      throw new ProviderError(
        'Cota da assinatura esgotada no agy.\n' +
          '  Isso NAO e defeito do codigo. O trabalho segue; a auditoria fica\n' +
          '  pendente e sera refeita quando a cota voltar.\n\n' +
          detail,
        true,
        true,
      );
    }
    throw new ProviderError(`O agy falhou: ${detail}`, isRetryable(detail));
  }

  const usage = readUsage(last.usage);

  const structured = last.structured_output;
  if (structured !== undefined && structured !== null) {
    return { text: JSON.stringify(structured), usage };
  }

  // Sem `structured_output`, o schema nao foi aplicado. Cair para o texto e
  // deixar o `validateReport` julgar e melhor que falhar aqui.
  const response = last.response;
  if (typeof response === 'string' && response.trim() !== '') {
    return { text: response, usage };
  }

  throw new ProviderError(
    'O agy respondeu SUCCESS sem `structured_output` nem `response`.',
  );
}

/** O `agy` reporta em snake_case; o contrato do runner e camelCase. */
function readUsage(raw: unknown): ProviderUsage | undefined {
  if (typeof raw !== 'object' || raw === null) return undefined;
  const u = raw as Record<string, unknown>;
  const n = (v: unknown): number => (Number.isFinite(Number(v)) ? Number(v) : 0);
  return {
    inputTokens: n(u.input_tokens),
    outputTokens: n(u.output_tokens),
    thinkingTokens: n(u.thinking_tokens),
    totalTokens: n(u.total_tokens),
  };
}
