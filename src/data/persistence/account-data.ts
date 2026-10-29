import { collection, deleteDoc, doc, type Firestore, getDocs, query, where, writeBatch } from 'firebase/firestore';

/**
 * As coleções em que um documento é do usuário pelo campo `userId`: os
 * valuations confirmados, os estudos e os estudos do escopo anterior, que a
 * aplicação não grava mais mas continuam no banco (ver `firestore.rules`).
 */
export const ACCOUNT_COLLECTIONS = ['valuations', 'portfolios', 'backtests'] as const;

/** Teto de operações de um lote de escrita do Firestore. */
const BATCH_LIMIT = 500;

/**
 * Apaga tudo o que a conta [uid] tem no Firestore: os documentos das
 * [ACCOUNT_COLLECTIONS] e o documento `users/{uid}` (a preferência de tema).
 * Devolve quantos documentos das coleções saíram.
 *
 * A consulta é pelo dono, e não pela lista que a tela mostra: a listagem
 * descarta documento ilegível, e um documento ilegível também é dado da
 * pessoa. Precisa rodar **antes** de apagar o login, porque sem ele as regras
 * de segurança recusam tudo.
 *
 * Não é atômico entre coleções. Uma falha no meio deixa parte dos dados, e a
 * conta continua de pé: repetir a exclusão apaga o resto.
 */
export async function deleteAccountData(firestore: Firestore, uid: string): Promise<number> {
  if (uid.trim().length === 0) throw new Error('Usuário não identificado.');
  let removed = 0;
  for (const name of ACCOUNT_COLLECTIONS) {
    const snapshot = await getDocs(query(collection(firestore, name), where('userId', '==', uid)));
    for (let start = 0; start < snapshot.docs.length; start += BATCH_LIMIT) {
      const batch = writeBatch(firestore);
      for (const d of snapshot.docs.slice(start, start + BATCH_LIMIT)) batch.delete(d.ref);
      await batch.commit();
    }
    removed += snapshot.docs.length;
  }
  await deleteDoc(doc(firestore, 'users', uid));
  return removed;
}
