import { type Changes, changeKindLabel, changeKinds, changelog, type Release, unreleased, versioningPolicy } from './changelog';

/**
 * Escreve o `CHANGELOG.md` a partir de `changelog.ts`, no formato do Keep a
 * Changelog 1.1.0: a seção "Não publicado" no alto, e cada versão como
 * `## [MAJOR.MINOR.PATCH] - AAAA-MM-DD`, com as categorias na ordem fixa.
 *
 * Função pura: quem grava o arquivo é `scripts/gerar-changelog.ts`, e um
 * teste confere que o arquivo versionado é exatamente o que ela produz.
 */
export function renderChangelogMarkdown(
  releases: readonly Release[] = changelog,
  pending: Changes = unreleased,
): string {
  const lines: string[] = [
    '# Changelog',
    '',
    '<!-- Arquivo gerado por `npm run changelog` a partir de src/data/changelog.ts. Não edite à mão. -->',
    '',
    'Todas as mudanças relevantes do Equisim ficam registradas neste arquivo.',
    '',
    'O formato segue o [Keep a Changelog 1.1.0](https://keepachangelog.com/pt-BR/1.1.0/),',
    'e a numeração segue o [Versionamento Semântico 2.0.0](https://semver.org/lang/pt-BR/).',
    '',
    '## Como a versão é numerada',
    '',
    versioningPolicy.publicInterface,
    '',
    `- ${versioningPolicy.major}`,
    `- ${versioningPolicy.minor}`,
    `- ${versioningPolicy.patch}`,
    `- ${versioningPolicy.zero}`,
    '',
    '## [Não publicado]',
    '',
    ...renderChanges(pending),
  ];
  for (const release of releases) {
    lines.push(`## [${release.version}] - ${release.date}`, '', `_${release.title}_`, '', ...renderChanges(release.changes));
  }
  // Uma linha em branco no fim, e nunca duas.
  while (lines.at(-1) === '') lines.pop();
  return `${lines.join('\n')}\n`;
}

function renderChanges(changes: Changes): string[] {
  const lines: string[] = [];
  for (const kind of changeKinds) {
    const items = changes[kind] ?? [];
    if (items.length === 0) continue;
    lines.push(`### ${changeKindLabel[kind]}`, '', ...items.map((item) => `- ${item}`), '');
  }
  return lines;
}
