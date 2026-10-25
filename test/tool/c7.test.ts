// O protocolo da réplica fora da amostra (item C7): cada trava tem teste.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { DateTime, SeededRandom } from '../../src/core';
import {
  commitFingerprint,
  commitOfFingerprint,
  Engine,
  engineFingerprint,
  fileHash,
  Index,
  ProtocolViolated,
  read,
  seal,
  sealsDir,
  situation,
} from '../../tool/c7/protocol';

type Json = Record<string, unknown>;

const engine = new Engine('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const other = new Engine('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

/** As coortes do C7 de 31/12/2025 em diante, [n] trimestres. */
const cohortsOf = (n: number): string[] =>
  Array.from({ length: n }, (_, i) => DateTime.local(2025, 12 + 3 * i + 1, 0).toIso8601String().slice(0, 10));

/**
 * Observações sintéticas: o retorno segue o potencial com ruído, para a
 * leitura ter o que medir.
 */
function rowsOf(cohorts: readonly string[], options: { assets?: number; withReturn?: boolean; seed?: number } = {}): Json[] {
  const assets = options.assets ?? 40;
  const withReturn = options.withReturn ?? false;
  const seed = options.seed ?? 7;
  const rnd = new SeededRandom(seed);
  // Gerador próprio para o desfecho: as previsões são as mesmas com ou sem
  // retorno, como num backtest refeito com a base de depois.
  const noise = new SeededRandom(seed + 1);
  const out: Json[] = [];
  for (const c of cohorts) {
    for (let a = 0; a < assets; a++) {
      const up = rnd.nextDouble() * 2 - 1;
      const row: Json = {
        coorte: c,
        ticker: `T${String(a).padStart(3, '0')}3`,
        deslistada: false,
        upside: up,
        bookToMarket: rnd.nextDouble(),
        earningsYield: rnd.nextDouble() * 0.2,
        justo: 10 + up,
        preco: 10.0,
      };
      if (withReturn) row['ret12tot'] = 0.3 * up + noise.nextDouble() * 0.2;
      if (withReturn) row['ret36tot'] = 0.5 * up + noise.nextDouble() * 0.4;
      out.push(row);
    }
  }
  return out;
}

const field = (j: unknown, ...path: string[]): unknown => path.reduce<unknown>((o, k) => (o as Json)[k], j);

let folder = '';
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'c7_'));
});
afterEach(() => rmSync(folder, { recursive: true, force: true }));

describe('selagem', () => {
  it('sela uma vez por coorte, sem campo de desfecho, com o hash no índice', async () => {
    const rows = rowsOf(cohortsOf(3), { withReturn: true });
    const r = await seal({ rows, engine, folder, today: '2026-09-24' });
    expect(r.sealedCohorts).toEqual(cohortsOf(3));
    expect(r.series).toBe('preRegistrado');

    const index = Index.read(folder);
    expect(index.preRegisteredEngine!.fingerprint).toBe(engine.fingerprint);
    expect(index.seals).toHaveLength(3);
    const sealedJson = JSON.parse(readFileSync(join(folder, 'previsoes_2025-12-31.json'), 'utf8')) as Json;
    const p = (sealedJson['previsoes'] as Json[])[0]!;
    expect(
      Object.keys(p).filter((k) => k.startsWith('ret')),
      'o selo guarda previsão, e não desfecho',
    ).toEqual([]);
    expect(index.seals[0]!['hash']).toBe(await fileHash(join(folder, 'previsoes_2025-12-31.json')));
  });

  it('selar de novo não reescreve: confere, e relata divergência', async () => {
    const rows = rowsOf(cohortsOf(2));
    await seal({ rows, engine, folder, today: 'd1' });
    const before = readFileSync(join(folder, 'previsoes_2025-12-31.json'), 'utf8');
    const changed = rows.map((l) => (l['ticker'] === 'T0003' ? { ...l, upside: 9.0 } : { ...l }));
    const r = await seal({ rows: changed, engine, folder, today: 'd2' });
    expect(r.sealedCohorts).toEqual([]);
    expect(r.alreadySealed).toEqual(cohortsOf(2));
    expect(Object.fromEntries(r.divergent)).toEqual({ '2025-12-31': 1, '2026-03-31': 1 });
    expect(readFileSync(join(folder, 'previsoes_2025-12-31.json'), 'utf8')).toBe(before);
  });

  it('um selo alterado depois de selado interrompe tudo', async () => {
    await seal({ rows: rowsOf(cohortsOf(1)), engine, folder, today: 'd' });
    const f = join(folder, 'previsoes_2025-12-31.json');
    // O preço de 10 reais está em toda previsão: trocar o primeiro adultera o
    // selo sem mexer no formato do arquivo.
    const text = readFileSync(f, 'utf8');
    const tampered = text.replace(/"preco":\s*10(\.0)?\b/, '"preco": 11');
    expect(tampered).not.toBe(text);
    writeFileSync(f, tampered);
    await expect(seal({ rows: rowsOf(cohortsOf(2)), engine, folder, today: 'd' })).rejects.toBeInstanceOf(ProtocolViolated);
  });

  it('coorte anterior a 31/12/2025 não é da réplica', async () => {
    await expect(seal({ rows: rowsOf(['2025-09-30']), engine, folder, today: 'd' })).rejects.toBeInstanceOf(ProtocolViolated);
  });

  it('motor diferente do pré-registrado sela em série própria', async () => {
    await seal({ rows: rowsOf(cohortsOf(1)), engine, folder, today: 'd' });
    const r = await seal({ rows: rowsOf(cohortsOf(1)), engine: other, folder, today: 'd' });
    expect(r.series).toBe('motorDaData');
    expect(r.sealedCohorts).toEqual(['2025-12-31']);
    expect(existsSync(join(folder, 'previsoes_2025-12-31_bbbbbbbb.json'))).toBe(true);
    expect(Index.read(folder).preRegisteredEngine!.fingerprint, 'o pré-registrado não muda').toBe(engine.fingerprint);
  });
});

