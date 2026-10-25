import { AuditEvent, AuditRecorder, isJsonObject, ManualValuationRecord } from '../core';
import { type AuditChannel, openAuditChannel } from './audit-channel';

/** Papel desta janela no barramento de auditoria. */
export type AuditRole =
  /** A janela onde o usuário opera: produz os eventos. */
  | 'emitter'
  /** A janela paralela de inspeção, em `/logs`: apenas consome. */
  | 'inspector';

/** Eventos descartados por falta de espaço, por anel. Chaves do protocolo. */
export interface DiscardedCounts {
  readonly calculos: number;
  readonly rede: number;
}

/** O que a interface lê do barramento, imutável a cada mudança. */
export interface AuditSnapshot {
  readonly history: readonly AuditEvent[];
  readonly discardedCalculations: number;
  readonly discardedNetwork: number;
  readonly role: AuditRole | null;
  readonly crossWindow: boolean;
  /**
   * `true` quando o inspetor já ouviu a janela que calcula — pelo aperto de
   * mão ou por qualquer evento dela. Na janela emissora, sempre `true`.
   */
  readonly peerConnected: boolean;
}

/**
 * Mensagens do protocolo entre janelas.
 *
 * - `hello`: a janela emissora anuncia que subiu — o inspetor aberto antes
 *   dela pede o histórico ao ouvi-la;
 * - `replay-request`: o inspetor entrou e pede o que já aconteceu;
 * - `replay`: a resposta, com o anel inteiro e os descartes da origem;
 * - `event`: um evento novo, no instante em que acontece;
 * - `clear`: apaga o histórico em todas as janelas.
 */
type AuditMessage =
  | { kind: 'hello' }
  | { kind: 'replay-request' }
  | { kind: 'replay'; events: unknown[]; descartados?: unknown }
  | { kind: 'event'; event: unknown; descartados?: unknown }
  | { kind: 'clear' };

/**
 * Barramento que liga o motor de cálculo ao painel de auditoria.
 *
 * Une três origens numa única fonte para a interface:
 *
 * 1. o coletor do núcleo ([AuditRecorder]), quando esta janela é a que calcula;
 * 2. o interceptador de rede, pelo mesmo coletor;
 * 3. o canal entre janelas, quando o painel está em outra aba.
 *
 * O histórico é mantido em memória dos dois lados. A `BroadcastChannel` não
 * guarda nada, e o painel costuma ser aberto **depois** de o usuário já ter
 * feito algumas consultas: sem o histórico, a segunda aba abriria vazia. Por
 * isso o inspetor pede um *replay* ao entrar, e a janela emissora responde com
 * o que tiver no anel.
 */
export class AuditBus {
  /** Nome do canal. Fixo: as duas janelas precisam concordar sem combinar. */
  static readonly channelName = 'equisim_audit_channel_v1';

  /**
   * Teto do anel de **cálculos**.
   *
   * **Dois anéis, e não um** (item D4). Com um só, de 200, cada avaliação
   * dispara várias idas à rede, e numa carteira de quinze ativos o ruído de
   * rede empurrava para fora justamente as avaliações que se abre o painel
   * para depurar. Cada anel descarta o seu mais antigo, e o descarte é
   * contado.
   */
  static readonly calculationLimit = 200;

  /** Teto do anel de eventos de **rede**. */
  static readonly networkLimit = 300;

  /**
   * O evento é de cálculo do núcleo, e não de ida à rede?
   *
   * **Pela origem, e não pela presença de passos** (item D4). Uma avaliação
   * recusada antes do primeiro passo não tem cálculo decomposto, e a regra
   * antiga a mostrava como ida à rede.
   */
  static isCalculation(event: AuditEvent): boolean {
    return event.endpoint.startsWith('/core/');
  }

  /** O evento é um valuation que o usuário confirmou na edição (decisão 150)? */
  static isConfirmedValuation(event: AuditEvent): boolean {
    return event.endpoint.startsWith(ManualValuationRecord.endpointPrefix);
  }

