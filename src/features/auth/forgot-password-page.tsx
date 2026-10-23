import { ArrowLeft, Mail, MailCheck, Send } from 'lucide-react';
import { type FormEvent, useState } from 'react';
import { Link } from 'react-router';

import { AuthCopy } from '../../app/auth';
import { getRuntime } from '../../app/runtime';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { TextField } from '../../ui/field';
import { AuthLayout, FormError } from './auth-layout';

/**
 * **Recuperar senha**: o Firebase manda o link ao e-mail. A tela abre também
 * com sessão — a troca de senha do perfil aponta para cá.
 */
export function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const auth = getRuntime().auth;
    if (auth === null) return;
    if (email.trim() === '') {
      setError('Preencha o campo de e-mail.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await auth.sendPasswordReset(email.trim());
      setSentTo(email.trim());
    } catch (err) {
      setError(AuthCopy.reset(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthLayout
      allowSignedIn
      title="Recuperar senha"
      subtitle="Digite seu e-mail cadastrado e enviaremos um link de recuperação para ele."
      footer={
        <Link to="/entrar" className="inline-flex min-h-11 items-center gap-1.5 font-semibold text-positive hover:underline">
          <ArrowLeft aria-hidden className="size-4" />
          Voltar
        </Link>
      }
    >
      {sentTo !== null ? (
        <Banner tone="positive" icon={<MailCheck aria-hidden className="mt-0.5 size-4 shrink-0" />} live>
          Link de recuperação enviado para o e-mail: {sentTo}. O link de recuperação expira em 30 minutos e só pode ser usado uma vez.
        </Banner>
      ) : (
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
            hint="O link de recuperação expira em 30 minutos e só pode ser usado uma vez."
            required
          />
          <FormError message={error} />
          <Button type="submit" variant="primary" size="lg" className="w-full" disabled={busy} icon={<Send aria-hidden className="size-[18px]" />}>
            {busy ? 'Enviando…' : 'Enviar link de recuperação'}
          </Button>
        </form>
      )}
    </AuthLayout>
  );
}
