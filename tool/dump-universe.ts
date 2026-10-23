import { writeText, jsonPretty, outln } from './lib/files';
import { ValidationContext } from './validation/context';

/**
 * Grava o universo da fonte de preços, com nome e setor de cada ticker, em
 * `docs/validacao/universo.json` — a lista que os empacotadores filtram.
 */
export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const universe = (await ctx.fundamentals.universe()).unwrap();
    const profiles: { ticker: string; nome: string | null; setor: string | null }[] = [];
    for (const t of universe) {
      const p = await ctx.fundamentals.profile(t);
      profiles.push({
        ticker: t.value,
        nome: p.isOk ? p.unwrap().name : null,
        setor: p.isOk ? p.unwrap().sector.key : null,
      });
    }
    writeText('docs/validacao/universo.json', jsonPretty(profiles));
    outln(`${profiles.length} tickers -> docs/validacao/universo.json`);
  } finally {
    await ctx.dispose();
  }
}
