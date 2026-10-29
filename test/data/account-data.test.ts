import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Um Firestore de mentira, só com o que a exclusão da conta usa: documentos
 * por coleção, a consulta pelo dono, o lote de exclusão e o `deleteDoc`.
 */
const db = vi.hoisted(() => ({
  docs: new Map<string, Array<{ id: string; userId: string }>>(),
  users: new Set<string>(),
  batches: [] as number[],
  failOn: null as string | null,
}));

vi.mock('firebase/firestore', () => ({
  collection: (_fs: unknown, name: string) => ({ name }),
  where: (field: string, _op: string, value: string) => ({ field, value }),
  query: (c: { name: string }, w: { value: string }) => ({ name: c.name, uid: w.value }),
  getDocs: async (q: { name: string; uid: string }) => {
    if (db.failOn === q.name) throw new Error(`permissão negada em ${q.name}`);
    const list = (db.docs.get(q.name) ?? []).filter((d) => d.userId === q.uid);
    return { docs: list.map((d) => ({ ref: { name: q.name, id: d.id } })) };
  },
  writeBatch: () => {
    const pending: Array<{ name: string; id: string }> = [];
    return {
      delete: (ref: { name: string; id: string }) => pending.push(ref),
      commit: async () => {
        db.batches.push(pending.length);
        for (const ref of pending) db.docs.set(ref.name, (db.docs.get(ref.name) ?? []).filter((d) => d.id !== ref.id));
      },
    };
  },
  doc: (_fs: unknown, name: string, id: string) => ({ name, id }),
  deleteDoc: async (ref: { name: string; id: string }) => {
    if (ref.name === 'users') db.users.delete(ref.id);
  },
}));

const { ACCOUNT_COLLECTIONS, deleteAccountData } = await import('../../src/data/persistence/account-data');

const firestore = {} as never;

function seed(name: string, owners: string[]): void {
  db.docs.set(
    name,
    owners.map((userId, i) => ({ id: `${name}-${i}`, userId })),
  );
}

beforeEach(() => {
  db.docs.clear();
  db.users.clear();
  db.batches.length = 0;
  db.failOn = null;
});

describe('deleteAccountData', () => {
  it('apaga os documentos da conta nas três coleções e o users/{uid}, sem tocar nos de outra conta', async () => {
    seed('valuations', ['ana', 'ana', 'bia']);
    seed('portfolios', ['ana', 'bia']);
    seed('backtests', ['ana']);
    db.users.add('ana');
    db.users.add('bia');

    expect(await deleteAccountData(firestore, 'ana')).toBe(4);

    for (const name of ACCOUNT_COLLECTIONS) {
      expect((db.docs.get(name) ?? []).every((d) => d.userId === 'bia')).toBe(true);
    }
    expect(db.docs.get('valuations')).toHaveLength(1);
    expect(db.docs.get('portfolios')).toHaveLength(1);
    expect([...db.users]).toEqual(['bia']);
  });

  it('divide em lotes de até 500 exclusões', async () => {
    seed('valuations', Array.from({ length: 1201 }, () => 'ana'));
    expect(await deleteAccountData(firestore, 'ana')).toBe(1201);
    expect(db.batches).toEqual([500, 500, 201]);
  });

  it('sem nada salvo, ainda apaga o users/{uid}', async () => {
    db.users.add('ana');
    expect(await deleteAccountData(firestore, 'ana')).toBe(0);
    expect(db.users.size).toBe(0);
  });

  it('propaga a falha, e não apaga o users/{uid}', async () => {
    seed('valuations', ['ana']);
    db.users.add('ana');
    db.failOn = 'portfolios';
    await expect(deleteAccountData(firestore, 'ana')).rejects.toThrow('permissão negada em portfolios');
    expect(db.users.has('ana')).toBe(true);
  });

  it('recusa usuário vazio', async () => {
    await expect(deleteAccountData(firestore, ' ')).rejects.toThrow('Usuário não identificado.');
  });
});
