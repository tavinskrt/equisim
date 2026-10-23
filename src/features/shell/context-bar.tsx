import { FolderOpen, HardDrive, Save, Target } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router';

import { RequiredReturnSolver } from '../../core';
import { Fmt } from '../../copy';
import { useFeasibility } from '../../app/hooks';
import { useSession } from '../../app/state/session-store';
import { StudyActions, useStudy } from '../../app/state/study-store';
import { Badge } from '../../ui/badge';
import { Button, IconButton } from '../../ui/button';
import { Spinner } from '../../ui/feedback';
import { toast } from '../../ui/toast';
import { Tooltip } from '../../ui/tooltip';
import { feasibilityTone } from '../goal/feasibility-tone';
import { SavedStudiesDialog } from '../study/saved-studies-dialog';

/**
 * A barra do estudo e da meta, comum às áreas: **o que está aberto e para
 * onde ele vai**. O estudo tem nome e é gravado daqui; a meta resume o plano
 * e a rentabilidade que ele exige, e abre o Planejador.
 */
export function ContextBar() {
  const study = useStudy((s) => s.study);
  const isSaving = useStudy((s) => s.isSaving);
  const local = useSession((s) => s.local);
  const [savedOpen, setSavedOpen] = useState(false);
  const verdict = useFeasibility(study.goal);

  const required = study.goal === null ? null : RequiredReturnSolver.solve(study.goal);
  const annual = required !== null && required.isOk ? required.unwrap().annual : null;

  const save = async () => {
    const ok = await StudyActions.save();
    // O erro vira mensagem pelo `lastError`; o caminho feliz precisa de
    // confirmação — sem ela, ficava a dúvida de ter salvo ou não.
    if (ok) toast(local ? 'Estudo salvo neste navegador.' : 'Estudo salvo. Abra em “Estudos salvos” quando voltar.', 'success');
  };

  return (
    <div className="border-b border-divider bg-surface/60">
      <div className="mx-auto flex max-w-[1440px] flex-wrap items-center gap-x-3 gap-y-1 px-4 py-1.5 sm:px-6">
        <div className="flex min-w-0 flex-1 items-center gap-1 sm:flex-none">
          <label htmlFor="study-name" className="sr-only">
            Nome do estudo
          </label>
          <input
            id="study-name"
            value={study.name}
            placeholder="Nome do estudo"
            onChange={(e) => StudyActions.rename(e.target.value)}
            className="min-h-11 w-full min-w-0 truncate rounded-md bg-transparent px-2 text-body font-semibold text-fg placeholder:text-fg-3 hover:bg-sunken focus:bg-sunken focus:outline-none sm:w-56"
          />
          <IconButton label="Estudos salvos" onClick={() => setSavedOpen(true)}>
            <FolderOpen aria-hidden className="size-[18px]" />
          </IconButton>
          {isSaving ? (
            <span className="inline-flex size-11 items-center justify-center">
              <Spinner label="Salvando o estudo" />
            </span>
          ) : (
            <IconButton label={study.id === null ? 'Salvar estudo' : 'Salvar alterações'} tone="brand" onClick={save}>
              <Save aria-hidden className="size-[18px]" />
            </IconButton>
          )}
          {local && (
            <Tooltip content="Sem conta: os estudos e valuations ficam neste navegador e não acompanham você para outro aparelho.">
              <span tabIndex={0} className="ml-1 hidden sm:inline-flex">
                <Badge tone="pending" icon={<HardDrive aria-hidden className="size-3" />}>
                  Neste navegador
                </Badge>
              </span>
            </Tooltip>
          )}
        </div>

        <div className="flex min-w-0 items-center gap-2 sm:ml-auto">
          {study.goal === null ? (
            <Button asChild variant="ghost" size="sm">
              <Link to="/meta">
                <Target aria-hidden className="size-4" />
                Definir a meta
              </Link>
            </Button>
          ) : (
            <Link
              to="/meta"
              className="flex min-h-11 min-w-0 items-center gap-2 rounded-lg px-2 text-body-sm hover:bg-sunken"
              aria-label="Abrir o planejador da meta"
            >
              <Target aria-hidden className="size-4 shrink-0 text-fg-3" />
              <span className="num truncate text-fg-2">
                {Fmt.compactMoney(study.goal.targetWealth.reais)} em {Math.round(study.goal.months / 12)} anos
              </span>
              {annual !== null && verdict !== null && (
                <Badge tone={feasibilityTone(verdict.level)}>exige {Fmt.percent(annual, { decimals: 1 })} a.a.</Badge>
              )}
            </Link>
          )}
        </div>
      </div>
      <SavedStudiesDialog open={savedOpen} onOpenChange={setSavedOpen} />
    </div>
  );
}
