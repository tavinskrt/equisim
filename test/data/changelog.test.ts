import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { APP_VERSION } from '../../src/app/version';
import { changeKinds, changelog, latestRelease, unreleased } from '../../src/data/changelog';
import { renderChangelogMarkdown } from '../../src/data/changelog-markdown';

const semver = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const parts = (v: string) => v.split('.').map(Number) as [number, number, number];
const compare = (a: string, b: string) => {
  const [x, y] = [parts(a), parts(b)];
  return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
};

describe('Histórico de versões', () => {
  it('a versão do package.json, a do aplicativo e a mais recente do histórico são a mesma', () => {
    const pkg = JSON.parse(readFileSync('package.json', 'utf8')) as { version: string };
    expect(APP_VERSION).toBe(pkg.version);
    expect(latestRelease.version).toBe(pkg.version);
  });

  it('as versões são SemVer, únicas e vêm da mais recente para a mais antiga', () => {
    for (const r of changelog) expect(r.version, r.version).toMatch(semver);
    for (let i = 1; i < changelog.length; i++) {
      expect(compare(changelog[i - 1]!.version, changelog[i]!.version), changelog[i]!.version).toBeGreaterThan(0);
    }
  });

  it('as datas são ISO 8601 válidas e nunca voltam no tempo', () => {
    for (const r of changelog) {
      expect(r.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(new Date(`${r.date}T00:00:00Z`).toISOString().slice(0, 10)).toBe(r.date);
    }
    for (let i = 1; i < changelog.length; i++) expect(changelog[i - 1]!.date >= changelog[i]!.date).toBe(true);
  });

  it('toda versão tem título e ao menos uma mudança, só nas quatro categorias', () => {
    for (const r of [...changelog, { version: 'não publicado', title: '-', changes: unreleased }]) {
      expect(r.title.trim(), r.version).not.toBe('');
      for (const key of Object.keys(r.changes)) expect(changeKinds, `${r.version}: ${key}`).toContain(key);
    }
    for (const r of changelog) {
      const total = changeKinds.reduce((n, k) => n + (r.changes[k]?.length ?? 0), 0);
      expect(total, r.version).toBeGreaterThan(0);
    }
  });

  it('o texto fala do produto, e não de bastidor: sem caminho de arquivo, código ou registro interno', () => {
    const items = [...changelog.flatMap((r) => changeKinds.flatMap((k) => r.changes[k] ?? [])), ...changeKinds.flatMap((k) => unreleased[k] ?? [])];
    for (const item of items) {
      expect(item, item).not.toMatch(/\.tsx?\b|\bsrc\/|`|decis[ãa]o \d|você pediu/i);
      expect(item.trim().endsWith('.'), item).toBe(true);
    }
  });

  it('o CHANGELOG.md é exatamente o que `npm run changelog` gera', () => {
    expect(readFileSync('CHANGELOG.md', 'utf8')).toBe(renderChangelogMarkdown());
  });
});
