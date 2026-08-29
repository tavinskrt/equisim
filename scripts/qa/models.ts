/**
 * Descoberta dos modelos disponiveis na assinatura, via `agy models`.
 *
 * NADA aqui e fixado por nome. O catalogo do Google muda rapido -- na semana em
 * que isto foi escrito conviviam Flash 3.5, 3.6 e 3.7 e Pro 3.1 --, e uma lista
 * escrita a mao envelheceria em silencio: o gate continuaria rodando, so que num
 * modelo velho, sem ninguem perceber. A familia e a versao sao extraidas do
 * proprio `agy models`, entao um Gemini 4 aparece sozinho na proxima execucao.
 */
import { execFileSync } from 'node:child_process';

export type Family = 'flash' | 'pro';
export type Effort = 'low' | 'medium' | 'high';

export interface AgyModel {
  id: string;
  label: string;
  family: Family;
  effort: Effort;
  /** [major, minor] -- comparado numericamente, nao como texto. */
  version: [number, number];
}

/**
 * `gemini-3.7-flash-high` -> familia flash, versao 3.7, esforco high.
 * Modelos fora desse padrao (claude-*, gpt-oss-*) sao ignorados de proposito:
 * este seletor e do auditor Gemini.
 */
const MODEL_ID = /^gemini-(\d+)\.(\d+)-(flash|pro)-(low|medium|high)$/;

function agyExecutable(): string {
  if (process.env.AGY_PATH) return process.env.AGY_PATH;
  return process.platform === 'win32' ? 'agy.exe' : 'agy';
}

export function listAgyModels(): AgyModel[] {
  let raw: string;
  try {
    raw = execFileSync(agyExecutable(), ['models'], {
      encoding: 'utf8',
      timeout: 30_000,
      windowsHide: true,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Nao consegui listar os modelos do agy: ${message}\n` +
        'Confirme com: agy models',
    );
  }

  const out: AgyModel[] = [];
  for (const line of raw.split(/\r?\n/)) {
    // Formato: "<id>\t<rotulo legivel>"
    const [id, label] = line.split('\t');
    if (!id) continue;
    const match = MODEL_ID.exec(id.trim());
    if (!match) continue;
    out.push({
      id: id.trim(),
      label: (label ?? id).trim(),
      version: [Number(match[1]), Number(match[2])],
      family: match[3] as Family,
      effort: match[4] as Effort,
    });
  }
  return out;
}

/** Ordena da versao mais nova para a mais antiga. */
function byVersionDesc(a: AgyModel, b: AgyModel): number {
  return b.version[0] - a.version[0] || b.version[1] - a.version[1];
}

export interface ModelChoice {
  id: string;
  label: string;
  hint: string;
}

/**
 * As quatro opcoes oferecidas: Flash e Pro, cada um em low e high, sempre na
 * versao mais recente de cada familia.
 *
 * `medium` existe para Flash mas fica de fora do menu -- entre quatro escolhas
 * a pessoa decide, entre seis hesita. Continua acessivel por `--model`.
 */
export function latestChoices(models: AgyModel[]): ModelChoice[] {
  const choices: ModelChoice[] = [];

  for (const family of ['flash', 'pro'] as const) {
    const ofFamily = models.filter((m) => m.family === family).sort(byVersionDesc);
    if (ofFamily.length === 0) continue;
    const newest = ofFamily[0]!.version;
    const latest = ofFamily.filter(
      (m) => m.version[0] === newest[0] && m.version[1] === newest[1],
    );

    for (const effort of ['low', 'high'] as const) {
      const found = latest.find((m) => m.effort === effort);
      if (!found) continue;
      choices.push({
        id: found.id,
        label: found.label,
        hint:
          family === 'flash'
            ? effort === 'low'
              ? 'mais rapido; bom para diff pequeno'
              : 'rapido, com mais profundidade'
            : effort === 'low'
              ? 'raciocinio Pro, tempo moderado'
              : 'maximo rigor; diff grande fica lento',
      });
    }
  }
  return choices;
}
