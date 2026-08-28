/**
 * Backend Antigravity (auditoria profunda sob demanda).
 *
 * Por que existe: em agosto de 2026 o Google encerrou o Gemini Code Assist for
 * individuals no Gemini CLI -- a tentativa de login responde "This client is no
 * longer supported [...] please migrate to the Antigravity suite of products".
 * Com isso, a UNICA forma de usar a assinatura Google AI Pro de forma
 * programatica nesta maquina passou a ser a `agentapi` do Antigravity.
 *
 * LIMITACAO ESTRUTURAL: a `agentapi` e um cliente de um language server em
 * execucao. Ela exige a variavel ANTIGRAVITY_LS_ADDRESS, que a IDE injeta
 * apenas nos terminais que ELA abre. Fora da IDE responde:
 *
 *     { "error": "ANTIGRAVITY_LS_ADDRESS is not set" }
 *
 * Consequencia pratica: este backend NAO serve para o hook de pre-commit
 * (GitHub Desktop nao roda dentro da IDE). Ele e para auditoria profunda
 * manual, rodada do terminal integrado do Antigravity, onde o raciocinio do
 * modelo Pro compensa o tempo. O gate rapido usa o backend `api`.
 *
 * AVISO: `agentapi` e IPC privado e nao documentado -- tres comandos, sem
 * contrato de estabilidade. Um update do Antigravity pode muda-la sem aviso.
 * Por isso ela nunca sustenta o gate: apenas a auditoria opcional.
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  ProviderError,
  type ProviderRequest,
  type ProviderResult,
  type QaProvider,
} from './types.ts';

/** Modelos aceitos pela agentapi (`--model=<flash_lite|flash|pro>`). */
export type AntigravityModel = 'flash_lite' | 'flash' | 'pro';
export const ANTIGRAVITY_DEFAULT_MODEL: AntigravityModel = 'pro';

/** Auditoria profunda e lenta por natureza; o teto e generoso de proposito. */
const TIMEOUT_MS = 900_000;

/** Locais conhecidos do language server, em ordem de preferencia. */
function candidateBinaries(): string[] {
  const local = process.env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local');
  return [
    process.env.ANTIGRAVITY_LS_PATH ?? '',
    join(
      local,
      'Programs',
      'Antigravity IDE',
      'resources',
      'app',
      'extensions',
      'antigravity',
      'bin',
      'language_server_windows_x64.exe',
    ),
    join(
      local,
      'Programs',
      'antigravity',
      'resources',
      'bin',
      'language_server.exe',
    ),
  ].filter((p) => p !== '');
}

function findBinary(): string | undefined {
  return candidateBinaries().find((p) => existsSync(p));
}

export class AntigravityProvider implements QaProvider {
  readonly name = 'antigravity' as const;

  private binary?: string;

  describeAuth(): string {
    return 'conta Google via Antigravity (plano AI Pro, sem API key)';
  }

  preflight(): void {
    this.binary = findBinary();
    if (!this.binary) {
      throw new ProviderError(
        'Nao encontrei o language server do Antigravity.\n' +
          '  Procurei em:\n' +
          candidateBinaries()
            .map((p) => `    ${p}`)
            .join('\n') +
          '\n\n  Se a instalacao estiver em outro lugar, aponte com:\n' +
          '      $env:ANTIGRAVITY_LS_PATH = "C:\\caminho\\language_server.exe"',
      );
    }

    if (!process.env.ANTIGRAVITY_LS_ADDRESS) {
      throw new ProviderError(
        'ANTIGRAVITY_LS_ADDRESS nao esta definida.\n\n' +
          '  A agentapi e um cliente do language server do Antigravity, e essa\n' +
          '  variavel so existe nos terminais abertos pela PROPRIA IDE.\n\n' +
          '  Abra o terminal integrado do Antigravity (nao o PowerShell comum,\n' +
          '  nao o GitHub Desktop) e rode a auditoria de la.\n\n' +
          '  Para o gate rapido, que roda em qualquer terminal, use:\n' +
          '      npx tsx scripts/gemini-qa.ts --diff --backend api',
      );
    }
  }

  async run(request: ProviderRequest): Promise<ProviderResult> {
    if (!this.binary) this.preflight();
    const model = normalizeModel(request.model);

    if (request.screenshots && request.screenshots.length > 0) {
      throw new ProviderError(
        'A agentapi do Antigravity so aceita prompt de texto -- nao ha canal\n' +
          'para anexar imagem. Auditoria visual exige o backend multimodal:\n' +
          '    npx tsx scripts/gemini-qa.ts --screenshot <img> --backend api',
      );
    }

    // A agentapi recebe o prompt como ARGUMENTO de linha de comando, e o
    // Windows limita isso a ~32 KB -- um diff deste repositorio passa de 100 KB.
    // Por isso o rulebook e o material vao para arquivos temporarios e o prompt
    // carrega apenas os caminhos. O agente do Antigravity tem ferramenta de
    // leitura de arquivo, entao essa indirecao e natural para ele.
    const dir = mkdtempSync(join(tmpdir(), 'equisim-qa-'));
    const rulebookPath = join(dir, 'rulebook.md');
    const materialPath = join(dir, 'material.txt');
    writeFileSync(rulebookPath, request.system, 'utf8');
    writeFileSync(materialPath, request.material, 'utf8');

    const prompt = [
      'Voce vai executar uma auditoria de codigo. Nao edite nenhum arquivo.',
      '',
      `1. Leia integralmente o rulebook em: ${rulebookPath}`,
      `2. Leia integralmente o material auditado em: ${materialPath}`,
      '3. Siga o rulebook a risca, inclusive a calibragem de severidade.',
      '',
      request.instructions,
      '',
      'Sua resposta final deve ser APENAS o objeto JSON especificado no',
      'rulebook. Sem markdown, sem cerca de codigo, sem comentario antes ou',
      'depois. Se voce escrever qualquer texto fora do JSON, a auditoria falha.',
    ].join('\n');

    const raw = await this.invoke(prompt, model);
    return { text: extractJson(raw), model: `antigravity:${model}` };
  }

