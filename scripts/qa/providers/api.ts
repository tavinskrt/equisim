/**
 * Backend de API key (`generativelanguage.googleapis.com`).
 *
 * E o backend PADRAO e o unico que sustenta o gate de commit: da Structured
 * Output com schema FORCADO pelo servidor, `temperature: 0` e roda em qualquer
 * terminal -- incluindo o hook disparado pelo GitHub Desktop, que nao roda
 * dentro de IDE nenhuma.
 *
 * Restricao verificada contra a API real: a familia Pro tem cota ZERO no tier
 * gratuito (resposta 429 com `limit: 0`), entao sem billing so os modelos
 * Flash rodam por aqui.
 */
import { GoogleGenAI } from '@google/genai';

import { resolveApiKey, type ApiKeyResolution } from '../env.ts';
import { QA_RESPONSE_SCHEMA } from '../schema.ts';
import {
  ProviderError,
  type ProviderRequest,
  type ProviderResult,
  type QaProvider,
} from './types.ts';

/** Flash roda no tier gratuito; Pro exige billing. Ver comentario do modulo. */
export const API_DEFAULT_MODEL = 'gemini-3.5-flash';
export const API_PRO_MODEL = 'gemini-3.1-pro-preview';

const TEMPERATURE = 0.0;

/**
 * Orcamento de raciocinio interno, em tokens.
 *
 * MEDIDO neste repositorio, no mesmo arquivo com 4 defeitos plantados:
 *
 *     sem teto (-1)   ~75-115s   4 FAIL  <- deteccao correta
 *     teto 2048        ~44s      2 FAIL  <- rebaixou 2 defeitos para WARN
 *     teto 0           ~29s      3 FAIL  <- rebaixou 1 defeito para WARN
 *
 * O padrao fica SEM teto. Cortar o raciocinio corta deteccao: os defeitos nao
 * somem do relatorio, eles descem para WARN -- e WARN nao bloqueia commit. Um
 * gate mais rapido que deixa passar erro de dinheiro nao e um gate.
 *
 * A latencia e problema do DESENHO DO HOOK, nao do orcamento de raciocinio.
 * Ver a discussao de estrategia de hook na Fase 4.
 *
 * 0 desliga; -1 e automatico (sem teto). Sobreponha com --thinking.
 */
const DEFAULT_THINKING_BUDGET = -1;

/**
 * Teto de tempo por chamada.
 *
 * MEDIDO: um diff de 3 KB responde em ~32s; um de 102 KB passou de 10 minutos
 * sem retornar. Sem teto, o hook de pre-push herda esse comportamento -- e um
 * push disparado pelo GitHub Desktop ficaria com a interface travada, sem
 * cancelamento e sem explicacao.
 *
 * O teto nao acelera nada: ele transforma "travou para sempre" em "falhou com
 * instrucao de como reduzir o escopo".
 */
const DEFAULT_TIMEOUT_MS = 240_000;

export class ApiProvider implements QaProvider {
  readonly name = 'api' as const;

  private readonly repoRoot: string;
  private readonly thinkingBudget: number;
  private readonly timeoutMs: number;
  private key?: ApiKeyResolution;

  constructor(
    repoRoot: string,
    thinkingBudget = DEFAULT_THINKING_BUDGET,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  ) {
    this.repoRoot = repoRoot;
    this.thinkingBudget = thinkingBudget;
    this.timeoutMs = timeoutMs;
  }

  describeAuth(): string {
    return `API key (${this.key?.source ?? 'nao resolvida'})`;
  }

  preflight(): void {
    this.key = resolveApiKey(this.repoRoot);
    if (this.key.warning) {
      process.stderr.write(`\nAVISO ${this.key.warning}\n`);
    }
  }

