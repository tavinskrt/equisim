/**
 * Canal de auditoria entre a janela que calcula e a janela que audita.
 *
 * **Por que não WebSocket ou SSE.** Neste sistema não existe backend próprio:
 * o motor financeiro roda dentro da própria aplicação, e a única API remota é
 * a brapi.dev, de terceiros. Levantar um servidor só para reemitir eventos
 * criaria uma peça de infraestrutura que não participa do cálculo — e o que
 * ela retransmitisse seria uma cópia do que aconteceu no navegador, não o
 * cálculo em si.
 *
 * O equivalente fiel é a `BroadcastChannel` do próprio navegador: canal
 * nomeado, mesma origem, entrega por *push* entre abas, com a semântica de
 * assinatura de um SSE — e o evento sai de dentro do cálculo, sem
 * intermediário que possa divergir dele
 * (https://html.spec.whatwg.org/multipage/web-messaging.html#broadcasting-to-other-browsing-contexts).
 *
 * Onde ela não existe — o Node das ferramentas e dos testes —, o canal degrada
 * para entrega local, e o painel continua funcionando na mesma janela.
 */
export interface AuditChannel {
  /** `true` quando há transporte real entre janelas. */
  readonly supportsCrossWindow: boolean;

  /** Publica uma mensagem já serializada em JSON. */
  post(json: string): void;

  /**
   * Assina as mensagens vindas de **outras** janelas. A `BroadcastChannel`
   * não entrega ao próprio remetente — a entrega local é do barramento.
   * Devolve a função que cancela a assinatura.
   */
  listen(onMessage: (json: string) => void): () => void;

  /** Encerra o canal. Chamar duas vezes é inofensivo. */
  close(): void;
}

/**
 * Canal sobre a `BroadcastChannel` do navegador.
 *
 * O tráfego é **texto JSON**, e não objeto estruturado: é exatamente o formato
 * que a exportação da auditoria produz no fim, e o que atravessa o canal é o
 * que o arquivo terá — o clone estruturado levaria instâncias que o outro lado
 * reconstruiria por outro caminho.
 */
export class BroadcastAuditChannel implements AuditChannel {
  readonly supportsCrossWindow = true;
  private readonly channel: BroadcastChannel;
  private readonly listeners = new Set<(json: string) => void>();
  private closed = false;

  constructor(name: string) {
    this.channel = new BroadcastChannel(name);
    this.channel.addEventListener('message', (event: MessageEvent<unknown>) => {
      if (this.closed || typeof event.data !== 'string') return;
      for (const l of this.listeners) l(event.data);
    });
  }

  post(json: string): void {
    if (!this.closed) this.channel.postMessage(json);
  }

  listen(onMessage: (json: string) => void): () => void {
    this.listeners.add(onMessage);
    return () => this.listeners.delete(onMessage);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.listeners.clear();
    this.channel.close();
  }
}

/** Canal sem transporte: nada sai, nada chega. O barramento entrega localmente. */
export class LocalAuditChannel implements AuditChannel {
  readonly supportsCrossWindow = false;
  post(_json: string): void {}
  listen(_onMessage: (json: string) => void): () => void {
    return () => {};
  }
  close(): void {}
}

/** O canal apropriado ao hospedeiro. */
export function openAuditChannel(name: string): AuditChannel {
  return typeof BroadcastChannel === 'function' ? new BroadcastAuditChannel(name) : new LocalAuditChannel();
}
