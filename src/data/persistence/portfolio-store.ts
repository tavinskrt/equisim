import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  type DocumentData,
  type Firestore,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

import {
  ComputationFailure,
  DateTime,
  err,
  InsufficientData,
  InvalidInput,
  isJsonObject,
  ok,
  PortfolioKind,
  type Result,
} from '../../core';
import type { KeyValueStore } from '../cache/key-value-store';
import { PortfolioStudyCodec } from './portfolio-codec';
import { compareStudiesByRecency, PortfolioStudy } from './portfolio-study';

/**
 * Onde moram os estudos do usuário.
 *
 * **Contrato, e não classe concreta**: o aplicativo grava no Firestore quando
 * o Firebase está configurado, e no navegador quando não está (modo local) —
 * e a tela não distingue os dois.
 */
export interface PortfolioStore {
  /**
   * Lista os estudos de um usuário, do mais recente para o mais antigo.
   * Lista vazia é **sucesso**, não falha.
   */
  listFor(userId: string): Promise<Result<PortfolioStudy[]>>;

  /**
   * Grava o estudo, criando ou atualizando conforme `study.id`, e devolve o
   * identificador do documento — o novo, na criação.
   */
  save(userId: string, study: PortfolioStudy): Promise<Result<string>>;

  /** Remove um estudo, conferindo a propriedade antes. **Irreversível.** */
  delete(userId: string, id: string): Promise<Result<void>>;
}

/** Documento do estudo, sem os carimbos de tempo, que cada armazenamento põe à sua maneira. */
function encodeStudy(userId: string, study: PortfolioStudy): Record<string, unknown> {
  const data: Record<string, unknown> = {
    userId,
    name: study.name,
    principal: PortfolioStudyCodec.encodePortfolio(study.principal),
    reserva: PortfolioStudyCodec.encodePortfolio(study.reserve),
  };
  // Uma meta nula é **omitida** em vez de gravada como nulo — o que, numa
  // atualização, deixa a meta anterior intacta no documento.
  if (study.goal !== null) data['goal'] = PortfolioStudyCodec.encodeGoal(study.goal);
  return data;
}

function decodeStudy(id: string, data: Record<string, unknown>, updatedAt: DateTime | null): PortfolioStudy {
  return new PortfolioStudy({
    id,
    name: typeof data['name'] === 'string' ? data['name'] : 'Estudo sem nome',
    principal: PortfolioStudyCodec.decodePortfolio(data['principal'], {
      id: `${id}-principal`,
      name: 'Principal',
      kind: PortfolioKind.principal,
    }),
    reserve: PortfolioStudyCodec.decodePortfolio(data['reserva'], {
      id: `${id}-reserva`,
      name: 'Reserva',
      kind: PortfolioKind.reserve,
    }),
    goal: PortfolioStudyCodec.decodeGoal(data['goal']),
    updatedAt,
  });
}

/** Mensagem de uma falha do Firebase, como o SDK a entrega. */
export function firebaseMessage(e: unknown): string {
  if (e instanceof Error && e.message.length > 0) return e.message;
  if (isJsonObject(e) && typeof e['code'] === 'string') return e['code'];
  return String(e);
}

/**
 * Persistência dos estudos no Firestore.
 *
 * Substitui a coleção `backtests`, do escopo anterior. Os documentos antigos
 * permanecem no banco com suas regras de segurança: apagá-los deixaria dados
 * de usuário órfãos. A migração é uma decisão do usuário, não um efeito
 * colateral da troca de escopo.
 */
export class FirestorePortfolioStore implements PortfolioStore {
  /** Nome da coleção. A anterior, `backtests`, permanece intocada no banco. */
  static readonly collection = 'portfolios';

  constructor(readonly firestore: Firestore) {}

  private get ref() {
    return collection(this.firestore, FirestorePortfolioStore.collection);
  }

