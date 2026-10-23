import { AtSign, ChevronRight, KeyRound, LogOut, Mail, Trash2 } from 'lucide-react';
import { type FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router';

import { AuthCopy } from '../../app/auth';
import { getRuntime } from '../../app/runtime';
import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { signOutSession, useSession } from '../../app/state/session-store';
import { Badge } from '../../ui/badge';
import { Banner } from '../../ui/banner';
import { Button } from '../../ui/button';
import { Card, Panel } from '../../ui/card';
import { ConfirmDialog } from '../../ui/dialog';
import { TextField } from '../../ui/field';
import { Segmented } from '../../ui/segmented';
import { toast } from '../../ui/toast';
import { FormError } from './auth-layout';

/**
 * **Meu perfil**: o nome e o e-mail da conta, as preferências, a troca de
 * senha e a exclusão. No modo local não há conta a editar — a tela diz onde
 * os dados ficam e oferece entrar.
 */
export function ProfilePage() {
  const user = useSession((s) => s.user);
  const local = useSession((s) => s.local);
  const navigate = useNavigate();
  const hasAuth = getRuntime().auth !== null;

  if (local || user === null) {
    return (
      <div className="mx-auto max-w-2xl space-y-4">
        <h1 className="text-title font-semibold text-fg">Meu perfil</h1>
        <Card className="p-5">
          <p className="text-body text-fg">Você está sem conta: os estudos e os valuations ficam neste navegador.</p>
          <p className="mt-1 text-body-sm text-fg-2">Eles não acompanham você para outro aparelho, e somem se os dados do site forem apagados.</p>
          {hasAuth && (
            <Button className="mt-4" variant="primary" onClick={() => void signOutSession().then(() => navigate('/entrar'))}>
              Entrar com uma conta
            </Button>
          )}
        </Card>
        <PreferencesCard />
      </div>
    );
  }

  const initial = (user.displayName ?? user.email ?? '?').trim().charAt(0).toUpperCase() || '?';
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <h1 className="text-title font-semibold text-fg">Meu perfil</h1>
      <Card className="flex items-center gap-4 p-5">
        <span aria-hidden className="flex size-14 shrink-0 items-center justify-center rounded-full border border-brand/40 bg-brand-surface text-title font-semibold text-positive">
          {initial}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-title-sm font-semibold text-fg">{user.displayName ?? 'Sem nome de usuário'}</p>
          <p className="truncate text-body-sm text-fg-2">{user.email}</p>
        </div>
        <Badge tone="positive">Membro ativo</Badge>
      </Card>
      <AccountInfo key={user.uid} displayName={user.displayName ?? ''} email={user.email ?? ''} />
      <PreferencesCard />
      <Panel title="Segurança">
        <Link
          to="/perfil/senha"
          className="-mx-2 flex min-h-14 items-center gap-3 rounded-lg px-2 text-left transition-colors hover:bg-sunken"
        >
          <KeyRound aria-hidden className="size-5 text-fg-2" />
          <span className="flex-1">
            <span className="block text-body font-medium text-fg">Trocar senha</span>
            <span className="block text-caption text-fg-2">Altere sua senha de acesso</span>
          </span>
          <ChevronRight aria-hidden className="size-4 text-fg-3" />
        </Link>
        <Button className="mt-3" variant="ghost" icon={<LogOut aria-hidden className="size-4" />} onClick={() => void signOutSession().then(() => navigate('/entrar'))}>
          Sair
        </Button>
      </Panel>
      <DeleteAccount />
    </div>
  );
}

