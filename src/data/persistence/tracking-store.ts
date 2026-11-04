import { collection, doc, type Firestore, getDoc, getDocs, query, where, writeBatch } from 'firebase/firestore';

import {
  ComputationFailure,
  err,
  InsufficientData,
  InvalidInput,
  ok,
  type Result,
  TrackingOrder,
  TrackingRecord,
} from '../../core';
import type { KeyValueStore } from '../cache/key-value-store';
import { firebaseMessage } from './portfolio-store';

/** Um acompanhamento gravado e as compras dele, em ordem de aporte. */
export interface StoredTracking {
  readonly record: TrackingRecord;
  readonly orders: readonly TrackingOrder[];
}

/**
 * Onde moram os acompanhamentos da carteira (decisão 159).
 *
 * **As compras só se acrescentam.** Uma compra gravada é a prova de que a
 * decisão usou só o que se sabia no dia; por isso não há operação que a
 * altere, e a regra do Firestore recusa a alteração (`firestore.rules`).
 * Apagar só apaga o acompanhamento inteiro.
 */
export interface TrackingStore {
  /** Os acompanhamentos do usuário, do mais recente para o mais antigo. Lista vazia é sucesso. */
  listFor(userId: string): Promise<Result<StoredTracking[]>>;

  /** Grava um acompanhamento novo, ainda sem compras. */
  create(userId: string, record: TrackingRecord): Promise<Result<void>>;

  /**
   * Acrescenta [orders] ao acompanhamento [trackingId]. **Idempotente**: cada
   * compra vai num documento nomeado pelo acompanhamento e pelo número do
   * aporte, e regravar a mesma compra não a duplica.
   */
  appendOrders(userId: string, trackingId: string, orders: readonly TrackingOrder[]): Promise<Result<void>>;

  /** Apaga o acompanhamento e todas as compras dele. **Irreversível.** */
  delete(userId: string, trackingId: string): Promise<Result<void>>;
}

/** O nome do documento de uma compra: o acompanhamento e o aporte, com zeros à esquerda para ordenar. */
export function orderDocId(trackingId: string, seq: number): string {
  return `${trackingId}-${String(seq).padStart(4, '0')}`;
}

/** Teto de operações de um lote de escrita do Firestore. */
const BATCH_LIMIT = 500;

/**
 * Os acompanhamentos no Firestore: o plano em `trackings/{id}` e cada compra em
 * `trackingOrders/{id}-{seq}`, com o dono nos dois.
 *
 * As compras ficam numa coleção de topo, e não em subcoleção, pelo mesmo
 * motivo dos valuations: a consulta por dono basta para listar e para a
 * exclusão da conta (`account-data.ts`), sem índice de grupo de coleções.
 */
export class FirestoreTrackingStore implements TrackingStore {
  static readonly collection = 'trackings';
  static readonly ordersCollection = 'trackingOrders';

  constructor(
    readonly firestore: Firestore,
    private readonly warn: (message: string) => void = (m) => console.warn(m),
  ) {}

  private get trackings() {
    return collection(this.firestore, FirestoreTrackingStore.collection);
  }

  private get ordersRef() {
    return collection(this.firestore, FirestoreTrackingStore.ordersCollection);
  }

