import { ArrowLeft, Check, CircleCheck, KeyRound, X } from 'lucide-react';
import { type FormEvent, useState } from 'react';
import { Link } from 'react-router';

import { AuthCopy, PasswordRules } from '../../app/auth';
import { getRuntime } from '../../app/runtime';
import { Button } from '../../ui/button';
import { Card, Panel } from '../../ui/card';
import { cn } from '../../ui/cn';
import { FormError, PasswordField, StrengthMeter } from './auth-layout';

/**
 * **Trocar senha**: a senha atual (o Firebase exige reautenticação), a nova
 * com os requisitos à vista, e a confirmação. Mesma régua do aplicativo
 * Flutter: atual com 6 ou mais, nova pelo menos "média", e as duas iguais.
 */
export function ChangePasswordPage() {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const checks = PasswordRules.checklist(next);
  const matches = confirm !== '' && next === confirm;
  const canSubmit = current.length >= 6 && PasswordRules.level(PasswordRules.strength(next)) >= PasswordRules.level('medium') && matches;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const auth = getRuntime().auth;
    if (auth === null || !canSubmit) return;
    setBusy(true);
    setError(null);
    try {
      await auth.changePassword(current, next);
      setDone(true);
    } catch (err) {
      setError(AuthCopy.changePassword(err));
    } finally {
      setBusy(false);
    }
  };

  const back = (
    <Link to="/perfil" className="inline-flex min-h-11 items-center gap-1.5 text-body-sm font-medium text-positive hover:underline">
      <ArrowLeft aria-hidden className="size-4" />
      Voltar ao perfil
    </Link>
  );

  if (done) {
    return (
      <div className="mx-auto max-w-xl space-y-4">
        {back}
        <Card className="p-6 text-center" role="status">
          <CircleCheck aria-hidden className="mx-auto size-10 text-positive" />
          <h1 className="mt-3 text-title font-semibold text-fg">Senha alterada!</h1>
          <p className="mt-1 text-body-sm text-fg-2">Sua senha foi atualizada com sucesso. Use-a no próximo acesso.</p>
        </Card>
      </div>
    );
  }

  const requirements = [
    { met: checks.length, label: 'Mínimo 8 caracteres' },
    { met: checks.number, label: 'Pelo menos um número' },
    { met: checks.uppercase, label: 'Pelo menos uma letra maiúscula' },
    { met: checks.symbol, label: 'Pelo menos um caractere especial (!@#$…)' },
  ];

  return (
    <div className="mx-auto max-w-xl space-y-4">
      {back}
      <div>
        <h1 className="text-title font-semibold text-fg">Trocar senha</h1>
        <p className="mt-1 text-body-sm text-fg-2">Sua senha deve ter pelo menos 8 caracteres e combinar letras, números e símbolos.</p>
      </div>
      <Panel title="Segurança da conta">
        <form onSubmit={(e) => void submit(e)} className="space-y-4" noValidate>
          <PasswordField label="Senha atual" autoComplete="current-password" placeholder="••••••••" value={current} onChange={(e) => setCurrent(e.target.value)} />
          <div>
            <PasswordField label="Nova senha" autoComplete="new-password" placeholder="Crie uma nova senha" value={next} onChange={(e) => setNext(e.target.value)} />
            <StrengthMeter password={next} />
          </div>
          <div className="rounded-lg border border-line bg-sunken p-3">
            <p className="eyebrow">Requisitos</p>
            <ul className="mt-2 space-y-1.5">
              {requirements.map((r) => (
                <li key={r.label} className={cn('flex items-center gap-2 text-body-sm', r.met ? 'text-fg' : 'text-fg-2')}>
                  {r.met ? <Check aria-hidden className="size-4 text-positive" /> : <X aria-hidden className="size-4 text-fg-3" />}
                  {r.label}
                  <span className="sr-only">{r.met ? ' — cumprido' : ' — pendente'}</span>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <PasswordField label="Confirmar nova senha" autoComplete="new-password" placeholder="Repita a nova senha" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
            {confirm !== '' && (
              <p className={cn('mt-1.5 flex items-center gap-1.5 text-caption', matches ? 'text-positive' : 'text-negative')} aria-live="polite">
                {matches ? <Check aria-hidden className="size-3.5" /> : <X aria-hidden className="size-3.5" />}
                {matches ? 'Senhas coincidem' : 'Senhas não coincidem'}
              </p>
            )}
          </div>
          <FormError message={error} />
          <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!canSubmit || busy} icon={<KeyRound aria-hidden className="size-[18px]" />}>
            {busy ? 'Trocando…' : 'Trocar senha'}
          </Button>
        </form>
        <p className="mt-4 text-center text-body-sm text-fg-2">
          Esqueceu sua senha?{' '}
          <Link to="/recuperar-senha" className="font-semibold text-positive hover:underline">
            Recuperar por e-mail
          </Link>
        </p>
      </Panel>
    </div>
  );
}
