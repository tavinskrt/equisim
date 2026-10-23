/**
 * Paridade com o motor Dart original.
 *
 * O gabarito em `test/parity/golden/` foi gravado pelo núcleo Dart compilado
 * para JavaScript (ver `test/parity/dart/harness.dart`) antes da remoção do
 * Dart (decisão 152). Esta suíte refaz a mesma bateria com o núcleo
 * TypeScript e exige **igualdade exata**: número com número por `Object.is`,
 * texto com texto, e o rastro de auditoria de cada avaliação pela impressão
 * SHA-256 do JSON que o Dart produziria.
 *
 * Tolerância é zero de propósito. A cascata é determinística por regra do
 * núcleo, e um port que «quase» bate é um port que tomou outro caminho em
 * algum ramo — a diferença de um centavo é o sintoma, não o defeito.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gunzipSync } from 'node:zlib';

import { beforeAll, describe, expect, it } from 'vitest';

import { diff, type Divergence } from './compare';
import { runOracle, type OracleOutput } from './oracle';

const repo = join(__dirname, '..', '..');
const golden = join(__dirname, 'golden');

function readGz(name: string): Record<string, unknown> {
  return JSON.parse(gunzipSync(readFileSync(join(golden, name))).toString('utf8')) as Record<string, unknown>;
}

const ASSEMBLIES = [
  'doisPontos',
  'curva',
  'aplicativo',
  'ancorada',
  'semCurva',
  'prior',
  'monteCarlo',
  'viaFirma',
  'viaAcionista',
  'impostos',
  'margemCurta',
  'notas',
  'deslocamentos',
] as const;

function report(divergences: readonly Divergence[]): string {
  return divergences
    .slice(0, 10)
    .map((d) => `${d.path}: esperado ${JSON.stringify(d.expected)}, obtido ${JSON.stringify(d.actual)}`)
    .join('\n');
}

describe('paridade com o motor Dart', () => {
  let out: OracleOutput;
  let expectedRows: Record<string, Record<string, unknown>>;
  let expectedServices: Record<string, unknown>;

  beforeAll(async () => {
    out = await runOracle({ repo });
    expectedRows = readGz('cascade.json.gz') as Record<string, Record<string, unknown>>;
    expectedServices = readGz('services.json.gz');
  }, 600_000);

  it('cabeçalho: âncoras de mercado, curva, prêmio e os dois priors do beta', () => {
    const expected = JSON.parse(readFileSync(join(golden, 'header.json'), 'utf8')) as unknown;
    const d = diff(expected, out.header);
    expect(d, report(d)).toEqual([]);
  });

  it('avalia o mesmo universo de ativos', () => {
    expect(Object.keys(out.rows)).toEqual(Object.keys(expectedRows));
  });

  for (const assembly of ASSEMBLIES) {
    it(`montagem «${assembly}»: resultado, avisos, diagnósticos e rastro idênticos`, () => {
      const divergent: string[] = [];
      for (const ticker of Object.keys(expectedRows)) {
        const d = diff(expectedRows[ticker]![assembly], out.rows[ticker]?.[assembly]);
        if (d.length > 0) divergent.push(`${ticker}\n${report(d)}`);
      }
      expect(divergent.length, divergent.slice(0, 5).join('\n\n')).toBe(0);
    });
  }

  for (const key of [
    'valuations',
    'manual',
    'backtests',
    'concentrations',
    'alignments',
    'swaps',
    'goals',
    'crossSection',
    'calendar',
    'easter',
  ]) {
    it(`serviços: «${key}» idêntico`, () => {
      const d = diff(expectedServices[key], out.services[key], `$.${key}`);
      expect(d, report(d)).toEqual([]);
    });
  }
});
