/**
 * Leitura dos pacotes versionados que o build serve.
 *
 * No Flutter, um pacote só ia para o build se estivesse declarado em
 * `flutter: assets:` no `pubspec.yaml`, e os testes de pacote conferiam a
 * declaração. No Vite não há declaração: **tudo o que está em `public/` é
 * copiado como está para a raiz de `dist/`** (https://vite.dev/guide/assets#the-public-directory).
 * A conferência equivalente é o arquivo estar em `public/`, no caminho que
 * [AssetPaths] diz ao aplicativo para buscar.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { isJsonObject, type JsonObject } from '../../src/core';

/** Caminho no repositório de um pacote que o build serve em [path]. */
export function publicFile(path: string): string {
  return join('public', path);
}

/** O pacote está onde o build o copia. */
export function isServed(path: string): boolean {
  return existsSync(publicFile(path));
}

/** O texto do pacote servido em [path]. */
export function readPublic(path: string): string {
  return readFileSync(publicFile(path), 'utf8');
}

/** O pacote servido em [path], como objeto JSON. */
export function readPublicJson(path: string): JsonObject {
  return asObject(JSON.parse(readPublic(path)), path);
}

/** Um JSON do repositório fora de `public/`, como as medições de `docs/validacao/`. */
export function readRepoJson(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8'));
}

/** [value] como objeto JSON, ou falha que diz onde a forma divergiu. */
export function asObject(value: unknown, where: string): JsonObject {
  if (!isJsonObject(value)) throw new TypeError(`${where}: esperava um objeto JSON`);
  return value;
}

/** As raízes de quatro letras dos tickers da coorte de validação. */
export function universeTickers(): string[] {
  const raw = readRepoJson('docs/validacao/universo.json');
  if (!Array.isArray(raw)) throw new TypeError('docs/validacao/universo.json: esperava uma lista');
  return raw.map((e) => String(asObject(e, 'universo.json')['ticker']));
}
