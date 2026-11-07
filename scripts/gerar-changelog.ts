/**
 * Gera o `CHANGELOG.md` da raiz a partir de `src/data/changelog.ts`.
 *
 *     npm run changelog
 *
 * A fonte é o arquivo TypeScript, que a tela de novidades do aplicativo lê; o
 * markdown é a cópia para quem lê o repositório. Editar o `CHANGELOG.md` à
 * mão não adianta: `test/data/changelog.test.ts` reprova quando os dois
 * divergem, e a próxima geração sobrescreve.
 */
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { latestRelease } from '../src/data/changelog';
import { renderChangelogMarkdown } from '../src/data/changelog-markdown';

const output = join(process.cwd(), 'CHANGELOG.md');
writeFileSync(output, renderChangelogMarkdown(), 'utf8');
process.stdout.write(`CHANGELOG.md gerado -- versao mais recente ${latestRelease.version} (${latestRelease.date}).\n`);