  private buffer: AuditEvent[] = [];
  private readonly seen = new Set<string>();
  private discarded = { calculos: 0, rede: 0 };
  private originDiscarded = { calculos: 0, rede: 0 };
  private channel: AuditChannel | null = null;
  private unlisten: (() => void) | null = null;
  private role: AuditRole | null = null;
  private peerConnected = false;
  private readonly listeners = new Set<() => void>();
  private snapshot: AuditSnapshot;

  constructor(private readonly openChannel: (name: string) => AuditChannel = openAuditChannel) {
    this.snapshot = this.buildSnapshot();
  }

  /** Assina as mudanças — o contrato de `useSyncExternalStore`. */
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /** O estado atual. A mesma referência enquanto nada mudar. */
  getSnapshot = (): AuditSnapshot => this.snapshot;

  /** Eventos, do mais antigo ao mais recente. */
  get history(): readonly AuditEvent[] {
    return this.snapshot.history;
  }

  /**
   * Cálculos que saíram do histórico por falta de espaço, **nesta janela ou
   * na que calcula** — o maior dos dois, porque o painel em outra aba só vê o
   * que a janela emissora ainda tinha. Um arquivo exportado com descarte não
   * está completo, e diz isso.
   */
  get discardedCalculations(): number {
    return Math.max(this.discarded.calculos, this.originDiscarded.calculos);
  }

  /** Eventos de rede descartados, pela mesma regra. */
  get discardedNetwork(): number {
    return Math.max(this.discarded.rede, this.originDiscarded.rede);
  }

  /** Liga o barramento. Chamar duas vezes é inofensivo. */
  start(role: AuditRole): void {
    if (this.role !== null) return;
    this.role = role;
    const channel = this.openChannel(AuditBus.channelName);
    this.channel = channel;
    this.unlisten = channel.listen((raw) => this.onRemoteMessage(raw));
    if (role === 'emitter') {
      // A partir daqui todo cálculo do núcleo passa a emitir rastro. Antes
      // disto, `AuditRecorder.begin` devolvia `null` e nada era montado.
      AuditRecorder.attach((event) => this.publishLocal(event));
      this.peerConnected = true;
      // O aperto de mão: um painel aberto antes desta janela fica sabendo
      // que ela subiu, e pede o histórico.
      this.post({ kind: 'hello' });
    } else {
      // O painel entrou depois: pede o que já aconteceu.
      this.post({ kind: 'replay-request' });
    }
    this.changed();
  }

  /** Reenvia o pedido de histórico — o botão de reconexão do painel. */
  requestReplay(): void {
    this.post({ kind: 'replay-request' });
  }

  /**
   * Apaga o histórico em **todas** as janelas.
   *
   * Limpar só a lista local deixaria o anel da janela emissora intacto, e o
   * próximo *replay* traria de volta exatamente o que o usuário mandou apagar.
   */
  clear(): void {
    this.clearLocal();
    this.post({ kind: 'clear' });
  }

  /** Desliga o barramento e o coletor do núcleo. */
  dispose(): void {
    if (this.role === 'emitter') AuditRecorder.detach();
    this.unlisten?.();
    this.channel?.close();
    this.channel = null;
    this.unlisten = null;
    this.role = null;
    this.changed();
  }

  // ------------------------------------------------------------- Interno --

  private post(message: AuditMessage): void {
    this.channel?.post(JSON.stringify(message));
  }

  private publishLocal(event: AuditEvent): void {
    this.record(event);
    // **O coletor roda dentro da transação que fecha o cálculo**: uma exceção
    // aqui subiria para a avaliação. A serialização do núcleo já é segura
    // (`AuditJson`), e esta guarda é a segunda linha — o evento fica no
    // histórico local mesmo que não atravesse para a outra janela.
    try {
      this.post({ kind: 'event', event: event.toJson(), descartados: { ...this.discarded } });
    } catch (error) {
      console.warn('⚠️  Evento de auditoria não transmitido:', error);
    }
  }

  private record(event: AuditEvent): void {
    if (this.seen.has(event.transactionId)) return;
    this.seen.add(event.transactionId);
    const buffer = [...this.buffer, event];
    const isCalculationEvent = AuditBus.isCalculation(event);
    const cap = isCalculationEvent ? AuditBus.calculationLimit : AuditBus.networkLimit;
    let sameKind = buffer.filter((e) => AuditBus.isCalculation(e) === isCalculationEvent).length;
    while (sameKind > cap) {
      const i = buffer.findIndex((e) => AuditBus.isCalculation(e) === isCalculationEvent);
      const [removed] = buffer.splice(i, 1);
      if (removed !== undefined) this.seen.delete(removed.transactionId);
      sameKind--;
      if (isCalculationEvent) this.discarded.calculos++;
      else this.discarded.rede++;
    }
    this.buffer = buffer;
    this.changed();
  }

