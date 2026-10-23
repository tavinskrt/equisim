import { HardDrive, LogIn, Mail } from 'lucide-react';
import { type FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router';

import { AuthCopy } from '../../app/auth';
import { getRuntime } from '../../app/runtime';
import { continueLocally } from '../../app/state/session-store';
import { Button } from '../../ui/button';
import { TextField } from '../../ui/field';
import { AuthLayout, FormError, PasswordField, useReturnTo } from './auth-layout';

/** **Entrar**: e-mail e senha, ou seguir sem conta — com os dados neste navegador. */
export function SignInPage() {
  const navigate = useNavigate();
  const returnTo = useReturnTo();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const auth = getRuntime().auth;
    if (auth === null) return;
    if (email.trim() === '' || password === '') {
      setError('Preencha todos os campos obrigatórios.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await auth.signIn(email.trim(), password);
      navigate(returnTo, { replace: true });
    } catch (err) {
      setError(AuthCopy.signIn(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthLayout
      title="Bem-vindo de volta!"
      subtitle="Acesse sua conta para continuar"
      footer={
        <>
          Não tem uma conta?{' '}
          <Link to="/criar-conta" state={{ from: returnTo }} className="font-semibold text-positive hover:underline">
            Criar conta
          </Link>
        </>
      }
    >
      <form onSubmit={(e) => void submit(e)} className="space-y-4" noValidate>
        <TextField
          label="E-mail"
          type="email"
          autoComplete="email"
          inputMode="email"
          placeholder="seu_email@exemplo.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          leading={<Mail aria-hidden className="size-4" />}
          required
        />
        <PasswordField label="Senha" autoComplete="current-password" placeholder="••••••••" value={password} onChange={(e) => setPassword(e.target.value)} required />
        <div className="-mt-1 text-right">
          <Link to="/recuperar-senha" className="inline-flex min-h-11 items-center text-body-sm font-medium text-positive hover:underline">
            Esqueci a senha
          </Link>
        </div>
        <FormError message={error} />
        <Button type="submit" variant="primary" size="lg" className="w-full" disabled={busy} icon={<LogIn aria-hidden className="size-[18px]" />}>
          {busy ? 'Entrando…' : 'Entrar'}
        </Button>
      </form>
      <div className="mt-6 border-t border-divider pt-5">
        <Button
          variant="ghost"
          className="w-full"
          icon={<HardDrive aria-hidden className="size-[18px]" />}
          onClick={() => {
            continueLocally();
            navigate(returnTo, { replace: true });
          }}
        >
          Seguir sem conta
        </Button>
        <p className="mt-2 text-center text-caption text-fg-3">Os estudos e valuations ficam neste navegador e não acompanham você para outro aparelho.</p>
      </div>
    </AuthLayout>
  );
}