  /**
   * Só o filtro por dono vai ao servidor. `orderBy` combinado com `where`
   * exigiria um índice composto publicado — e, sem ele, a consulta falha
   * inteira. A ordenação acontece aqui: são poucos estudos por usuário, e a
   * lista deixa de depender de um passo de infraestrutura.
   */
  async listFor(userId: string): Promise<Result<PortfolioStudy[]>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const snapshot = await getDocs(query(this.ref, where('userId', '==', userId)));
      const studies = snapshot.docs.map((d) => {
        const data = d.data();
        const stamp = data['updatedAt'];
        const updatedAt =
          stamp instanceof Timestamp ? DateTime.fromMillisecondsSinceEpoch(stamp.toMillis()) : null;
        return decodeStudy(d.id, data, updatedAt);
      });
      studies.sort(compareStudiesByRecency);
      return ok(studies);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao carregar os estudos salvos: ${firebaseMessage(e)}`));
    }
  }

  /**
   * `updatedAt` é sempre carimbado pelo **servidor**; `createdAt` só na
   * criação.
   */
  async save(userId: string, study: PortfolioStudy): Promise<Result<string>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const data: DocumentData = { ...encodeStudy(userId, study), updatedAt: serverTimestamp() };
      if (study.id === null) {
        data['createdAt'] = serverTimestamp();
        const created = await addDoc(this.ref, data);
        return ok(created.id);
      }
      await updateDoc(doc(this.ref, study.id), data);
      return ok(study.id);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao salvar o estudo: ${firebaseMessage(e)}`));
    }
  }

  /**
   * A conferência de dono é **redundante** com a regra de segurança do
   * Firestore, e deliberadamente: a regra é a barreira que vale, esta produz a
   * mensagem que o usuário entende em vez de um erro de permissão cru.
   */
  async delete(userId: string, id: string): Promise<Result<void>> {
    try {
      const snapshot = await getDoc(doc(this.ref, id));
      if (!snapshot.exists()) return err(new InsufficientData('Estudo não encontrado.'));
      if (snapshot.data()['userId'] !== userId) return err(new InvalidInput('Este estudo pertence a outro usuário.'));
      await deleteDoc(doc(this.ref, id));
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao remover o estudo: ${firebaseMessage(e)}`));
    }
  }
}

/** Documento do modo local: o mesmo do Firestore, com o carimbo em milissegundos. */
interface LocalStudyDocument {
  id: string;
  data: Record<string, unknown>;
  updatedAtMs: number;
  createdAtMs: number;
}

/**
 * Estudos guardados no próprio navegador — o **modo local**, quando o
 * Firebase não está configurado.
 *
 * Mesmo formato de documento e mesmas mensagens do Firestore, de modo que a
 * tela não distingue os dois. A diferença é a que o nome diz: os estudos
 * ficam neste navegador, e não acompanham o usuário para outro aparelho.
 */
export class LocalPortfolioStore implements PortfolioStore {
  constructor(
    private readonly store: KeyValueStore,
    private readonly now: () => number = () => Date.now(),
    private readonly newId: () => string = () => crypto.randomUUID(),
  ) {}

  private key(userId: string): string {
    return `estudos:${userId}`;
  }

  async listFor(userId: string): Promise<Result<PortfolioStudy[]>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    try {
      const docs = (await this.store.get<LocalStudyDocument[]>(this.key(userId))) ?? [];
      const studies = docs.map((d) =>
        decodeStudy(d.id, d.data, DateTime.fromMillisecondsSinceEpoch(d.updatedAtMs)),
      );
      studies.sort(compareStudiesByRecency);
      return ok(studies);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao carregar os estudos salvos: ${firebaseMessage(e)}`));
    }
  }

  async save(userId: string, study: PortfolioStudy): Promise<Result<string>> {
    if (userId.trim().length === 0) return err(new InvalidInput('Usuário não identificado.'));
    const id = study.id ?? this.newId();
    const at = this.now();
    const data = encodeStudy(userId, study);
    try {
      let missing = false;
      await this.store.update<LocalStudyDocument[]>(this.key(userId), (old) => {
        const docs = [...(old ?? [])];
        const index = docs.findIndex((d) => d.id === id);
        if (index < 0) {
          if (study.id !== null) {
            missing = true;
            return docs;
          }
          docs.push({ id, data, updatedAtMs: at, createdAtMs: at });
        } else {
          const previous = docs[index]!;
          // Como no `update` do Firestore: o que não veio fica — a meta
          // omitida inclusive.
          docs[index] = { ...previous, data: { ...previous.data, ...data }, updatedAtMs: at };
        }
        return docs;
      });
      // O `update` do Firestore também falha em documento inexistente.
      if (missing) return err(new ComputationFailure('Falha ao salvar o estudo: documento inexistente.'));
      return ok(id);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao salvar o estudo: ${firebaseMessage(e)}`));
    }
  }

  async delete(userId: string, id: string): Promise<Result<void>> {
    try {
      const docs = (await this.store.get<LocalStudyDocument[]>(this.key(userId))) ?? [];
      if (!docs.some((d) => d.id === id)) return err(new InsufficientData('Estudo não encontrado.'));
      await this.store.update<LocalStudyDocument[]>(this.key(userId), (old) => (old ?? []).filter((d) => d.id !== id));
      return ok(undefined);
    } catch (e) {
      return err(new ComputationFailure(`Falha ao remover o estudo: ${firebaseMessage(e)}`));
    }
  }
}
