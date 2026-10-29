import { lazy, type ReactNode, Suspense } from 'react';
import { createBrowserRouter, Link, Navigate, Outlet, useLocation } from 'react-router';

import { useSession } from './app/state/session-store';
import { AppShell } from './features/shell/app-shell';
import { BuilderPage } from './features/study/builder-page';
import { Button } from './ui/button';
import { Card } from './ui/card';
import { EmptyState, Spinner } from './ui/feedback';

// As áreas pesadas vão em pedaços próprios: quem abre o estudo não baixa o
// editor manual, o laboratório de backtest nem o gráfico da Bklit da Meta.
const BacktestPage = lazy(() => import('./features/backtest/backtest-page').then((m) => ({ default: m.BacktestPage })));
const AssetPage = lazy(() => import('./features/asset/asset-page').then((m) => ({ default: m.AssetPage })));
const PlannerPage = lazy(() => import('./features/goal/planner-page').then((m) => ({ default: m.PlannerPage })));
const ManualPage = lazy(() => import('./features/manual/manual-page').then((m) => ({ default: m.ManualPage })));
const ValuationsPage = lazy(() => import('./features/valuations/valuations-page').then((m) => ({ default: m.ValuationsPage })));
const ProfilePage = lazy(() => import('./features/auth/profile-page').then((m) => ({ default: m.ProfilePage })));
const ChangePasswordPage = lazy(() => import('./features/auth/change-password-page').then((m) => ({ default: m.ChangePasswordPage })));
const SignInPage = lazy(() => import('./features/auth/sign-in-page').then((m) => ({ default: m.SignInPage })));
const SignUpPage = lazy(() => import('./features/auth/sign-up-page').then((m) => ({ default: m.SignUpPage })));
const ForgotPasswordPage = lazy(() => import('./features/auth/forgot-password-page').then((m) => ({ default: m.ForgotPasswordPage })));

function Splash() {
  return (
    <div className="flex min-h-[50dvh] items-center justify-center">
      <Spinner className="size-6" label="Carregando" />
    </div>
  );
}

const page = (node: ReactNode) => <Suspense fallback={<Splash />}>{node}</Suspense>;

/**
 * O portão da sessão: enquanto o Firebase restaura a sessão, espera; sem
 * sessão, vai para a entrada lembrando para onde ia; com sessão — ou no modo
 * local —, abre a área pedida.
 */
function RequireSession() {
  const status = useSession((s) => s.status);
  const location = useLocation();
  if (status === 'loading') return <Splash />;
  if (status === 'signedOut') {
    return <Navigate to="/entrar" replace state={{ from: `${location.pathname}${location.search}` }} />;
  }
  return <Outlet />;
}

function NotFound() {
  return (
    <Card>
      <EmptyState
        title="Página não encontrada"
        message="O endereço não corresponde a nenhuma área do Equisim."
        action={
          <Button asChild variant="secondary">
            <Link to="/estudo">Ir ao estudo</Link>
          </Button>
        }
      />
    </Card>
  );
}

export const router = createBrowserRouter(
  [
    { path: '/entrar', element: page(<SignInPage />) },
    { path: '/criar-conta', element: page(<SignUpPage />) },
    { path: '/recuperar-senha', element: page(<ForgotPasswordPage />) },
    {
      element: <RequireSession />,
      children: [
        {
          element: <AppShell />,
          children: [
            { index: true, element: <Navigate to="/estudo" replace /> },
            { path: '/estudo', element: <BuilderPage /> },
            { path: '/meta', element: page(<PlannerPage />) },
            { path: '/backtest', element: page(<BacktestPage />) },
            { path: '/valuations', element: page(<ValuationsPage />) },
            { path: '/ativo/:ticker', element: page(<AssetPage />) },
            { path: '/ativo/:ticker/simular', element: page(<ManualPage />) },
            { path: '/perfil', element: page(<ProfilePage />) },
            { path: '/perfil/senha', element: page(<ChangePasswordPage />) },
            { path: '*', element: <NotFound /> },
          ],
        },
      ],
    },
  ],
  { basename: import.meta.env.BASE_URL.replace(/\/$/, '') || '/' },
);