describe('leitura', () => {
  it('antes da data, a situação — e nenhuma estatística', async () => {
    await seal({ rows: rowsOf(cohortsOf(3)), engine, folder, today: 'd' });
    const s = situation({ folder, today: DateTime.local(2026, 9, 24), dataEnd: DateTime.local(2027, 3, 30) });
    expect(s['coortesSeladas']).toEqual(cohortsOf(3));
    expect(field(s, '12m', 'aberta')).toBe(false);
    expect(field(s, '12m', 'coortesMaduras'), 'só 31/12/2025 tem doze meses até 30/03/2027').toBe(1);
    expect(JSON.stringify(s)).not.toContain('media');

    await expect(
      read({ months: 12, folder, today: DateTime.local(2029, 9, 29), rows: rowsOf(cohortsOf(3), { withReturn: true }) }),
    ).rejects.toBeInstanceOf(ProtocolViolated);
  });

  it('na data, o instrumento do R3 sobre as previsões seladas', async () => {
    const cohorts = cohortsOf(12);
    await seal({ rows: rowsOf(cohorts), engine, folder, today: 'd' });
    // Os retornos chegam de um backtest posterior, com as mesmas previsões.
    const r = await read({ months: 12, folder, today: DateTime.local(2029, 9, 30), rows: rowsOf(cohorts, { withReturn: true }) });
    expect(r['previsoesRefeitasQueDivergem']).toBe(0);
    const fm = field(r, 'leitura', 'famaMacBeth', 'potencialDadoBm') as Json;
    expect(fm['coortes']).toBe(12);
    expect(fm['media'] as number, 'o retorno sintético segue o potencial').toBeGreaterThan(0);
    expect('passaR3' in fm).toBe(true);
  });

  it('as duas versões: a pré-registrada é a leitura, a do motor da data vem ao lado', async () => {
    const cohorts = cohortsOf(12);
    await seal({ rows: rowsOf(cohorts), engine, folder, today: 'd' });
    // O motor posterior prevê outra coisa (outra semente) e sela à parte.
    await seal({ rows: rowsOf(cohorts, { seed: 99 }), engine: other, folder, today: 'd' });
    const s = situation({ folder, today: DateTime.local(2026, 9, 24), dataEnd: DateTime.local(2027, 3, 30) });
    expect(field(s, 'motoresDaData', other.fingerprint)).toEqual(cohorts);
    expect(s['coortesSeladas'], 'as coortes da leitura são as do pré-registrado').toEqual(cohorts);

    const r = await read({ months: 12, folder, today: DateTime.local(2029, 9, 30), rows: rowsOf(cohorts, { withReturn: true }) });
    const preRegistered = field(r, 'leitura', 'famaMacBeth', 'potencialDadoBm') as Json;
    const ofDate = field(r, 'motoresDaData', other.fingerprint, 'famaMacBeth', 'potencialDadoBm') as Json;
    expect(preRegistered['coortes']).toBe(12);
    expect(ofDate['coortes']).toBe(12);
    expect((preRegistered['media'] as number) - (ofDate['media'] as number), 'cada série lê as próprias previsões seladas').not.toBe(0);
    expect(r['previsoesRefeitasQueDivergem'], 'a divergência é medida contra o pré-registrado').toBe(0);
  });

  it('juntar as coortes antigas às novas é recusado, e não filtrado', async () => {
    await seal({ rows: rowsOf(cohortsOf(2)), engine, folder, today: 'd' });
    await expect(
      read({
        months: 12,
        folder,
        today: DateTime.local(2030, 1, 1),
        rows: [...rowsOf(cohortsOf(2), { withReturn: true }), ...rowsOf(['2025-09-30'], { withReturn: true })],
      }),
    ).rejects.toBeInstanceOf(ProtocolViolated);
  });
});

it('a impressão do motor é estável e é a do git', async () => {
  const a = await engineFingerprint();
  const b = await engineFingerprint();
  expect(a).toBe(b);
  expect(a).toMatch(/^[0-9a-f]{40}$/);
});

it('o motor pré-registrado do índice está num commit, e a árvore dele tem a mesma impressão', async () => {
  // A série pré-registrada das coortes novas sai de um worktree desse commit
  // (decisão 138): se a impressão do índice não fosse achável no histórico,
  // não haveria de onde refazê-la.
  const preRegistered = Index.read(sealsDir).preRegisteredEngine;
  expect(preRegistered, 'o C7 tem selo desde 24/09/2026').not.toBeNull();
  const found = await commitOfFingerprint(preRegistered!.fingerprint);
  expect(found).not.toBeNull();
  expect(await commitFingerprint(found!.commit, found!.tree)).toBe(preRegistered!.fingerprint);
});
