// Listagem de arquivos de dados, na ordem estável que os scripts esperam.
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

import { compareStr, str } from '../../src/core';

/**
 * Os arquivos de [dir] cujo nome casa com [pattern], pelo caminho em ordem
 * de código de unidade — a ordem do `compareTo` do Dart, que é a que o
 * resultado das leituras supõe ("o mais recente vence" lê o último por último).
 *
 * Sem o diretório, devolve lista vazia; quem chama decide se isso é recuo ou
 * erro.
 */
export function filesIn(dir: string, pattern: RegExp): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((name) => pattern.test(name) && statSync(`${dir}/${name}`).isFile())
    .map((name) => `${dir}/${name}`)
    .sort(compareStr);
}

/**
 * As linhas de um arquivo de texto em UTF-8, como o `readAsLinesSync` do
 * Dart: `\n` e `\r\n` separam, e a quebra final não cria linha vazia.
 */
export function readLines(path: string): string[] {
  const lines = readFileSync(path, 'utf8').split(/\r?\n/);
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/** Lê e decodifica um JSON. */
export function readJson<T = unknown>(path: string): T {
  return JSON.parse(readFileSync(path, 'utf8')) as T;
}

/** Encerra a ferramenta com uma mensagem no stderr e o código dado. */
export function fail(message: string, code = 2): never {
  process.stderr.write(`${message}\n`);
  process.exit(code);
}

/**
 * JSON com recuo de um espaço, o `JsonEncoder.withIndent(' ')` com que as
 * ferramentas em Dart gravavam os relatórios — o diff de uma regravação fica
 * no que mudou, e não no recuo.
 */
export function jsonPretty(value: unknown, indent = ' '): string {
  return JSON.stringify(value, null, indent);
}

/** Grava um arquivo de texto, criando o diretório que faltar. */
export function writeText(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

/** O valor que segue [flag] nos argumentos, ou `null`. */
export function flagValue(args: readonly string[], flag: string): string | null {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1]! : null;
}

/** Saída padrão, linha a linha — o `stdout.writeln` do Dart. */
export const outln = (line = ''): void => {
  process.stdout.write(`${line}\n`);
};

/** Saída de erro, linha a linha — o `stderr.writeln` do Dart. */
export const errln = (line = ''): void => {
  process.stderr.write(`${line}\n`);
};

/**
 * As linhas de um texto, como o `LineSplitter` do Dart: `\n`, `\r\n` e `\r`
 * separam, e a quebra final não cria linha vazia.
 */
export function splitLines(text: string): string[] {
  const lines = text.split(/\r\n|\r|\n/);
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/** O texto de um arquivo em ISO-8859-1 — o `latin1.decode` do Dart. */
export function readLatin1(path: string): string {
  return readFileSync(path).toString('latin1');
}

/**
 * Um valor decodificado de JSON escrito como o Dart o interpolava: mapa como
 * `{chave: valor}`, lista como `[a, b]`, texto sem aspas e ausente como `null`.
 * Existe para que as linhas de console das ferramentas saiam iguais às de
 * antes, que imprimiam mapas inteiros.
 */
export function dartString(value: unknown): string {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') return str(value);
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return `[${value.map(dartString).join(', ')}]`;
  if (value instanceof Map) return `{${[...value].map(([k, v]) => `${dartString(k)}: ${dartString(v)}`).join(', ')}}`;
  if (typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .map(([k, v]) => `${k}: ${dartString(v)}`)
      .join(', ')}}`;
  }
  return String(value);
}
