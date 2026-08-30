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

/**
 * Modelo padrao: o APELIDO da familia Flash, nao uma versao.
 *
 * Flash roda no tier gratuito; Pro exige billing (ver comentario do modulo).
 *
 * POR QUE APELIDO E NAO VERSAO FIXA: enquanto isto era `gemini-3.5-flash`, o
 * gate envelhecia preso a uma versao -- a API ja oferecia `3.6` e `3.7`
 * enquanto o codigo continuava pedindo `3.5`. E o modelo mais apontado por
 * todo mundo tambem e o mais sujeito a 503, que foi como o problema apareceu.
 *
 * E o mesmo principio que o backend `agy` ja segue: o `CLAUDE.md` registra que
 * a lista dele "vem de `agy models` a cada execucao, nada e fixado por nome".
 * O backend `api` era a excecao, sem que ninguem tivesse decidido isso.
 *
 * O QUE SE PERDE, E COMO SE RECUPERA: um apelido pode resolver para versoes
 * diferentes em execucoes diferentes, o que atrapalharia a reproducao -- e
 * reproduzir e a razao de este backend existir. Por isso a resposta e lida por
 * `modelVersion` e o relatorio informa a versao CONCRETA que atendeu. Para
 * repetir uma auditoria exatamente, passe essa versao em `--model`.
 */
export const API_DEFAULT_MODEL = 'gemini-flash-latest';
/**
 * Modelo Pro, disponivel apenas por `--model`.
 *
 * No tier gratuito a cota da familia Pro e **zero**: usa-lo com API key sem
 * billing falha na primeira chamada. Mantido porque quem tem billing ativo se
 * beneficia, e porque o backend `agy` alcanca a familia Pro pela assinatura.
 */
export const API_PRO_MODEL = 'gemini-3.1-pro-preview';

/**
 * Cascata de modelos: do mais capaz ao de maior cota.
 *
 * O DADO QUE JUSTIFICA ISTO: no tier gratuito o limite diario e POR MODELO,
 * nao por chave. Medido no painel em 30/08/2026:
 *
 *     gemini-3.7-flash        19 / 20  requisicoes/dia
 *     gemini-3.6-flash         7 / 20
 *     gemini-3.5-flash        31 / 20  <- estourado
 *     gemini-3.5-flash-lite    2 / 500 <- vinte e cinco vezes mais folga
 *
 * Um apelido como `gemini-flash-latest` aponta para um modelo so, entao esgota
 * as 20 daquele e para -- foi assim que as consultas da lente `tela` passaram o
 * dia devolvendo 503. Descer a cascata usa a cota de cada um em vez da de um.
 *
 * TROCA ACEITA: `flash-lite` e mais fraco. Para critica de direcao visual isso
 * custa profundidade. Por isso o relatorio informa qual modelo respondeu, e o
 * runner avisa quando houve rebaixamento -- um parecer vindo do ultimo degrau
 * nao merece a mesma confianca do primeiro.
 *
 * Ordem fixa de proposito. Consultar o painel a cada execucao para escolher o
 * menos usado seria mais eficiente e menos previsivel; o custo de comecar pelo
 * topo e uma tentativa perdida quando ele ja esta cheio.
 */
export const API_CASCATA_FLASH: readonly string[] = [
  'gemini-3.7-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
];

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

/**
 * Backend por API key, chamando `generativelanguage.googleapis.com` direto.
 *
 * E o caminho **reproduzivel**: o schema e forcado pelo servidor e a
 * temperatura e zero, entao a mesma entrada tende a produzir o mesmo relatorio.
 * Em troca, o tier gratuito da 20 requisicoes por dia.
 */
export class ApiProvider implements QaProvider {
  readonly name = 'api' as const;

  private readonly repoRoot: string;
  private readonly thinkingBudget: number;
  private readonly timeoutMs: number;
  private key?: ApiKeyResolution;

  /** O que sugerir a quem estourou o teto. Ver `timeoutMessage`. */
  private readonly saidasDeTimeout: readonly string[];

  /**
   * Modelos a tentar, em ordem, quando o primeiro nao responde.
   *
   * Vazia por padrao -- o auditor NAO cascateia. Ele existe para ser
   * reproduzivel, e trocar de modelo no meio em silencio destruiria isso: dois
   * relatorios do mesmo diff poderiam vir de modelos diferentes sem que a
   * diferenca fosse escolha de ninguem. Quem quiser a cascata pede por ela.
   */
  private readonly cascata: readonly string[];

