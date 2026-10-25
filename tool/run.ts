// Despachante das ferramentas: `npm run tool -- <nome> [argumentos]`.
//
// Cada ferramenta é um módulo em `tool/` que exporta `main(args)`. O nome é o
// caminho do módulo sem a extensão — `implied-premium`, `c7-seal` — e a
// tabela de nomes antigos (os `.dart`) para os novos está no `tool/README.md`.
// Sem nome, lista as ferramentas.
import { existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

// O `node:sqlite` do cache das ferramentas ainda é experimental no Node 22, e
// o aviso sairia em toda execução. Só esse aviso é calado; os outros passam.
const emitWarning = process.emitWarning.bind(process);
process.emitWarning = ((warning: string | Error, ...rest: unknown[]) => {
  if (String(warning).includes('SQLite is an experimental feature')) return;
  (emitWarning as (...a: unknown[]) => void)(warning, ...rest);
}) as typeof process.emitWarning;

/** Módulos de biblioteca: são importados pelas ferramentas, e não executados. */
const libraries = new Set(['run']);

function tools(): string[] {
  return readdirSync(here)
    .filter((f) => f.endsWith('.ts') && !f.endsWith('.d.ts'))
    .map((f) => f.slice(0, -3))
    .filter((name) => !libraries.has(name))
    .sort();
}

const [name, ...args] = process.argv.slice(2);
if (name === undefined || name === '--help' || name === '-h') {
  process.stdout.write('Uso: npm run tool -- <ferramenta> [argumentos]\n\nFerramentas:\n');
  for (const t of tools()) process.stdout.write(`  ${t}\n`);
  process.exit(0);
}
const file = join(here, `${name}.ts`);
if (libraries.has(name) || !existsSync(file)) {
  process.stderr.write(`Ferramenta desconhecida: ${name}. Rode \`npm run tool\` para a lista; o tool/README.md traz o nome novo de cada .dart.\n`);
  process.exit(2);
}
const module = (await import(pathToFileURL(file).href)) as { main?: (args: string[]) => Promise<void> | void };
if (typeof module.main !== 'function') {
  process.stderr.write(`${name} é módulo de biblioteca, e não ferramenta: não exporta main.\n`);
  process.exit(2);
}
await module.main(args);