  async listFor(userId: string): Promise<Result<StoredTracking[]>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const [trackings, orders] = await Promise.all([
        getDocs(query(this.trackings, where('userId', '==', userId))),
        getDocs(query(this.ordersRef, where('userId', '==', userId))),
      ]);
      const byTracking = new Map<string, TrackingOrder[]>();
      for (const d of orders.docs) {
        const data = d.data();
        const order = TrackingOrder.fromJson(data['registro']);
        const trackingId = data['trackingId'];
        if (order === null || typeof trackingId !== 'string') {
          this.warn(`⚠️  Compra gravada ilegível, descartada: ${d.id}`);
          continue;
        }
        const list = byTracking.get(trackingId) ?? [];
        list.push(order);
        byTracking.set(trackingId, list);
      }
      return ok(assemble(trackings.docs.map((d) => ({ id: d.id, registro: d.data()['registro'] })), byTracking, this.warn));
    } catch (e) {
      return err(new ComputationFailure(`Falha ao carregar os acompanhamentos: ${firebaseMessage(e)}`));
    }
  }

  async create(userId: string, record: TrackingRecord): Promise<Result<void>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const batch = writeBatch(this.firestore);
      batch.set(doc(this.trackings, record.id), { userId, inicio: record.plan.toJson()['inicio'], registro: record.toJson() });
      await batch.commit();
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao iniciar o acompanhamento: ${firebaseMessage(e)}`));
    }
  }

  async appendOrders(userId: string, trackingId: string, orders: readonly TrackingOrder[]): Promise<Result<void>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      for (let start = 0; start < orders.length; start += BATCH_LIMIT) {
        const batch = writeBatch(this.firestore);
        for (const o of orders.slice(start, start + BATCH_LIMIT)) {
          batch.set(doc(this.ordersRef, orderDocId(trackingId, o.seq)), {
            userId,
            trackingId,
            seq: o.seq,
            registro: o.toJson(),
          });
        }
        await batch.commit();
      }
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao gravar as compras do acompanhamento: ${firebaseMessage(e)}`));
    }
  }

  async delete(userId: string, trackingId: string): Promise<Result<void>> {
    try {
      const snapshot = await getDoc(doc(this.trackings, trackingId));
      if (!snapshot.exists()) return err(new InsufficientData('Acompanhamento não encontrado.'));
      if (snapshot.data()['userId'] !== userId) return err(new InvalidInput('Este acompanhamento pertence a outro usuário.'));
      const orders = await getDocs(
        query(this.ordersRef, where('userId', '==', userId), where('trackingId', '==', trackingId)),
      );
      // As compras saem antes do plano: uma falha no meio deixa o plano de pé,
      // e repetir a exclusão apaga o resto.
      for (let start = 0; start < orders.docs.length; start += BATCH_LIMIT) {
        const batch = writeBatch(this.firestore);
        for (const d of orders.docs.slice(start, start + BATCH_LIMIT)) batch.delete(d.ref);
        await batch.commit();
      }
      const last = writeBatch(this.firestore);
      last.delete(doc(this.trackings, trackingId));
      await last.commit();
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao apagar o acompanhamento: ${firebaseMessage(e)}`));
    }
  }
}

/** Monta a lista a partir dos documentos lidos, descartando o ilegível. */
function assemble(
  trackings: readonly { id: string; registro: unknown }[],
  ordersByTracking: ReadonlyMap<string, TrackingOrder[]>,
  warn: (message: string) => void,
): StoredTracking[] {
  const out: StoredTracking[] = [];
  for (const t of trackings) {
    const record = TrackingRecord.fromJson(t.registro);
    if (record === null) {
      warn(`⚠️  Acompanhamento gravado ilegível, descartado: ${t.id}`);
      continue;
    }
    const orders = [...(ordersByTracking.get(record.id) ?? [])].sort((a, b) => a.seq - b.seq);
    out.push({ record, orders });
  }
  out.sort((a, b) => b.record.createdAt.compareTo(a.record.createdAt));
  return out;
}

interface LocalTrackingDocument {
  userId: string;
  registro: unknown;
  compras: Record<string, unknown>;
}

/**
 * Acompanhamentos sobre um armazenamento chave-valor — o navegador, no modo
 * local, e a memória, nos testes. As mesmas regras do Firestore: a compra já
 * gravada não é sobrescrita, e só o dono apaga.
 */
export class KeyValueTrackingStore implements TrackingStore {
  constructor(
    private readonly store: KeyValueStore,
    private readonly warn: (message: string) => void = (m) => console.warn(m),
  ) {}

  private static readonly key = 'acompanhamentos';

  private async all(): Promise<Record<string, LocalTrackingDocument>> {
    return (await this.store.get<Record<string, LocalTrackingDocument>>(KeyValueTrackingStore.key)) ?? {};
  }

  async listFor(userId: string): Promise<Result<StoredTracking[]>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const docs = Object.entries(await this.all()).filter(([, d]) => d.userId === userId);
      const byTracking = new Map<string, TrackingOrder[]>();
      for (const [id, d] of docs) {
        const list: TrackingOrder[] = [];
        for (const [key, raw] of Object.entries(d.compras ?? {})) {
          const o = TrackingOrder.fromJson(raw);
          if (o === null) {
            this.warn(`⚠️  Compra gravada ilegível, descartada: ${id}-${key}`);
            continue;
          }
          list.push(o);
        }
        byTracking.set(id, list);
      }
      return ok(assemble(docs.map(([id, d]) => ({ id, registro: d.registro })), byTracking, this.warn));
    } catch (e) {
      return err(new ComputationFailure(`Falha ao carregar os acompanhamentos: ${firebaseMessage(e)}`));
    }
  }

  async create(userId: string, record: TrackingRecord): Promise<Result<void>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      await this.store.update<Record<string, LocalTrackingDocument>>(KeyValueTrackingStore.key, (old) => {
        const next = { ...(old ?? {}) };
        const existing = next[record.id];
        next[record.id] = { userId, registro: record.toJson(), compras: existing?.compras ?? {} };
        return next;
      });
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao iniciar o acompanhamento: ${firebaseMessage(e)}`));
    }
  }

  async appendOrders(userId: string, trackingId: string, orders: readonly TrackingOrder[]): Promise<Result<void>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    const found = (await this.all())[trackingId];
    if (found === undefined) return err(new InsufficientData('Acompanhamento não encontrado.'));
    if (found.userId !== userId) return err(new InvalidInput('Este acompanhamento pertence a outro usuário.'));
    try {
      await this.store.update<Record<string, LocalTrackingDocument>>(KeyValueTrackingStore.key, (old) => {
        const next = { ...(old ?? {}) };
        const d = next[trackingId]!;
        const compras = { ...d.compras };
        // A compra já gravada fica como está: só se acrescenta.
        for (const o of orders) {
          const key = String(o.seq).padStart(4, '0');
          if (!(key in compras)) compras[key] = o.toJson();
        }
        next[trackingId] = { ...d, compras };
        return next;
      });
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao gravar as compras do acompanhamento: ${firebaseMessage(e)}`));
    }
  }

  async delete(userId: string, trackingId: string): Promise<Result<void>> {
    try {
      const found = (await this.all())[trackingId];
      if (found === undefined) return err(new InsufficientData('Acompanhamento não encontrado.'));
      if (found.userId !== userId) return err(new InvalidInput('Este acompanhamento pertence a outro usuário.'));
      await this.store.update<Record<string, LocalTrackingDocument>>(KeyValueTrackingStore.key, (old) => {
        const next = { ...(old ?? {}) };
        delete next[trackingId];
        return next;
      });
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao apagar o acompanhamento: ${firebaseMessage(e)}`));
    }
  }
}
