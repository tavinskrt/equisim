/**
 * Carga da credencial do Gemini.
 *
 * Ordem de precedencia, do mais seguro para o menos seguro:
 *   1. Variavel de ambiente do processo  (CI, terminal, secret manager)
 *   2. `.env.qa` na raiz                 (arquivo exclusivo de ferramentas)
 *   3. `.env` na raiz                    (ACEITO, MAS COM AVISO -- ver abaixo)
 *
 * Por que o aviso no caso 3: o `pubspec.yaml` do Equisim declara `.env` como
 * asset do Flutter (`assets: - .env`). Todo asset e empacotado no bundle da
 * aplicacao e, em `flutter build web`, fica publicamente legivel. Uma chave do
 * Gemini colocada la vaza para qualquer visitante. O arquivo `.env.qa` existe
 * exatamente para separar credencial de ferramenta de credencial de runtime.
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export interface ApiKeyResolution {
  apiKey: string;
  source: string;
  warning?: string;
}

/** Parser minimo de dotenv: `CHAVE=valor`, ignora comentarios e linhas vazias. */
function parseDotEnv(path: string): Record<string, string> {
  const out: Record<string, string> = {};
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    return out;
  }
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    // Remove aspas envolventes, se houver.
    if (
      (value.startsWith('"') && value.endsWith('"') && value.length >= 2) ||
      (value.startsWith("'") && value.endsWith("'") && value.length >= 2)
    ) {
      value = value.slice(1, -1);
    }
    out[key] = value;
  }
  return out;
}

export function resolveApiKey(repoRoot: string): ApiKeyResolution {
  const fromProcess = process.env.GEMINI_API_KEY?.trim();
  if (fromProcess) {
    return { apiKey: fromProcess, source: 'variavel de ambiente GEMINI_API_KEY' };
  }

  const qaPath = join(repoRoot, '.env.qa');
  if (existsSync(qaPath)) {
    const value = parseDotEnv(qaPath).GEMINI_API_KEY?.trim();
    if (value) return { apiKey: value, source: '.env.qa' };
  }

  const envPath = join(repoRoot, '.env');
  if (existsSync(envPath)) {
    const value = parseDotEnv(envPath).GEMINI_API_KEY?.trim();
    if (value) {
      return {
        apiKey: value,
        source: '.env',
        warning:
          'A GEMINI_API_KEY foi lida de `.env`, que o pubspec.yaml declara como ASSET do Flutter.\n' +
          '  Em `flutter build web` esse arquivo e embarcado no bundle publico e a chave vaza.\n' +
          '  Mova a chave para `.env.qa` (ignorado pelo git e nao declarado como asset).',
      };
    }
  }

  throw new Error(
    'GEMINI_API_KEY nao encontrada.\n' +
      'Defina-a em uma destas fontes (nesta ordem de preferencia):\n' +
      '  1. variavel de ambiente:  $env:GEMINI_API_KEY = "..."   (PowerShell)\n' +
      '  2. arquivo `.env.qa` na raiz:  GEMINI_API_KEY=...\n' +
      '  3. arquivo `.env` na raiz (NAO recomendado: e asset do Flutter)\n' +
      'Obtenha a chave em https://aistudio.google.com/apikey',
  );
}
