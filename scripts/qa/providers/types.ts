/**
 * Contrato entre o runner e o backend que fala com o Gemini.
 *
 * Existem dois backends porque eles resolvem problemas diferentes:
 *
 * - `api`: chamada direta a `generativelanguage.googleapis.com` com API key.
 *   Suporta Structured Output com schema FORCADO pelo servidor e
 *   `temperature: 0`, entao o veredito e determinista. Roda em qualquer
 *   terminal -- inclusive no hook disparado pelo GitHub Desktop. E o padrao,
 *   e o unico que sustenta o gate de commit.
 *
 * - `antigravity`: usa a assinatura Google AI Pro pela agentapi do Antigravity,
 *   sem API key e sem billing. So funciona DENTRO do terminal integrado da IDE
 *   (ver o comentario em `antigravity.ts`), e nao tem schema forcado. Serve
 *   para auditoria profunda sob demanda, nao para o gate.
 *
 * O runner nao sabe qual esta em uso: recebe texto JSON e valida.
 */

import type { ScreenshotPart } from '../screenshot.ts';

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
}

export interface ProviderResult {
  /** Texto bruto retornado. Espera-se JSON, possivelmente sujo. */
  text: string;
  /** Modelo efetivamente usado, para o cabecalho do relatorio. */
  model: string;
}

export interface QaProvider {
  readonly name: 'api' | 'antigravity';
  /** Descricao da autenticacao, exibida no cabecalho do relatorio. */
  describeAuth(): string;
  /** Falha com mensagem acionavel se o backend nao estiver utilizavel. */
  preflight(): void;
  run(request: ProviderRequest): Promise<ProviderResult>;
  /**
   * Segunda tentativa quando o JSON volta invalido, apontando o erro ao modelo.
   *
   * Existe apenas em backends SEM schema forcado pelo servidor. No backend
   * `api` o formato e garantido pela API, entao insistir no mesmo prompt nao
   * mudaria nada -- por isso o metodo e opcional, e nao um no-op.
   */
  repair?(
    request: ProviderRequest,
    badOutput: string,
    parseError: string,
  ): Promise<ProviderResult>;
}

export class ProviderError extends Error {
  readonly transient: boolean;
  constructor(message: string, transient = false) {
    super(message);
    this.name = 'ProviderError';
    this.transient = transient;
  }
}
