import {
  collection,
  deleteDoc,
  doc,
  type Firestore,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  where,
} from 'firebase/firestore';

import {
  ComputationFailure,
  err,
  InsufficientData,
  InvalidInput,
  isJsonObject,
  ManualValuationRecord,
  ok,
  type Result,
} from '../../core';
import type { KeyValueStore } from '../cache/key-value-store';
import { firebaseMessage } from './portfolio-store';

/**
 * Onde moram os valuations que o usuário confirmou (decisão 150).
 *
 * **Contrato, e não classe concreta**, porque a tela e o painel de logs são
 * testados sem Firebase: o teste monta a mesma lógica sobre um armazenamento
 * em memória, o modo local sobre o navegador, e o aplicativo conectado, sobre
 * o Firestore.
 */
export interface ManualValuationStore {
  /**
   * Os valuations do usuário, do mais recente para o mais antigo.
   *
   * Lista vazia é **sucesso**. Um documento ilegível é descartado, e não
   * derruba a lista.
   */
  listFor(userId: string): Promise<Result<ManualValuationRecord[]>>;

  /**
   * Grava [record] em nome de [userId].
   *
   * **Idempotente**: o documento leva o identificador do registro, então
   * repetir a gravação depois de uma falha de rede não cria duplicata.
   */
  save(userId: string, record: ManualValuationRecord): Promise<Result<void>>;

  /** Apaga o valuation [id], conferindo que ele é de [userId]. Irreversível. */
  delete(userId: string, id: string): Promise<Result<void>>;
}

/** Registro lido do documento, ou `null` quando ilegível. */
function recordFrom(raw: unknown): ManualValuationRecord | null {
  return isJsonObject(raw) ? ManualValuationRecord.fromJson(raw) : null;
}

const SAVE_TIMEOUT_MESSAGE =
  'O servidor não confirmou a gravação a tempo. Confira a conexão e ' +
  'confirme de novo: a nova tentativa não duplica o valuation.';

class SaveTimeout extends Error {}

/**
 * Os valuations confirmados no Firestore, na coleção [collection].
 *
 * O desenho segue o de `FirestorePortfolioStore`: o dono vai no documento, a
 * regra de segurança confere que é quem está autenticado, e a ordenação é
 * local para não exigir índice composto publicado.
 */
export class FirestoreManualValuationStore implements ManualValuationStore {
  /** Nome da coleção. Ver `firestore.rules`. */
  static readonly collection = 'valuations';

  /**
   * Quanto esperar a confirmação do servidor antes de desistir, em
   * milissegundos.
   *
   * Sem teto, a gravação feita sem rede no navegador fica pendurada para
   * sempre — o Firestore da web só resolve o `set` quando o servidor
   * confirma —, e o botão de confirmar ficaria girando sem dizer nada.
   */
  readonly timeoutMs: number;

  /** Destino do aviso de documento ilegível. */
  private readonly warn: (message: string) => void;

  constructor(
    readonly firestore: Firestore,
    options: { timeoutMs?: number; warn?: (message: string) => void } = {},
  ) {
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.warn = options.warn ?? ((m) => console.warn(m));
  }

  private get ref() {
    return collection(this.firestore, FirestoreManualValuationStore.collection);
  }