  constructor(
    repoRoot: string,
    thinkingBudget = DEFAULT_THINKING_BUDGET,
    timeoutMs = DEFAULT_TIMEOUT_MS,
    saidasDeTimeout: readonly string[] = SAIDAS_TIMEOUT_AUDITOR,
    cascata: readonly string[] = [],
  ) {
    this.repoRoot = repoRoot;
    this.thinkingBudget = thinkingBudget;
    this.timeoutMs = timeoutMs;
    this.saidasDeTimeout = saidasDeTimeout;
    this.cascata = cascata;
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

  /**
   * Executa, descendo a cascata quando o modelo do topo nao responde.
   *
   * `--model` explicito VENCE a cascata: quem fixou um modelo quer aquele, e
   * trocar por baixo dos panos e o oposto do que o pedido significa. E ao
   * esgotar a cascata o erro sobe como DEFINITIVO, nao transitorio -- repetir
   * a mesma sequencia agora daria a mesma coisa, e o laco de fora so gastaria
   * cota de novo.
   */
  async run(request: ProviderRequest): Promise<ProviderResult> {
    if (!this.key) this.preflight();

    const degraus =
      request.model !== undefined || this.cascata.length === 0
        ? [request.model ?? API_DEFAULT_MODEL]
        : this.cascata;

    let ultimo: unknown;
    for (const [i, modelo] of degraus.entries()) {
      try {
        return await this.chamar(request, modelo);
      } catch (erro) {
        ultimo = erro;
        const vale = erro instanceof ProviderError && (erro.transient || erro.quota);
        if (!vale || i === degraus.length - 1) break;
        process.stderr.write(
          `  ${modelo} indisponivel; descendo para ${degraus[i + 1]}\n`,
        );
        // O tier limita tambem por MINUTO (5 rpm nos Flash). Descer a cascata
        // em rajada esbarraria nesse teto e o degrau seguinte falharia por um
        // motivo que nao e o dele.
        await new Promise((r) => setTimeout(r, 1500));
      }
    }
    if (ultimo instanceof ProviderError && degraus.length > 1) {
      throw new ProviderError(
        `Nenhum modelo da cascata respondeu (${degraus.join(' -> ')}).\n` +
          `  Ultimo erro: ${ultimo.message}`,
      );
    }
    throw ultimo;
  }

  private async chamar(
    request: ProviderRequest,
    model: string,
  ): Promise<ProviderResult> {
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
          responseSchema: request.schema ?? QA_RESPONSE_SCHEMA,
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
      // A versao CONCRETA que atendeu, nao o apelido que foi pedido. Sem isto,
      // um relatorio de `gemini-flash-latest` nao diz o que de fato auditou, e
      // nao ha como repetir a auditoria depois -- que e justamente o que este
      // backend existe para permitir.
      return { text, model: response.modelVersion ?? model };
    } catch (error) {
      // O aborto e nosso, nao da API: traduzimos para a instrucao de escopo.
      if (controller.signal.aborted) {
        throw new ProviderError(
          timeoutMessage(this.timeoutMs, request, this.saidasDeTimeout),
        );
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
/**
 * Mensagem de estouro de tempo.
 *
 * As SAIDAS vem de quem chamou, nao daqui. Enquanto este texto trazia
 * `--base HEAD~1`, `--file` e `--thinking` fixos, o conselheiro estourava o
 * teto e recebia como conselho tres flags que a CLI dele nao tem -- o
 * transporte dava instrucao de um agente para o outro. Aqui se sabe QUANTO
 * tempo passou e QUANTO material foi; o que fazer a respeito e do chamador.
 */
function timeoutMessage(
  timeoutMs: number,
  request: ProviderRequest,
  saidas: readonly string[],
): string {
  const kb = Math.round(request.material.length / 1024);
  const imagens = request.screenshots?.length ?? 0;
  return (
    `A consulta excedeu ${timeoutMs / 1000}s e foi cancelada.\n` +
    `Material enviado: ${kb} KB` +
    (imagens > 0 ? `, mais ${imagens} imagem(ns).` : '.') +
    '\n\n' +
    (imagens > 0
      ? 'Requisicao multimodal custa bem mais tempo que a mesma em texto.\n'
      : 'Material grande com raciocinio irrestrito nao termina em tempo util.\n') +
    'Opcoes, da melhor para a pior:\n' +
    saidas.map((s, i) => `  ${i + 1}. ${s}`).join('\n')
  );
}

/** Saidas do auditor. Outro agente passa as suas ao construir o provider. */
export const SAIDAS_TIMEOUT_AUDITOR: readonly string[] = [
  'reduza o escopo:      --base HEAD~1  (em vez de varios commits)',
  'audite por arquivo:   --file <caminho>',
  'limite o raciocinio:  --thinking 4096\n' +
    '     ATENCAO: isso rebaixa defeitos de FAIL para WARN. Ver o comentario\n' +
    '     de DEFAULT_THINKING_BUDGET neste arquivo antes de usar no gate.',
  'aumente o teto:       --timeout 600',
];

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
