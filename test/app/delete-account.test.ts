import { beforeEach, describe, expect, it, vi } from 'vitest';

/** O que aconteceu, na ordem: é a ordem que protege os dados. */
const calls = vi.hoisted(() => ({
  log: [] as string[],
  reauth: null as Error | null,
  purge: null as Error | null,
}));

vi.mock('firebase/auth', () => ({
  EmailAuthProvider: { credential: (email: string, password: string) => ({ email, password }) },
  reauthenticateWithCredential: async (_user: unknown, credential: { password: string }) => {
    calls.log.push(`reauth:${credential.password}`);
    if (calls.reauth !== null) throw calls.reauth;
  },
  deleteUser: async () => {
    calls.log.push('deleteUser');
  },
}));

vi.mock('../../src/data/persistence/account-data', () => ({
  deleteAccountData: async (_fs: unknown, uid: string) => {
    calls.log.push(`purge:${uid}`);
    if (calls.purge !== null) throw calls.purge;
    return 3;
  },
}));

const { AuthCopy, AuthError, FirebaseAuthGateway } = await import('../../src/app/auth');

const firebaseError = (code: string) => Object.assign(new Error(code), { code: `auth/${code}` });

function gateway(user: { uid: string; email: string | null } | null = { uid: 'ana', email: 'ana@exemplo.com' }) {
  return new FirebaseAuthGateway({ currentUser: user } as never, {} as never);
}

beforeEach(() => {
  calls.log.length = 0;
  calls.reauth = null;
  calls.purge = null;
});

describe('FirebaseAuthGateway.deleteAccount', () => {
  it('confirma a senha, apaga os dados e só então o login', async () => {
    await gateway().deleteAccount('segredo');
    expect(calls.log).toEqual(['reauth:segredo', 'purge:ana', 'deleteUser']);
  });

  it('senha errada não apaga nada', async () => {
    calls.reauth = firebaseError('invalid-credential');
    const error = await gateway()
      .deleteAccount('errada')
      .catch((e: unknown) => e);
    expect(calls.log).toEqual(['reauth:errada']);
    expect(error).toBeInstanceOf(AuthError);
    expect(AuthCopy.deleteAccount(error)).toBe('A senha fornecida está incorreta. Nada foi excluído.');
  });

  it('falha ao apagar os dados mantém o login, e a mensagem diz que a conta segue ativa', async () => {
    calls.purge = new Error('permissão negada.');
    const error = await gateway()
      .deleteAccount('segredo')
      .catch((e: unknown) => e);
    expect(calls.log).toEqual(['reauth:segredo', 'purge:ana']);
    expect((error as InstanceType<typeof AuthError>).code).toBe('data-delete-failed');
    expect(AuthCopy.deleteAccount(error)).toContain('a conta continua ativa');
  });

  it('sem usuário, nada acontece', async () => {
    await expect(gateway(null).deleteAccount('segredo')).rejects.toThrow('Usuário não está autenticado');
    expect(calls.log).toEqual([]);
  });
});
