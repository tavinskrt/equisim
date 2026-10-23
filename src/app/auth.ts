import { type FirebaseApp, initializeApp } from 'firebase/app';
import {
  type Auth,
  createUserWithEmailAndPassword,
  deleteUser,
  EmailAuthProvider,
  getAuth,
  onAuthStateChanged,
  reauthenticateWithCredential,
  reload,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signOut,
  updatePassword,
  updateProfile,
  type User,
  verifyBeforeUpdateEmail,
} from 'firebase/auth';
import { doc, type Firestore, getDoc, getFirestore, setDoc } from 'firebase/firestore';

import { firebaseWebOptions } from './firebase-options';

/** O usuário autenticado, só com o que a tela usa. */
export interface AuthUser {
  readonly uid: string;
  readonly email: string | null;
  readonly displayName: string | null;
}

/** Falha de autenticação, com o código do Firebase para a mensagem. */
export class AuthError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

/**
 * A porta da autenticação.
 *
 * Existe para que a sessão não dependa do Firebase em si: o teste monta uma
 * porta falsa, e o **modo local** — sem Firebase configurado, ou com ele fora
 * do ar — é a ausência da porta, e não um caminho de exceção espalhado.
 */
export interface AuthGateway {
  /**
   * O usuário já restaurado, **síncrono**. O fluxo de [onChange] só emite
   * depois da assinatura; quem perguntar nesse intervalo — o botão de salvar
   * era esse caso no aplicativo Flutter — precisa da resposta certa.
   */
  current(): AuthUser | null;
  onChange(listener: (user: AuthUser | null) => void): () => void;
  signIn(email: string, password: string): Promise<void>;
  signUp(email: string, password: string, displayName: string): Promise<void>;
  sendPasswordReset(email: string): Promise<void>;
  signOut(): Promise<void>;
  changePassword(current: string, next: string): Promise<void>;
  updateProfile(args: { displayName: string; email: string }): Promise<void>;
  deleteAccount(): Promise<void>;
  /** A preferência de tema guardada na nuvem: `true` claro, `false` escuro, `null` nenhuma. */
  readThemePreference(uid: string): Promise<boolean | null>;
  writeThemePreference(uid: string, isLight: boolean): Promise<void>;
}

/** O que a inicialização do Firebase entrega, ou por que não entregou. */
export type FirebaseRuntime =
  | { readonly ok: true; readonly app: FirebaseApp; readonly auth: Auth; readonly firestore: Firestore }
  | { readonly ok: false; readonly reason: string };

/**
 * Inicializa o Firebase. **Falha não derruba o aplicativo**: vira modo local,
 * com os dados no navegador, e a tela diz isso.
 *
 * `VITE_EQUISIM_LOCAL=true` força o modo local — útil para desenvolver sem
 * rede ou sem conta.
 */
export function initFirebase(env: { VITE_EQUISIM_LOCAL?: string } = {}): FirebaseRuntime {
  if (env.VITE_EQUISIM_LOCAL === 'true') {
    return { ok: false, reason: 'Modo local forçado por VITE_EQUISIM_LOCAL.' };
  }
  try {
    const app = initializeApp(firebaseWebOptions);
    return { ok: true, app, auth: getAuth(app), firestore: getFirestore(app) };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : String(e) };
  }
}

const userOf = (u: User | null): AuthUser | null =>
  u === null ? null : { uid: u.uid, email: u.email, displayName: u.displayName };

function wrap(e: unknown): AuthError {
  if (typeof e === 'object' && e !== null && 'code' in e) {
    const code = String((e as { code: unknown }).code).replace(/^auth\//, '');
    return new AuthError(code, e instanceof Error ? e.message : code);
  }
  return new AuthError('unknown', e instanceof Error ? e.message : String(e));
}

/** A coleção da preferência de tema, como no aplicativo Flutter. */
const themeKey = 'isLightMode';

/** A porta sobre o Firebase Auth e o documento `users/{uid}`. */
export class FirebaseAuthGateway implements AuthGateway {
  constructor(
    private readonly auth: Auth,
    private readonly firestore: Firestore,
  ) {}

  current(): AuthUser | null {
    return userOf(this.auth.currentUser);
  }

  onChange(listener: (user: AuthUser | null) => void): () => void {
    return onAuthStateChanged(this.auth, (u) => listener(userOf(u)));
  }

  async signIn(email: string, password: string): Promise<void> {
    try {
      await signInWithEmailAndPassword(this.auth, email, password);
    } catch (e) {
      throw wrap(e);
    }
  }

  async signUp(email: string, password: string, displayName: string): Promise<void> {
    try {
      const credential = await createUserWithEmailAndPassword(this.auth, email, password);
      await updateProfile(credential.user, { displayName });
    } catch (e) {
      throw wrap(e);
    }
  }

  async sendPasswordReset(email: string): Promise<void> {
    try {
      await sendPasswordResetEmail(this.auth, email);
    } catch (e) {
      throw wrap(e);
    }
  }

  async signOut(): Promise<void> {
    await signOut(this.auth);
  }

  private requireUser(): User {
    const user = this.auth.currentUser;
    if (user === null) throw new AuthError('no-user', 'Usuário não está autenticado no momento.');
    return user;
  }

  async changePassword(current: string, next: string): Promise<void> {
    const user = this.requireUser();
    if (user.email === null) throw new AuthError('no-email', 'E-mail do usuário não pôde ser localizado.');
    try {
      // Reautenticar é exigência do Firebase para troca de dado sensível.
      await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email, current));
      await updatePassword(user, next);
    } catch (e) {
      throw wrap(e);
    }
  }

  async updateProfile(args: { displayName: string; email: string }): Promise<void> {
    const user = this.requireUser();
    try {
      if (args.displayName !== user.displayName) await updateProfile(user, { displayName: args.displayName });
      if (args.email !== user.email) await verifyBeforeUpdateEmail(user, args.email);
      await reload(user);
    } catch (e) {
      throw wrap(e);
    }
  }

  async deleteAccount(): Promise<void> {
    try {
      await deleteUser(this.requireUser());
    } catch (e) {
      throw wrap(e);
    }
  }

  async readThemePreference(uid: string): Promise<boolean | null> {
    const snap = await getDoc(doc(this.firestore, 'users', uid));
    const value: unknown = snap.exists() ? snap.data()[themeKey] : undefined;
    return typeof value === 'boolean' ? value : null;
  }

  async writeThemePreference(uid: string, isLight: boolean): Promise<void> {
    await setDoc(doc(this.firestore, 'users', uid), { [themeKey]: isLight }, { merge: true });
  }
}

