/**
 * Contrato entre o runner e o backend que fala com o Gemini.
 *
 * Dois backends, com papeis distintos:
 *
 * - `agy`: CLI do Antigravity, autenticado pela ASSINATURA Google AI Pro.
 *   Da acesso a familia Pro sem API key e sem billing, e roda em qualquer
 *   shell -- inclusive hook e CI. E o caminho de cota alta.
 *
 * - `api`: chamada direta a `generativelanguage.googleapis.com` com API key.
 *   Schema forcado pelo servidor e `temperature: 0`, entao e o mais
 *   deterministico. Porem no tier gratuito sao 20 requisicoes/dia e a
 *   familia Pro tem cota ZERO. Fica como alternativa reproduzivel.
 *
 * O runner nao sabe qual esta em uso: recebe texto JSON e valida.
 */

import type { Schema } from '@google/genai';

import type { ScreenshotPart } from '../screenshot.ts';

/** Tudo o que um backend precisa para executar uma auditoria. */
export interface ProviderRequest {
  /** Instrucao de sistema (rulebook). */
  system: string;
  /** Instrucoes da tarefa -- sem o material auditado. */
  instructions: string;
  /** Material auditado (diff ou arquivos). Pode ter centenas de KB. */
  material: string;
  /** Modelo a usar, ou undefined para o padrao do backend. */
  model?: string;
  /**
   * Capturas de tela para auditoria visual, ja em base64 inline.
   * So o backend `api` consegue transmitir imagem.
   */
  screenshots?: ScreenshotPart[];
  /**
   * Contrato de saida a exigir do modelo. Omitido, vale `QA_RESPONSE_SCHEMA`
   * -- o do auditor.
   *
   * Existe porque o schema estava soldado ao transporte: os dois backends
   * importavam o do auditor diretamente, e nenhum outro agente cabia sem
   * duplicar o provider. O tipo aqui e o do SDK (`Schema`), nao JSON Schema
   * padrao: e `api` que o consome direto, enquanto `agy` converte com
   * `toJsonSchema` na hora de gravar o arquivo do `--json-schema`.
   */
  schema?: Schema;
}

/**
 * Consumo de tokens de uma chamada.
 *
 * Existe porque a cota do backend `agy` e da assinatura, nao da API: nao ha
 * painel de billing para consultar. Medir aqui e a unica forma de saber quanto
 * cada auditoria custa e quantas cabem no dia.
 */
export interface ProviderUsage {
  inputTokens: number;
  outputTokens: number;
  thinkingTokens: number;
  totalTokens: number;
}

/**
 * O que um backend devolve. Nao valida nada: a validacao do JSON contra o
 * schema e do runner, para que os dois backends passem pelo mesmo crivo.
 */
export interface ProviderResult {
  /** Texto bruto retornado. Espera-se JSON, possivelmente sujo. */
  text: string;
  /** Modelo efetivamente usado, para o cabecalho do relatorio. */
  model: string;
  /** Consumo, quando o backend reporta. A API key nao reporta por chamada. */
  usage?: ProviderUsage;
}

/**
 * Backend de auditoria.
 *
 * A ordem de uso e fixa: `preflight()` antes de `run()`, para que a falta de
 * credencial ou de binario apareca como mensagem acionavel antes de montar um
 * payload de centenas de KB.
 */
export interface QaProvider {
  /** Identificador do backend, para o cabecalho do relatorio. */
  readonly name: 'api' | 'agy';
  /** Descricao da autenticacao, exibida no cabecalho do relatorio. */
  describeAuth(): string;
  /** Falha com mensagem acionavel se o backend nao estiver utilizavel. */
  preflight(): void;
  /**
   * Executa a auditoria.
   *
   * Lanca `ProviderError` com `transient` para falha que vale repetir e com
   * `quota` para cota esgotada, que alimenta a fila de pendencias.
   */
  run(request: ProviderRequest): Promise<ProviderResult>;
}

/**
 * Falha de backend, classificada pela acao que ela permite.
 *
 * Um erro sem `transient` nem `quota` e definitivo: nao adianta repetir agora
 * nem depois, e o runner sai com codigo 2.
 */
export class ProviderError extends Error {
  /** Vale repetir imediatamente -- rede instavel, 5xx, sobrecarga. */
  readonly transient: boolean;
  /**
   * Cota esgotada, especificamente.
   *
   * Distinto de `transient` porque a acao e outra: erro transitorio se resolve
   * repetindo agora; cota esgotada so se resolve com o tempo passando. E o
   * segundo caso que alimenta a fila de pendencias -- repetir seria inutil, e
   * desistir sem registrar perderia a auditoria.
   */
  readonly quota: boolean;

  /**
   * @param message Mensagem acionavel, exibida ao usuario.
   * @param transient Vale repetir agora. Padrao `false`.
   * @param quota Cota esgotada. Padrao `false`.
   */
  constructor(message: string, transient = false, quota = false) {
    super(message);
    this.name = 'ProviderError';
    this.transient = transient;
    this.quota = quota;
  }
}