function AccountInfo(props: { displayName: string; email: string }) {
  const [displayName, setDisplayName] = useState(props.displayName);
  const [email, setEmail] = useState(props.email);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const dirty = displayName !== props.displayName || email !== props.email;

  const save = async (e: FormEvent) => {
    e.preventDefault();
    const auth = getRuntime().auth;
    if (auth === null) return;
    if (displayName.trim() === '') return setError('O nome de usuário não pode estar vazio.');
    if (email.trim() === '') return setError('O e-mail não pode estar vazio.');
    setBusy(true);
    setError(null);
    try {
      await auth.updateProfile({ displayName: displayName.trim(), email: email.trim() });
      // A troca de nome não dispara o observador de sessão do Firebase: a
      // sessão local é atualizada à mão, para o menu da conta acompanhar.
      const user = useSession.getState().user;
      if (user !== null) useSession.setState({ user: { ...user, displayName: displayName.trim() } });
      toast(
        email.trim() !== props.email
          ? 'Informações salvas. Enviamos um link ao novo e-mail: a troca vale depois que você confirmar por lá.'
          : 'Informações salvas com sucesso!',
        'success',
      );
    } catch (err) {
      setError(AuthCopy.profile(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Panel title="Informações da conta">
      <form onSubmit={(e) => void save(e)} className="space-y-4" noValidate>
        <TextField label="Nome de usuário" autoComplete="username" value={displayName} onChange={(e) => setDisplayName(e.target.value)} leading={<AtSign aria-hidden className="size-4" />} />
        <TextField
          label="E-mail"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          leading={<Mail aria-hidden className="size-4" />}
          hint="Trocar o e-mail manda um link de confirmação ao endereço novo."
        />
        <FormError message={error} />
        <div className="flex flex-wrap gap-2">
          <Button type="submit" variant="primary" disabled={!dirty || busy}>
            {busy ? 'Salvando…' : 'Salvar alterações'}
          </Button>
          {dirty && (
            <Button
              type="button"
              variant="ghost"
              onClick={() => {
                setDisplayName(props.displayName);
                setEmail(props.email);
                setError(null);
              }}
            >
              Cancelar
            </Button>
          )}
        </div>
      </form>
    </Panel>
  );
}

function PreferencesCard() {
  const theme = usePreferences((s) => s.theme);
  const mode = usePreferences((s) => s.mode);
  return (
    <Panel title="Preferências" subtitle="Valem neste navegador; com conta, o tema acompanha você.">
      <div className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-body-sm text-fg-2">Tema</p>
          <Segmented
            label="Tema"
            value={theme}
            onChange={PreferencesActions.setTheme}
            options={[
              { value: 'dark', label: 'Escuro' },
              { value: 'light', label: 'Claro' },
            ]}
          />
        </div>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-body-sm text-fg-2">Profundidade da interface</p>
            <p className="text-caption text-fg-3">O Completo mostra o modelo, as taxas e as métricas todas. Os números são os mesmos.</p>
          </div>
          <Segmented
            label="Profundidade da interface"
            value={mode}
            onChange={PreferencesActions.setMode}
            options={[
              { value: 'guided', label: 'Essencial' },
              { value: 'analyst', label: 'Completo' },
            ]}
          />
        </div>
      </div>
    </Panel>
  );
}

function DeleteAccount() {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const remove = async () => {
    const auth = getRuntime().auth;
    if (auth === null) return;
    setBusy(true);
    setError(null);
    try {
      await auth.deleteAccount();
      setOpen(false);
      toast('Sua conta foi excluída com sucesso.', 'success');
      navigate('/entrar', { replace: true });
    } catch (err) {
      setOpen(false);
      setError(AuthCopy.deleteAccount(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Panel title="Excluir conta" subtitle="Definitivo: não há como desfazer.">
      {error !== null && (
        <Banner tone="negative" className="mb-3">
          {error}
        </Banner>
      )}
      <Button variant="danger" icon={<Trash2 aria-hidden className="size-4" />} onClick={() => setOpen(true)}>
        Excluir conta
      </Button>
      <ConfirmDialog
        open={open}
        onOpenChange={setOpen}
        title="Excluir a conta?"
        description="Esta ação é definitiva: a conta deixa de existir, e você perde o acesso aos estudos e valuations salvos nela. Deseja mesmo prosseguir?"
        confirmLabel="Excluir"
        busy={busy}
        onConfirm={() => void remove()}
      />
    </Panel>
  );
}