  /**
   * Reenvia apontando o erro do parser. Repetir o prompt original sem citar o
   * problema tende a reproduzir exatamente a mesma saida invalida.
   */
  async repair(
    request: ProviderRequest,
    badOutput: string,
    parseError: string,
  ): Promise<ProviderResult> {
    if (!this.binary) this.preflight();
    const model = normalizeModel(request.model);

    const prompt = [
      'Sua resposta anterior nao pode ser lida como JSON.',
      `Erro do parser: ${parseError}`,
      '',
      'Responda AGORA apenas com o objeto JSON do relatorio de auditoria,',
      'comecando em "{" e terminando em "}". Sem cerca de codigo markdown,',
      'sem texto antes ou depois.',
      '',
      'Trecho da resposta invalida, para voce nao repetir o mesmo formato:',
      badOutput.slice(0, 400),
    ].join('\n');

    const raw = await this.invoke(prompt, model);
    return { text: extractJson(raw), model: `antigravity:${model}` };
  }

  private invoke(prompt: string, model: AntigravityModel): Promise<string> {
    return new Promise((resolve, reject) => {
      const args = [
        'agentapi',
        'new-conversation',
        `--model=${model}`,
        '--title=equisim-qa',
        prompt,
      ];

      const child = spawn(this.binary!, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
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
            `A agentapi nao respondeu em ${TIMEOUT_MS / 1000}s.`,
            true,
          ),
        );
      }, TIMEOUT_MS);

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
        reject(new ProviderError(`Falha ao executar a agentapi: ${error.message}`));
      });

      child.on('close', (code) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);

        // A agentapi e nao documentada: quando a saida nao for o que
        // esperamos, o diagnostico depende de ver o texto cru.
        if (process.env.QA_DEBUG_RAW) {
          process.stderr.write(
            `\n[agentapi raw] exit=${code}\n--- stdout ---\n${stdout}\n` +
              `--- stderr ---\n${stderr}\n`,
          );
        }

        if (code !== 0) {
          const detail = (stderr.trim() || stdout.trim()).slice(0, 2000);
          reject(
            new ProviderError(
              `A agentapi saiu com codigo ${code}.\n${detail}\n\n` +
                'Rode de novo com QA_DEBUG_RAW=1 para ver a saida completa.',
              /429|503|rate limit|quota|overload/i.test(detail),
            ),
          );
          return;
        }
        resolve(stdout);
      });
    });
  }
}

function normalizeModel(model?: string): AntigravityModel {
  if (!model) return ANTIGRAVITY_DEFAULT_MODEL;
  const normalized = model.toLowerCase();
  if (normalized === 'pro' || normalized === 'flash' || normalized === 'flash_lite') {
    return normalized;
  }
  throw new ProviderError(
    `O backend antigravity aceita apenas --model pro | flash | flash_lite ` +
      `(recebido: "${model}").\n` +
      'Nomes completos como gemini-3.5-flash valem no backend api.',
  );
}

/**
 * Extrai o JSON do relatorio de dentro da saida da agentapi.
 *
 * Podem aparecer duas camadas de embrulho: o envelope da propria agentapi e
 * cerca de markdown em volta do JSON do modelo.
 */
export function extractJson(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed === '') {
    throw new ProviderError('A agentapi retornou saida vazia.');
  }

  let candidate = trimmed;
  try {
    const envelope = JSON.parse(trimmed) as Record<string, unknown>;
    if (envelope && typeof envelope === 'object') {
      if (Array.isArray(envelope.findings)) return trimmed;
      if (typeof envelope.error === 'string') {
        throw new ProviderError(`A agentapi retornou erro: ${envelope.error}`);
      }
      const inner =
        envelope.response ?? envelope.output ?? envelope.text ?? envelope.content;
      if (typeof inner === 'string') candidate = inner.trim();
    }
  } catch (error) {
    if (error instanceof ProviderError) throw error;
    // Nao era JSON no topo: o texto do modelo veio cru.
  }

  const fenced = /```(?:json)?\s*([\s\S]*?)```/.exec(candidate);
  if (fenced?.[1]) candidate = fenced[1].trim();

  if (!candidate.startsWith('{')) {
    const start = candidate.indexOf('{');
    const end = candidate.lastIndexOf('}');
    if (start >= 0 && end > start) candidate = candidate.slice(start, end + 1);
  }
  return candidate;
}
