// Estende o histórico das séries macro no cache de validação.
//
// O backtest *point-in-time* precisa da média decenal do CDI **na data da
// coorte**, e o cache começa em 09/2016: para uma avaliação de 2018 a janela
// de dez anos ficava com dois. Isto busca no Banco Central o histórico que
// falta e o grava no mesmo cache, uma vez.
import { DateRange, DateTime } from '../src/core';
import { BcbDatasource } from '../src/data/datasources/bcb-datasource';
import { outln } from './lib/files';
import { ValidationContext } from './validation/context';

const iso = (d: DateTime): string =>
  `${String(d.year).padStart(4, '0')}-${String(d.month).padStart(2, '0')}-${String(d.day).padStart(2, '0')}`;

export async function main(_args: string[]): Promise<void> {
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const range = new DateRange(DateTime.local(2005, 1, 1), DateTime.local(2026, 9, 4));
    const series = new Map<number, string>([
      [BcbDatasource.seriesCdiDaily, 'CDI diário (SGS 12)'],
      [BcbDatasource.seriesIpcaMonthly, 'IPCA mensal (SGS 433)'],
      [BcbDatasource.seriesIbcBrMonthly, 'IBC-Br mensal (SGS 24364)'],
    ]);

    for (const [seriesId, label] of series) {
      // O SGS recusa janela maior que dez anos em série diária, então a busca
      // é fatiada. As fatias se sobrepõem em um dia, e o upsert por chave
      // (série, data) torna a duplicata inofensiva.
      const slices: DateRange[] = [];
      let start = range.start;
      while (start.isBefore(range.end)) {
        const end = DateTime.local(start.year + 9, start.month, start.day);
        slices.push(new DateRange(start, end.isAfter(range.end) ? range.end : end));
        start = end;
      }

      let total = 0;
      let first: DateTime | null = null;
      let last: DateTime | null = null;
      let failed = false;
      for (const slice of slices) {
        const r = await ctx.bcb.series(seriesId, slice);
        if (r.isErr) {
          outln(`${label}: FALHA em ${iso(slice.start)}..${iso(slice.end)} — ${r.failureOrNull?.message}`);
          failed = true;
          continue;
        }
        const s = r.unwrap();
        if (s.isEmpty) continue;
        await ctx.cache.upsertMacro(
          seriesId,
          s.points.map((p) => ({ date: iso(p.date), value: p.rate })),
        );
        total += s.points.length;
        first ??= s.points[0]!.date;
        last = s.points[s.points.length - 1]!.date;
      }
      outln(
        `${label}: ${total} observações${first === null ? '' : ` (${iso(first)} a ${iso(last!)})`}${failed ? '  [com falha parcial]' : ''}`,
      );
    }
  } finally {
    await ctx.dispose();
  }
}
