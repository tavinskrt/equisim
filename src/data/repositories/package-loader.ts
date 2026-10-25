import { isJsonObject, type JsonObject } from '../../core';

/**
 * Lê o conteúdo de um pacote de dados versionado.
 *
 * No aplicativo, é um `fetch` de `public/assets/...`; nas ferramentas de
 * `tool/`, a leitura do arquivo no disco; em teste, a string da fixture.
 */
export type PackageLoader = () => Promise<string>;

/**
 * Lê e decodifica um pacote **uma vez**, devolvendo [fallback] para pacote
 * ausente, ilegível ou de forma inesperada.
 *
 * Todo repositório de pacote é **transparente sem o pacote**: a falta dele
 * devolve o comportamento anterior ao pacote, e nunca derruba a avaliação. Por
 * isso a falha não é propagada — ela é a ausência.
 */
export function memoizedPackage<T>(
  loadPackage: PackageLoader,
  decode: (json: JsonObject) => T,
  fallback: T,
): () => Promise<T> {
  let cached: Promise<T> | null = null;
  const read = async (): Promise<T> => {
    try {
      const json: unknown = JSON.parse(await loadPackage());
      return isJsonObject(json) ? decode(json) : fallback;
    } catch {
      return fallback;
    }
  };
  return () => (cached ??= read());
}
