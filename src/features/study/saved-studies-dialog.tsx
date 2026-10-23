import { FolderX, Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';

import { Fmt } from '../../copy';
import { StudyActions, useStudy } from '../../app/state/study-store';
import type { PortfolioStudy } from '../../data/persistence/portfolio-study';
import { Button, IconButton } from '../../ui/button';
import { ConfirmDialog, Dialog } from '../../ui/dialog';
import { EmptyState, Spinner } from '../../ui/feedback';
import { Banner } from '../../ui/banner';

/**
 * Os estudos gravados. Salvar sem poder reabrir não resolveria o problema que
 * motivou a funcionalidade — remontar carteiras de nove ativos a cada sessão.
 */
export function SavedStudiesDialog(props: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const saved = useStudy((s) => s.saved);
  const openId = useStudy((s) => s.study.id);
  const [toDelete, setToDelete] = useState<PortfolioStudy | null>(null);
  const [busy, setBusy] = useState(false);

  const close = () => props.onOpenChange(false);

  return (
    <>
      <Dialog
        open={props.open}
        onOpenChange={props.onOpenChange}
        title="Estudos salvos"
        description="Abrir recarrega as duas carteiras e a meta."
        footer={
          <Button
            icon={<Plus aria-hidden className="size-4" />}
            onClick={() => {
              StudyActions.startNew();
              close();
            }}
          >
            Novo estudo
          </Button>
        }
      >
        {saved.status === 'error' && (
          <Banner tone="negative" title="Não foi possível listar" className="mb-3">
            {saved.error}
          </Banner>
        )}
        {saved.status === 'loading' && saved.studies.length === 0 ? (
          <div className="flex justify-center py-8">
            <Spinner label="Carregando os estudos" />
          </div>
        ) : saved.studies.length === 0 && saved.status !== 'error' ? (
          <EmptyState
            icon={<FolderX className="size-5" />}
            title="Nenhum estudo salvo"
            message="Monte as carteiras e use “Salvar” para guardar este estudo."
          />
        ) : (
          <ul className="-mx-2 divide-y divide-divider">
            {saved.studies.map((s) => (
              <li key={s.id ?? s.name} className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => {
                    StudyActions.load(s);
                    close();
                  }}
                  className="min-h-14 min-w-0 flex-1 rounded-lg px-2 py-2 text-left hover:bg-sunken"
                >
                  <span className="flex items-center gap-2">
                    <span className="truncate text-body-sm font-semibold text-fg">{s.name || 'Sem nome'}</span>
                    {s.id !== null && s.id === openId && <span className="text-caption text-positive">aberto</span>}
                  </span>
                  <span className="mt-0.5 block truncate text-caption text-fg-3">
                    {s.principal.length} na Principal · {s.reserve.length} na Reserva
                    {s.updatedAt !== null && ` · ${Fmt.date(s.updatedAt)}`}
                  </span>
                </button>
                <IconButton label={`Excluir “${s.name}”`} tone="danger" onClick={() => setToDelete(s)}>
                  <Trash2 aria-hidden className="size-4" />
                </IconButton>
              </li>
            ))}
          </ul>
        )}
      </Dialog>
      <ConfirmDialog
        open={toDelete !== null}
        onOpenChange={(o) => !o && setToDelete(null)}
        title="Excluir estudo"
        description={`“${toDelete?.name ?? ''}” será removido definitivamente.`}
        confirmLabel="Excluir"
        busy={busy}
        onConfirm={async () => {
          if (toDelete?.id == null) return;
          setBusy(true);
          await StudyActions.deleteSaved(toDelete.id);
          setBusy(false);
          setToDelete(null);
        }}
      />
    </>
  );
}
