import { ArrowLeft, ArrowRight, AtSign, CheckCircle2, Mail, User, UserPlus } from 'lucide-react';
import { type FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router';

import { AuthCopy } from '../../app/auth';
import { getRuntime } from '../../app/runtime';
import { PreferencesActions } from '../../app/state/preferences-store';
import { Button } from '../../ui/button';
import { cn } from '../../ui/cn';
import { TextField } from '../../ui/field';
import { toast } from '../../ui/toast';
import { AuthLayout, FormError, PasswordField, StrengthMeter, useReturnTo } from './auth-layout';

/** O piso de tamanho que o campo anuncia ("Mínimo 8 caracteres") — e que agora o formulário cobra. */
export const minPasswordLength = 8;

/**
 * **Criar conta**, em dois passos: os dados da pessoa e a senha. O nome de
 * usuário é o nome de exibição da conta, como no aplicativo Flutter.
 */
export function SignUpPage() {
  const navigate = useNavigate();
  const returnTo = useReturnTo();
  const [step, setStep] = useState<1 | 2>(1);
  const [name, setName] = useState('');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canProceed = name.trim() !== '' && username.trim() !== '' && email.trim() !== '';
  const mismatch = confirm !== '' && confirm !== password;
  const canSubmit = agreed && password.length >= minPasswordLength && confirm === password;

  const next = (e: FormEvent) => {
    e.preventDefault();
    if (!canProceed) {
      setError('Preencha todos os campos obrigatórios.');
      return;
    }
    setError(null);
    setStep(2);
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const auth = getRuntime().auth;
    if (auth === null) return;
    if (!canSubmit) {
      setError('Preencha todos os campos obrigatórios corretamente.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await auth.signUp(email.trim(), password, username.trim());
      const user = auth.current();
      if (user !== null) await PreferencesActions.syncThemeWithAccount(user.uid);
      toast('Conta criada com sucesso!', 'success');
      navigate(returnTo, { replace: true });
    } catch (err) {
      setError(AuthCopy.signUp(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthLayout
      title="Criar nova conta"
      subtitle={step === 1 ? 'Preencha as informações abaixo para criar sua conta.' : 'Use uma senha forte para proteger sua conta.'}
      footer={
        <Link to="/entrar" state={{ from: returnTo }} className="font-semibold text-positive hover:underline">
          Já tenho conta
        </Link>
      }
    >
      <Steps step={step} />
      {step === 1 ? (
        <form onSubmit={next} className="mt-5 space-y-4" noValidate>
          <TextField label="Nome completo" autoComplete="name" placeholder="Seu nome" value={name} onChange={(e) => setName(e.target.value)} leading={<User aria-hidden className="size-4" />} required />
          <TextField
            label="Usuário"
            autoComplete="username"
            placeholder="seu_usuario"
            hint="É o nome que aparece no menu da conta."
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            leading={<AtSign aria-hidden className="size-4" />}
            required
          />
          <TextField
            label="E-mail"
            type="email"
            autoComplete="email"
            inputMode="email"
            placeholder="email@exemplo.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            leading={<Mail aria-hidden className="size-4" />}
            required
          />
          <FormError message={error} />
          <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!canProceed} icon={<ArrowRight aria-hidden className="size-[18px]" />}>
            Continuar
          </Button>
        </form>
      ) : (
        <form onSubmit={(e) => void submit(e)} className="mt-5 space-y-4" noValidate>
          <div>
            <PasswordField label="Crie sua senha" autoComplete="new-password" hint="Mínimo 8 caracteres" value={password} onChange={(e) => setPassword(e.target.value)} required />
            <StrengthMeter password={password} />
          </div>
          <PasswordField
            label="Confirmar senha"
            autoComplete="new-password"
            placeholder="Repita sua senha"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            error={mismatch ? 'As senhas não coincidem.' : null}
            required
          />
          <label className="flex min-h-11 cursor-pointer items-start gap-3 text-body-sm text-fg-2">
            <input
              type="checkbox"
              checked={agreed}
              onChange={(e) => setAgreed(e.target.checked)}
              className="mt-0.5 size-5 shrink-0 cursor-pointer accent-[var(--brand)]"
            />
            <span>
              Concordo com os <strong className="font-semibold text-fg">Termos de Uso</strong> e a <strong className="font-semibold text-fg">Política de Privacidade</strong>{' '}
              do Equisim.
            </span>
          </label>
          <FormError message={error} />
          <div className="flex gap-2">
            <Button type="button" variant="secondary" size="lg" onClick={() => setStep(1)} icon={<ArrowLeft aria-hidden className="size-[18px]" />}>
              Voltar
            </Button>
            <Button type="submit" variant="primary" size="lg" className="flex-1" disabled={!canSubmit || busy} icon={<UserPlus aria-hidden className="size-[18px]" />}>
              {busy ? 'Criando…' : 'Criar minha conta'}
            </Button>
          </div>
        </form>
      )}
    </AuthLayout>
  );
}

function Steps({ step }: { step: 1 | 2 }) {
  const items = [
    { n: 1, label: 'Seus dados' },
    { n: 2, label: 'Senha e segurança' },
  ];
  return (
    <ol className="flex items-center gap-2" aria-label="Etapas do cadastro">
      {items.map((it, i) => (
        <li key={it.n} className="flex flex-1 items-center gap-2" aria-current={step === it.n ? 'step' : undefined}>
          <span
            className={cn(
              'inline-flex size-6 shrink-0 items-center justify-center rounded-full text-caption font-bold',
              step > it.n ? 'bg-brand text-on-brand' : step === it.n ? 'border-2 border-brand text-positive' : 'border border-line text-fg-3',
            )}
          >
            {step > it.n ? <CheckCircle2 aria-hidden className="size-4" /> : it.n}
          </span>
          <span className={cn('text-caption', step === it.n ? 'font-semibold text-fg' : 'text-fg-3')}>{it.label}</span>
          {i === 0 && <span aria-hidden className="h-px flex-1 bg-line" />}
        </li>
      ))}
    </ol>
  );
}