  async run(request: ProviderRequest): Promise<ProviderResult> {
    if (!this.key) this.preflight();
    const model = request.model ?? API_DEFAULT_MODEL;
    const ai = new GoogleGenAI({ apiKey: this.key!.apiKey });

    // O controller vive FORA do try porque o SDK lanca "This operation was
    // aborted" de dentro do await -- o fluxo desvia para o catch antes de
    // qualquer checagem posterior. Sem o escopo externo, a mensagem util seria
    // substituida pelo texto cru do SDK.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      // Quando ha capturas de tela, o conteudo vira multipart: o texto primeiro,
      // as imagens depois. A ordem importa -- o modelo le as instrucoes antes de
      // olhar a imagem, entao ja sabe o que procurar nela.
      const parts = [
        { text: `${request.instructions}\n\n${request.material}` },
        ...(request.screenshots ?? []),
      ];

      const response = await ai.models.generateContent({
        model,
        contents: [{ role: 'user', parts }],
        config: {
          systemInstruction: request.system,
          temperature: TEMPERATURE,
          responseMimeType: 'application/json',
          responseSchema: QA_RESPONSE_SCHEMA,
          thinkingConfig: { thinkingBudget: this.thinkingBudget },
          abortSignal: controller.signal,
        },
      });

      const text = response.text;
      if (!text) {
        throw new ProviderError(
          'A API retornou resposta vazia. Causa provavel: filtro de seguranca ' +
            'ou estouro do limite de tokens de saida.',
        );
      }
      return { text, model };
    } catch (error) {
      // O aborto e nosso, nao da API: traduzimos para a instrucao de escopo.
      if (controller.signal.aborted) {
        throw new ProviderError(timeoutMessage(this.timeoutMs, request));
      }
      if (error instanceof ProviderError) throw error;
      const message = error instanceof Error ? error.message : String(error);
      throw new ProviderError(
        explainApiError(error, model),
        isTransient(error),
        // 429 por cota diaria ou por indisponibilidade do modelo: em ambos os
        // casos repetir agora nao resolve, e a auditoria deve ficar pendente.
        /\b429\b|RESOURCE_EXHAUSTED|quota/i.test(message),
      );
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * Mensagem de estouro de tempo, com o caminho de saida concreto.
 *
 * O tamanho do material entra na mensagem porque e a variavel que o usuario
 * controla: dizer "demorou demais" sem dizer "voce mandou 102 KB" nao ajuda
 * ninguem a decidir o que fazer.
 */
function timeoutMessage(timeoutMs: number, request: ProviderRequest): string {
  const kb = Math.round(request.material.length / 1024);
  return (
    `A auditoria excedeu ${timeoutMs / 1000}s e foi cancelada.\n` +
    `Material enviado: ${kb} KB.\n\n` +
    'Diffs grandes com raciocinio irrestrito nao terminam em tempo util.\n' +
    'Opcoes, da melhor para a pior:\n' +
    '  1. reduza o escopo:      --base HEAD~1  (em vez de varios commits)\n' +
    '  2. audite por arquivo:   --file <caminho>\n' +
    '  3. limite o raciocinio:  --thinking 4096\n' +
    '     ATENCAO: isso rebaixa defeitos de FAIL para WARN. Ver o comentario\n' +
    '     de DEFAULT_THINKING_BUDGET neste arquivo antes de usar no gate.\n' +
    '  4. aumente o teto:       --timeout 600'
  );
}

function isTransient(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  // `limit: 0` nao e throttling -- e o modelo indisponivel para o tier da
  // chave. Repetir nunca resolve.
  if (/"?limit"?:\s*0\b/.test(message)) return false;
  return /\b(429|500|502|503|504)\b|UNAVAILABLE|RESOURCE_EXHAUSTED|deadline/i.test(
    message,
  );
}

/** Traduz erros comuns da API em orientacao acionavel. */
export function explainApiError(error: unknown, model: string): string {
  const message = error instanceof Error ? error.message : String(error);

  if (/"?limit"?:\s*0\b/.test(message)) {
    return (
      `O modelo "${model}" tem cota ZERO para esta chave (tier gratuito).\n` +
      'Isso nao e limite de velocidade -- o modelo nao esta disponivel.\n' +
      'Opcoes:\n' +
      `  1. use um modelo Flash:  --model ${API_DEFAULT_MODEL}\n` +
      '  2. habilite billing no projeto para liberar a familia Pro:\n' +
      '     https://aistudio.google.com/apikey\n\n' +
      message
    );
  }
  if (/no longer available to new users/.test(message)) {
    return (
      `O modelo "${model}" foi descontinuado para chaves novas.\n` +
      `Use --model ${API_DEFAULT_MODEL} (Flash roda no tier gratuito).\n\n` +
      message
    );
  }
  if (/API[_ ]?key not valid|API_KEY_INVALID|\b401\b|\b403\b/.test(message)) {
    return (
      'A GEMINI_API_KEY foi rejeitada pela API.\n' +
      'Gere uma nova em https://aistudio.google.com/apikey e atualize `.env.qa`.\n' +
      'A chave precisa vir de um projeto com a Generative Language API ativa.\n\n' +
      message
    );
  }
  return message;
}
