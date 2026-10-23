import { LogIn, LogOut, Moon, ScrollText, Sun, User } from 'lucide-react';
import { useNavigate } from 'react-router';

import { PreferencesActions, usePreferences } from '../../app/state/preferences-store';
import { signOutSession, useSession } from '../../app/state/session-store';
import { getRuntime } from '../../app/runtime';
import { auditEnabled } from '../../audit/audit-bus';
import { AuditRoutes } from '../../audit/audit-routes';
import { Menu, MenuContent, MenuItem, MenuLabel, MenuSeparator, MenuTrigger } from '../../ui/menu';

/** O menu da conta: perfil, tema, painel de logs e sair — o mesmo do aplicativo Flutter. */
export function AccountMenu() {
  const user = useSession((s) => s.user);
  const local = useSession((s) => s.local);
  const theme = usePreferences((s) => s.theme);
  const navigate = useNavigate();
  const hasAuth = getRuntime().auth !== null;
  const initial = (user?.displayName ?? user?.email ?? '?').trim().charAt(0).toUpperCase() || '?';

  return (
    <Menu>
      <MenuTrigger asChild>
        <button
          type="button"
          aria-label="Conta e preferências"
          className="inline-flex size-11 items-center justify-center rounded-full"
        >
          <span className="flex size-8 items-center justify-center rounded-full border border-brand/40 bg-brand-surface text-body-sm font-semibold text-positive">
            {local ? <User aria-hidden className="size-4" /> : initial}
          </span>
        </button>
      </MenuTrigger>
      <MenuContent>
        <MenuLabel>
          {local ? 'Sem conta — dados neste navegador' : (user?.displayName ?? user?.email ?? 'Conta')}
        </MenuLabel>
        {!local && (
          <MenuItem icon={<User />} onSelect={() => navigate('/perfil')}>
            Meu perfil
          </MenuItem>
        )}
        <MenuItem
          icon={theme === 'dark' ? <Sun /> : <Moon />}
          onSelect={() => PreferencesActions.setTheme(theme === 'dark' ? 'light' : 'dark')}
        >
          {theme === 'dark' ? 'Modo claro' : 'Modo escuro'}
        </MenuItem>
        {auditEnabled() && (
          <MenuItem icon={<ScrollText />} onSelect={() => AuditRoutes.openInNewWindow()}>
            Abrir Painel de Logs de Cálculo
          </MenuItem>
        )}
        <MenuSeparator />
        {local && hasAuth ? (
          <MenuItem icon={<LogIn />} onSelect={() => void signOutSession().then(() => navigate('/entrar'))}>
            Entrar com uma conta
          </MenuItem>
        ) : !local ? (
          <MenuItem icon={<LogOut />} tone="danger" onSelect={() => void signOutSession().then(() => navigate('/entrar'))}>
            Sair
          </MenuItem>
        ) : null}
      </MenuContent>
    </Menu>
  );
}