/**
 * As mensagens das falhas de autenticação, em português — as do aplicativo
 * Flutter, por código do Firebase.
 */
export const AuthCopy = {
  signIn(e: unknown): string {
    const code = e instanceof AuthError ? e.code : 'unknown';
    switch (code) {
      case 'user-not-found':
        return 'Nenhum usuário correspondente a este e-mail foi encontrado.';
      case 'wrong-password':
        return 'A senha fornecida está incorreta.';
      case 'invalid-credential':
        return 'Credenciais de acesso inválidas.';
      case 'invalid-email':
        return 'O formato do e-mail inserido é inválido.';
      case 'too-many-requests':
        return 'Muitas tentativas seguidas. Espere alguns minutos e tente de novo.';
      case 'network-request-failed':
        return 'Sem conexão com o servidor de autenticação.';
      default:
        return `Erro na autenticação: ${messageOf(e)}`;
    }
  },

  signUp(e: unknown): string {
    const code = e instanceof AuthError ? e.code : 'unknown';
    switch (code) {
      case 'weak-password':
        return 'A senha fornecida é considerada muito fraca pelo servidor.';
      case 'email-already-in-use':
        return 'Já existe uma conta ativa cadastrada com este e-mail.';
      case 'invalid-email':
        return 'O formato do e-mail inserido é inválido.';
      default:
        return `Erro no cadastro: ${messageOf(e)}`;
    }
  },

  reset(e: unknown): string {
    const code = e instanceof AuthError ? e.code : 'unknown';
    switch (code) {
      case 'user-not-found':
        return 'Nenhum usuário correspondente a este e-mail foi encontrado.';
      case 'invalid-email':
        return 'O formato do e-mail inserido é inválido.';
      default:
        return `Erro na autenticação: ${messageOf(e)}`;
    }
  },

  changePassword(e: unknown): string {
    const code = e instanceof AuthError ? e.code : 'unknown';
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'A senha atual fornecida está incorreta.';
      case 'requires-recent-login':
        return 'Para realizar esta ação sensível, é necessário fazer login novamente.';
      case 'weak-password':
        return 'A nova senha informada é considerada muito fraca pelo servidor.';
      case 'no-user':
      case 'no-email':
        return messageOf(e);
      default:
        return `Erro do Firebase: ${messageOf(e)}`;
    }
  },

  profile(e: unknown): string {
    const code = e instanceof AuthError ? e.code : 'unknown';
    switch (code) {
      case 'requires-recent-login':
        return 'Esta ação é sensível e exige login recente. Por segurança, faça logout e entre novamente para alterar seu e-mail.';
      case 'email-already-in-use':
        return 'Este endereço de e-mail já está em uso por outro usuário.';
      case 'invalid-email':
        return 'O formato de e-mail informado é inválido.';
      default:
        return `Falha no Firebase Auth: ${messageOf(e)}`;
    }
  },

  deleteAccount(e: unknown): string {
    const code = e instanceof AuthError ? e.code : 'unknown';
    if (code === 'requires-recent-login') {
      return 'Esta operação é sensível e exige autenticação recente. Faça logout e entre novamente para excluir sua conta.';
    }
    return `Erro ao excluir conta: ${messageOf(e)}`;
  },
};

function messageOf(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Força da senha, pela mesma régua do aplicativo Flutter. */
export type PasswordStrength = 'empty' | 'weak' | 'medium' | 'good' | 'strong';

export const PasswordRules = {
  symbol: /[!@#$%^&*(),.?":{}|<>]/,

  strength(pass: string): PasswordStrength {
    if (pass.length === 0) return 'empty';
    if (pass.length < 6) return 'weak';
    if (pass.length < 10 || !/[0-9]/.test(pass)) return 'medium';
    if (!PasswordRules.symbol.test(pass)) return 'good';
    return 'strong';
  },

  level(s: PasswordStrength): number {
    return { empty: 0, weak: 1, medium: 2, good: 3, strong: 4 }[s];
  },

  label(s: PasswordStrength): string {
    return { empty: '', weak: 'Fraca', medium: 'Média', good: 'Boa', strong: 'Forte' }[s];
  },

  /** O checklist de requisitos da troca de senha. */
  checklist(pass: string): { length: boolean; number: boolean; uppercase: boolean; symbol: boolean } {
    return {
      length: pass.length >= 8,
      number: /[0-9]/.test(pass),
      uppercase: /[A-Z]/.test(pass),
      symbol: PasswordRules.symbol.test(pass),
    };
  },
};
