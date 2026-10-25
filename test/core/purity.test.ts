/**
 * Guarda arquitetural: o núcleo de domínio permanece TypeScript puro.
 *
 * É a diferença entre convenção e garantia. Sem este teste, «o domínio não
 * importa React» é uma regra que alguém quebra em seis meses sem que ninguém
 * perceba; com ele, quebrar a regra derruba a suíte.
 *
 * Também é o que permite às ferramentas de validação (`tool/`) reusar
 * exatamente o mesmo motor que roda no aplicativo.
 *
 * As regras, herdadas do núcleo Dart (`purity_test.dart`) e da decisão 152:
 * - **zero dependência de runtime** — nenhum import que não seja relativo e
 *   que não fique dentro de `src/core`;
 * - **sem rede, sem I/O, sem navegador** — nenhuma referência a `fetch`,
 *   `window`, `document`, armazenamento do navegador, Firebase ou módulos do
 *   Node;
 * - **determinístico** — relógio e sorteio sem semente só nos três pontos que
 *   os declaram: `DateTime.now()` (que o caminho de cálculo recebe por
 *   parâmetro, `asOf ?? DateTime.now()`), o `Random()` sem semente e o
 *   identificador de transação da auditoria.
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const core = resolve(__dirname, '..', '..', 'src', 'core');

function files(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...files(p));
    else if (p.endsWith('.ts')) out.push(p);
  }
  return out;
}

/** O código sem comentários, para que a documentação possa citar o que o código não usa. */
function code(text: string): string {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
}

const all = files(core);

describe('Pureza do núcleo de domínio', () => {
  it('o diretório lido é o núcleo', () => {
    expect(all.length).toBeGreaterThan(50);
    expect(all.some((f) => f.endsWith(join('usecases', 'compute-valuation.ts')))).toBe(true);
  });

  it('nenhum arquivo importa dependência de fora do núcleo', () => {
    const violations: string[] = [];
    const importPattern = /(?:import|export)\s[^'"]*?from\s+['"]([^'"]+)['"]|import\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
    for (const f of all) {
      const text = code(readFileSync(f, 'utf8'));
      for (const m of text.matchAll(importPattern)) {
        const spec = m[1] ?? m[2]!;
        if (!spec.startsWith('.')) {
          violations.push(`${relative(core, f)} → '${spec}': o núcleo não tem dependência de runtime.`);
          continue;
        }
        const target = resolve(dirname(f), spec);
        if (!target.startsWith(core)) {
          violations.push(`${relative(core, f)} → '${spec}': importa de fora de src/core.`);
        }
      }
    }
    expect(violations, `Violações de pureza:\n${violations.join('\n')}`).toEqual([]);
  });

  it('sem rede, sem I/O, sem navegador', () => {
    const forbidden: [RegExp, string][] = [
      [/\bfetch\s*\(/, 'Acesso a rede pertence à camada de dados.'],
      [/\bXMLHttpRequest\b/, 'Acesso a rede pertence à camada de dados.'],
      [/\bWebSocket\b/, 'Acesso a rede pertence à camada de dados.'],
      [/(?<![.\w])window\./, 'window é específico de navegador.'],
      [/\bdocument\./, 'document é específico de navegador.'],
      [/\blocalStorage\b|\bsessionStorage\b|\bindexedDB\b/, 'Persistência pertence à camada de dados.'],
      [/\bBroadcastChannel\b/, 'O canal do painel de logs pertence à camada de auditoria do aplicativo.'],
      [/\bprocess\./, 'process é específico do Node.'],
      [/\brequire\s*\(/, 'require é específico do Node.'],
      [/firebase/i, 'Persistência pertence à camada de dados.'],
    ];
    const violations: string[] = [];
    for (const f of all) {
      const text = code(readFileSync(f, 'utf8'));
      // `window` é também o nome da janela de datas em boa parte do núcleo; só
      // conta como o global do navegador num arquivo que não o declara.
      const localWindow = /\b(?:const|let|var)\s+window\b|[(,]\s*window\s*[:,)]/.test(text);
      text.split('\n').forEach((line, i) => {
        for (const [pattern, why] of forbidden) {
          if (localWindow && pattern.source.includes('window')) continue;
          if (pattern.test(line)) violations.push(`${relative(core, f)}:${i + 1} → ${why}`);
        }
      });
    }
    expect(violations, `Violações de pureza:\n${violations.join('\n')}`).toEqual([]);
  });

  it('relógio e sorteio sem semente só onde são declarados', () => {
    const allowed: Record<string, RegExp[]> = {
      [join('lang', 'date-time.ts')]: [/new Date\(/],
      [join('lang', 'random.ts')]: [/Math\.random\(/],
      [join('audit', 'calculation-trace.ts')]: [/Math\.random\(/],
      [join('audit', 'audit-recorder.ts')]: [/Date\.now\(/],
    };
    const patterns = [/new Date\(/, /Date\.now\(/, /Math\.random\(/, /performance\.now\(/];
    const violations: string[] = [];
    for (const f of all) {
      const rel = relative(core, f);
      const lines = code(readFileSync(f, 'utf8')).split('\n');
      lines.forEach((line, i) => {
        for (const p of patterns) {
          if (!p.test(line)) continue;
          if ((allowed[rel] ?? []).some((a) => a.source === p.source)) continue;
          // A medição de tempo da auditoria é metadado do rastro, não cálculo.
          if (rel === join('audit', 'audit-recorder.ts') && p.source === /performance\.now\(/.source) continue;
          violations.push(`${rel}:${i + 1} → ${p.source}`);
        }
      });
    }
    expect(violations, violations.join('\n')).toEqual([]);
  });

  it('DateTime.now() só na forma injetável, `asOf ?? DateTime.now()`', () => {
    const violations: string[] = [];
    for (const f of all) {
      const rel = relative(core, f);
      if (rel === join('lang', 'date-time.ts')) continue;
      // A hora de abertura da transação de auditoria é metadado da observação,
      // como no `AuditTransaction` do Dart — não entra em conta alguma.
      if (rel === join('audit', 'audit-recorder.ts')) continue;
      const lines = code(readFileSync(f, 'utf8')).split('\n');
      lines.forEach((line, i) => {
        if (/DateTime\.now\(\)/.test(line) && !/\?\?\s*DateTime\.now\(\)/.test(line)) {
          violations.push(`${rel}:${i + 1} → ${line.trim()}`);
        }
      });
    }
    expect(violations, violations.join('\n')).toEqual([]);
  });

  it('Math é permitido — é biblioteca da linguagem', () => {
    // O exemplo é `inference.ts`, que precisa de `Math` para a t de Student e a
    // beta incompleta.
    const text = readFileSync(join(core, 'services', 'valuation', 'inference.ts'), 'utf8');
    expect(text).toMatch(/Math\.(log|exp|sqrt|pow)/);
  });
});
