// Estende o histórico das séries macro no cache de validação.
//
// O backtest *point-in-time* precisa da média decenal do CDI **na data da
// coorte**, e o cache começa em 09/2016: para uma avaliação de 2018 a janela
// de dez anos ficava com dois. Isto busca no Banco Central o histórico que
// falta e o grava no mesmo cache, uma vez.
import 'dart:io';

import 'package:equisim/data/datasources/local/cache_database.dart';
import 'package:equisim/data/datasources/remote/bcb_datasource.dart';
import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<void> main() async {
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final range = DateRange(DateTime(2005, 1, 1), DateTime(2026, 9, 4));
    const series = {
      BcbDatasource.seriesCdiDaily: 'CDI diário (SGS 12)',
      BcbDatasource.seriesIpcaMonthly: 'IPCA mensal (SGS 433)',
      BcbDatasource.seriesIbcBrMonthly: 'IBC-Br mensal (SGS 24364)',
    };

    for (final e in series.entries) {
      // O SGS recusa janela maior que dez anos em série diária, então a busca
      // é fatiada. As fatias se sobrepõem em um dia, e o upsert por chave
      // (série, data) torna a duplicata inofensiva.
      final slices = <DateRange>[];
      var start = range.start;
      while (start.isBefore(range.end)) {
        final end = DateTime(start.year + 9, start.month, start.day);
        slices.add(DateRange(start, end.isAfter(range.end) ? range.end : end));
        start = end;
      }

      var total = 0;
      DateTime? first, last;
      var failed = false;
      for (final slice in slices) {
        final r = await ctx.bcb.series(e.key, slice);
        if (r.isErr) {
          stdout.writeln('${e.value}: FALHA em '
              '${_iso(slice.start)}..${_iso(slice.end)} — '
              '${r.failureOrNull?.message}');
          failed = true;
          continue;
        }
        final s = r.unwrap();
        if (s.rates.isEmpty) continue;
        await ctx.cache.upsertMacro([
          for (var i = 0; i < s.rates.length; i++)
            CachedMacroRatesCompanion.insert(
              seriesId: e.key,
              date: _iso(s.dates[i]),
              value: s.rates[i],
            ),
        ]);
        total += s.rates.length;
        first ??= s.dates.first;
        last = s.dates.last;
      }
      stdout.writeln('${e.value}: $total observações'
          '${first == null ? '' : ' (${_iso(first)} a ${_iso(last!)})'}'
          '${failed ? '  [com falha parcial]' : ''}');
    }
  } finally {
    await ctx.dispose();
  }
}