  async listFor(userId: string): Promise<Result<ManualValuationRecord[]>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const snapshot = await getDocs(query(this.ref, where('userId', '==', userId)));
      const records: ManualValuationRecord[] = [];
      for (const d of snapshot.docs) {
        const record = recordFrom(d.data()['registro']);
        if (record === null) {
          this.warn(`⚠️  Valuation salvo ilegível, descartado: ${d.id}`);
          continue;
        }
        records.push(record);
      }
      records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return ok(records);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao carregar os valuations salvos: ${firebaseMessage(e)}`));
    }
  }

  async save(userId: string, record: ManualValuationRecord): Promise<Result<void>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const write = setDoc(doc(this.ref, record.id), {
        userId,
        // Campos de topo só para consulta e leitura no console; a verdade é o
        // `registro`, que o núcleo relê.
        ticker: record.ticker.value,
        salvoEm: Timestamp.fromMillis(record.savedAt.millisecondsSinceEpoch),
        registro: record.toJson(),
        gravadoEm: serverTimestamp(),
      });
      const timeout = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new SaveTimeout()), this.timeoutMs);
      });
      await Promise.race([write, timeout]);
      return ok(undefined);
    } catch (e) {
      if (e instanceof SaveTimeout) return err(new ComputationFailure(SAVE_TIMEOUT_MESSAGE));
      return err(new ComputationFailure(`Falha ao salvar o valuation: ${firebaseMessage(e)}`));
    } finally {
      clearTimeout(timer);
    }
  }

  async delete(userId: string, id: string): Promise<Result<void>> {
    try {
      const snapshot = await getDoc(doc(this.ref, id));
      if (!snapshot.exists()) return err(new InsufficientData('Valuation não encontrado.'));
      // Dupla checagem local, além da regra de segurança do Firestore: a regra
      // é a barreira, esta produz a frase que o usuário entende.
      if (snapshot.data()['userId'] !== userId) {
        return err(new InvalidInput('Este valuation pertence a outro usuário.'));
      }
      await deleteDoc(doc(this.ref, id));
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao apagar o valuation: ${firebaseMessage(e)}`));
    }
  }
}

/** Documento guardado pelos armazenamentos sem Firebase. */
interface StoredValuation {
  id: string;
  userId: string;
  registro: unknown;
}

/**
 * Valuations confirmados sobre um armazenamento chave-valor — o navegador, no
 * modo local, e a memória, nos testes.
 *
 * As mesmas regras do Firestore: idempotência pelo identificador do registro,
 * conferência de dono no apagamento, documento ilegível descartado na
 * listagem.
 */
export class KeyValueManualValuationStore implements ManualValuationStore {
  constructor(
    private readonly store: KeyValueStore,
    private readonly warn: (message: string) => void = (m) => console.warn(m),
  ) {}

  private static readonly key = 'valuations';

  private async all(): Promise<StoredValuation[]> {
    return (await this.store.get<StoredValuation[]>(KeyValueManualValuationStore.key)) ?? [];
  }

  async listFor(userId: string): Promise<Result<ManualValuationRecord[]>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const records: ManualValuationRecord[] = [];
      for (const d of await this.all()) {
        if (d.userId !== userId) continue;
        const record = recordFrom(d.registro);
        if (record === null) {
          this.warn(`⚠️  Valuation salvo ilegível, descartado: ${d.id}`);
          continue;
        }
        records.push(record);
      }
      records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return ok(records);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao carregar os valuations salvos: ${firebaseMessage(e)}`));
    }
  }

  async save(userId: string, record: ManualValuationRecord): Promise<Result<void>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const stored: StoredValuation = { id: record.id, userId, registro: record.toJson() };
      await this.store.update<StoredValuation[]>(KeyValueManualValuationStore.key, (old) => [
        ...(old ?? []).filter((d) => d.id !== record.id),
        stored,
      ]);
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao salvar o valuation: ${firebaseMessage(e)}`));
    }
  }

  async delete(userId: string, id: string): Promise<Result<void>> {
    try {
      const found = (await this.all()).find((d) => d.id === id);
      if (found === undefined) return err(new InsufficientData('Valuation não encontrado.'));
      if (found.userId !== userId) return err(new InvalidInput('Este valuation pertence a outro usuário.'));
      await this.store.update<StoredValuation[]>(KeyValueManualValuationStore.key, (old) =>
        (old ?? []).filter((d) => d.id !== id),
      );
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao apagar o valuation: ${firebaseMessage(e)}`));
    }
  }
}
