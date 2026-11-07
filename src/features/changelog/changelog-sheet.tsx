import { History } from 'lucide-react';

import { APP_VERSION } from '../../app/version';
import { type ChangeKind, type Changes, changeKindLabel, changeKinds, changelog, type Release, unreleased } from '../../data/changelog';
import { Badge } from '../../ui/badge';
import { Sheet } from '../../ui/sheet';
import type { Tone } from '../../ui/tone';
import { ChangelogActions, useChangelog } from './changelog-store';

/**
 * A cor de cada categoria. Discreta — superfície tingida com o texto do mesmo
 * papel, os pares de contraste já medidos para os dois temas — e nunca
 * sozinha: o nome da categoria vai escrito na pastilha.
 */
const kindTone: Record<ChangeKind, Tone> = {
  added: 'positive',
  changed: 'pending',
  removed: 'negative',
  fixed: 'caution',
};

const dateFormat = new Intl.DateTimeFormat('pt-BR', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });

/** `2026-11-07` → "7 de novembro de 2026", sem o fuso do navegador mudar o dia. */
export function releaseDateLabel(isoDate: string): string {
  const [year, month, day] = isoDate.split('-').map(Number);
  return dateFormat.format(new Date(Date.UTC(year!, month! - 1, day!)));
}

/** O histórico de versões, da mais recente à mais antiga, numa folha lateral. */
export function ChangelogSheet() {
  const open = useChangelog((s) => s.open);
  const hasPending = changeKinds.some((k) => (unreleased[k]?.length ?? 0) > 0);
  return (
    <Sheet
      open={open}
      onOpenChange={ChangelogActions.setOpen}
      title="Changelog"
      icon={<History aria-hidden className="size-5 text-fg-2" />}
      description={`Versão em uso: v${APP_VERSION}. As versões aparecem da mais recente à mais antiga.`}
      width="lg"
    >
      <div className="space-y-3 px-4 py-4 sm:px-5">
        {hasPending && (
          <article aria-labelledby="changelog-pending" className="rounded-xl border border-dashed border-line p-4">
            <header className="flex flex-wrap items-center gap-2">
              <h3 id="changelog-pending" className="text-body font-semibold text-fg">
                Em preparo
              </h3>
              <Badge tone="neutral">Ainda não publicado</Badge>
            </header>
            <ChangeGroups changes={unreleased} />
          </article>
        )}
        <ol className="space-y-3" aria-label="Versões">
          {changelog.map((release) => (
            <li key={release.version}>
              <ReleaseEntry release={release} current={release.version === APP_VERSION} />
            </li>
          ))}
        </ol>
      </div>
    </Sheet>
  );
}

function ReleaseEntry({ release, current }: { release: Release; current: boolean }) {
  const id = `changelog-${release.version.replaceAll('.', '-')}`;
  return (
    <article
      aria-labelledby={id}
      className={current ? 'rounded-xl border border-brand/40 bg-surface p-4 shadow-card' : 'rounded-xl border border-line bg-surface p-4'}
    >
      <header className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <h3 id={id} className="num text-title-sm font-semibold text-fg">
          v{release.version}
        </h3>
        {current && (
          <Badge tone="brand" className="self-center">
            Atual
          </Badge>
        )}
        <time dateTime={release.date} className="ml-auto text-caption text-fg-3">
          {releaseDateLabel(release.date)}
        </time>
        <p className="w-full text-body-sm text-fg-2">{release.title}</p>
      </header>
      <ChangeGroups changes={release.changes} />
    </article>
  );
}

function ChangeGroups({ changes }: { changes: Changes }) {
  return (
    <div className="mt-3 space-y-3">
      {changeKinds.map((kind) => {
        const items = changes[kind] ?? [];
        if (items.length === 0) return null;
        return (
          <section key={kind} aria-label={changeKindLabel[kind]}>
            <Badge tone={kindTone[kind]}>{changeKindLabel[kind]}</Badge>
            <ul className="mt-1.5 list-disc space-y-1 pl-5 text-body-sm leading-relaxed text-fg marker:text-fg-3">
              {items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}