  private clearLocal(): void {
    this.discarded = { calculos: 0, rede: 0 };
    this.originDiscarded = { calculos: 0, rede: 0 };
    this.buffer = [];
    this.seen.clear();
    this.changed();
  }

  private readOriginDiscarded(raw: unknown): void {
    if (!isJsonObject(raw)) return;
    const c = raw['calculos'];
    const r = raw['rede'];
    if (Number.isInteger(c) && (c as number) > this.originDiscarded.calculos) this.originDiscarded.calculos = c as number;
    if (Number.isInteger(r) && (r as number) > this.originDiscarded.rede) this.originDiscarded.rede = r as number;
  }

  private onRemoteMessage(raw: string): void {
    let decoded: unknown;
    try {
      decoded = JSON.parse(raw);
    } catch (error) {
      console.warn('⚠️  Mensagem de auditoria ilegível:', error);
      return;
    }
    if (!isJsonObject(decoded)) return;

    switch (decoded['kind']) {
      case 'hello':
        // A janela que calcula subiu depois do painel: o painel pede o que
        // ela já tiver — vazio, num arranque, mas a conexão fica marcada.
        if (this.role !== 'inspector') return;
        this.markPeer();
        this.requestReplay();
        return;

      case 'event': {
        if (this.role === 'inspector') this.markPeer();
        this.readOriginDiscarded(decoded['descartados']);
        const payload = decoded['event'];
        if (isJsonObject(payload)) this.record(AuditEvent.fromJson(payload));
        return;
      }

      case 'replay-request':
        // Só quem calcula tem histórico de verdade a oferecer. Responde mesmo
        // com o anel vazio: a resposta é também o aperto de mão.
        if (this.role !== 'emitter') return;
        this.post({ kind: 'replay', events: this.buffer.map((e) => e.toJson()), descartados: { ...this.discarded } });
        return;

      case 'replay': {
        if (this.role !== 'inspector') return;
        this.markPeer();
        this.readOriginDiscarded(decoded['descartados']);
        const events = decoded['events'];
        if (!Array.isArray(events)) return;
        for (const item of events) if (isJsonObject(item)) this.record(AuditEvent.fromJson(item));
        return;
      }

      case 'clear':
        this.clearLocal();
        return;
    }
  }

  private markPeer(): void {
    if (this.peerConnected) return;
    this.peerConnected = true;
    this.changed();
  }

  private buildSnapshot(): AuditSnapshot {
    return {
      history: this.buffer,
      discardedCalculations: this.discardedCalculations,
      discardedNetwork: this.discardedNetwork,
      role: this.role,
      crossWindow: this.channel?.supportsCrossWindow ?? false,
      peerConnected: this.peerConnected,
    };
  }

  private changed(): void {
    this.snapshot = this.buildSnapshot();
    for (const l of this.listeners) l();
  }
}

/**
 * A auditoria está ligada neste build?
 *
 * O padrão acompanha o modo de desenvolvimento — é onde o painel é usado —,
 * mas `VITE_EQUISIM_AUDIT=true` a liga num build de produção, para a
 * apresentação feita a partir do site publicado, que é o cenário em que
 * descobrir o painel desligado seria mais caro. `VITE_EQUISIM_AUDIT=false` a
 * desliga em desenvolvimento.
 */
export function auditEnabled(
  env: { DEV?: boolean; VITE_EQUISIM_AUDIT?: string } = (import.meta.env as ImportMetaEnv | undefined) ?? {},
): boolean {
  const flag = env.VITE_EQUISIM_AUDIT?.trim().toLowerCase();
  if (flag === 'true') return true;
  if (flag === 'false') return false;
  return env.DEV === true;
}

/** O barramento da página. Um só, como o coletor do núcleo. */
export const auditBus = new AuditBus();
