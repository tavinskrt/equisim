import { Eye, EyeOff, ShieldCheck } from 'lucide-react';
import { type ReactNode, useState } from 'react';
import { Navigate, useLocation } from 'react-router';

import { type PasswordStrength, PasswordRules } from '../../app/auth';
import { useSession } from '../../app/state/session-store';
import { cn } from '../../ui/cn';
import { TextField, type TextFieldProps } from '../../ui/field';
import { Logo } from '../../ui/logo';

/** Para onde voltar depois de entrar: a rota que o portão interceptou, ou o estudo. */
export function useReturnTo(): string {
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from;
  return typeof from === 'string' && from.startsWith('/') && !from.startsWith('//') ? from : '/estudo';
}

/**
 * A moldura das telas de entrada: a marca, o cartão e a nota de conexão.
 * Quem já tem sessão não vê esta tela — vai para onde ia.
 */
export function AuthLayout(props: { title: string; subtitle: ReactNode; children: ReactNode; footer?: ReactNode; allowSignedIn?: boolean }) {
  const status = useSession((s) => s.status);
  const returnTo = useReturnTo();
  if (status === 'signedIn' && props.allowSignedIn !== true) return <Navigate to={returnTo} replace />;
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-canvas px-4 py-10">
      <main className="w-full max-w-[420px]">
        <div className="mb-6 flex flex-col items-center text-center">
          <Logo className="size-11" />
          <p className="mt-3 text-title font-bold tracking-tight text-fg">Equisim</p>
          <p className="text-body-sm text-fg-3">Comparador de Carteiras</p>
        </div>
        <div className="rounded-2xl border border-line bg-surface p-5 shadow-card sm:p-7">
          <h1 className="text-title font-semibold text-fg">{props.title}</h1>
          <p className="mt-1 text-body-sm text-fg-2">{props.subtitle}</p>
          <div className="mt-6">{props.children}</div>
        </div>
        {props.footer !== undefined && <div className="mt-5 text-center text-body-sm text-fg-2">{props.footer}</div>}
        <p className="mt-6 flex items-center justify-center gap-1.5 text-caption text-fg-3">
          <ShieldCheck aria-hidden className="size-3.5" />
          Conexão segura · Dados criptografados
        </p>
      </main>
    </div>
  );
}

/** Campo de senha com o botão de mostrar — rotulado, com alvo de 44 px. */
export function PasswordField(props: Omit<TextFieldProps, 'type' | 'trailing'>) {
  const [visible, setVisible] = useState(false);
  return (
    <TextField
      {...props}
      type={visible ? 'text' : 'password'}
      trailing={
        <button
          type="button"
          onClick={() => setVisible((v) => !v)}
          aria-label={visible ? 'Esconder a senha' : 'Mostrar a senha'}
          aria-pressed={visible}
          className="inline-flex size-11 items-center justify-center text-fg-3 hover:text-fg"
        >
          {visible ? <EyeOff aria-hidden className="size-4" /> : <Eye aria-hidden className="size-4" />}
        </button>
      }
    />
  );
}

const strengthTone: Record<PasswordStrength, string> = {
  empty: 'bg-line',
  weak: 'bg-negative',
  medium: 'bg-caution',
  good: 'bg-positive',
  strong: 'bg-positive',
};

/** A força da senha em quatro segmentos **e** em palavra — a cor nunca está sozinha. */
export function StrengthMeter({ password }: { password: string }) {
  const s = PasswordRules.strength(password);
  const level = PasswordRules.level(s);
  if (s === 'empty') return null;
  return (
    <div className="mt-2" aria-live="polite">
      <div className="flex gap-1" aria-hidden>
        {[1, 2, 3, 4].map((i) => (
          <span key={i} className={cn('h-1 flex-1 rounded-full', i <= level ? strengthTone[s] : 'bg-line')} />
        ))}
      </div>
      <p className="mt-1 text-caption text-fg-2">Senha {PasswordRules.label(s).toLowerCase()}</p>
    </div>
  );
}

/** Mensagem de falha do formulário, anunciada. */
export function FormError({ message }: { message: string | null }) {
  if (message === null) return null;
  return (
    <p role="alert" className="rounded-lg border border-negative/40 bg-negative-surface px-3 py-2 text-body-sm text-fg">
      {message}
    </p>
  );
}
