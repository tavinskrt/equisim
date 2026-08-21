import 'package:drift/drift.dart' show Value;
import 'package:equisim_core/equisim_core.dart';

import '../datasources/local/cache_database.dart';
import '../datasources/local/cache_policy.dart';
import '../datasources/remote/bcb_datasource.dart';
import '../datasources/remote/brapi_datasource.dart';
import '../dtos/brapi_dtos.dart' show BrapiJson;

/// Executa uma operação de cache tolerando falha.
///
/// O cache é **otimização, não requisito**: acelera e torna os resultados
/// reprodutíveis, mas a aplicação precisa funcionar sem ele. Um banco que não
/// abre — falta de asset no alvo web, permissão negada, disco cheio — não pode
/// derrubar a camada de dados inteira.
Future<T?> _tryCache<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (_) {
    return null;
  }
}

/// Cotações, com cache local opcional.
class PriceRepositoryImpl implements PriceRepository {
  final BrapiDatasource remote;

  /// `null` quando o cache não pôde ser inicializado. Tudo passa a vir da rede.
  final CacheDatabase? cache;

  PriceRepositoryImpl({required this.remote, required this.cache});

  @override
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range) async {
    final batch = await dailyBatch([ticker], range);
    return batch.flatMap((map) {
      final series = map[ticker];
      if (series == null) {
        return Err(InsufficientData('Sem cotações para ${ticker.value}.'));
      }
      return Ok(series);
    });
  }

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  ) async {
    if (tickers.isEmpty) return const Ok({});

    final out = <Ticker, PriceSeries>{};
    final missing = <Ticker>[];

    for (final ticker in tickers) {
      final db = cache;
      final fresh = db == null
          ? false
          : await _tryCache(() => db.isFresh(
                    CachePolicy.pricesKey(ticker.value),
                    CachePolicy.historicalPrices,
                  )) ??
              false;
      if (!fresh) {
        missing.add(ticker);
        continue;
      }
      final rows = await _tryCache(() => db.pricesIn(
            ticker.value,
            BrapiJson.isoDay(range.start),
            BrapiJson.isoDay(range.end),
          ));
      if (rows == null || rows.isEmpty) {
        missing.add(ticker);
        continue;
      }
      out[ticker] = PriceSeries(
        ticker: ticker,
        points: rows
            .map((r) => PricePoint(
                  date: DateTime.parse(r.date),
                  close: r.close,
                  adjustedClose: r.adjustedClose,
                ))
            .toList(),
      );
    }

    if (missing.isEmpty) return Ok(out);

    // Um único lote para tudo que faltou.
    final fetched = await remote.historicalBatch(missing);
    if (fetched.isErr) {
      // Havendo cache parcial, entrega o que existe em vez de falhar inteiro.
      return out.isEmpty ? Err(fetched.failureOrNull!) : Ok(out);
    }

    for (final entry in fetched.unwrap().entries) {
      await _persist(entry.key, entry.value);
      out[entry.key] = _slice(entry.value, range);
    }
    return Ok(out);
  }

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(
    Ticker ticker,
    DateRange range,
  ) =>
      daily(ticker, range);

  Future<void> _persist(Ticker ticker, PriceSeries series) async {
    final db = cache;
    if (db == null) return;
    await _tryCache(() async {
      await db.upsertPrices([
        for (final p in series.points)
          CachedPricesCompanion.insert(
            ticker: ticker.value,
            date: BrapiJson.isoDay(p.date),
            close: p.close,
            adjustedClose: Value(p.adjustedClose),
          ),
      ]);
      await db.touch(CachePolicy.pricesKey(ticker.value));
    });
  }

  PriceSeries _slice(PriceSeries series, DateRange range) => PriceSeries(
        ticker: series.ticker,
        points: series.points.where((p) => range.contains(p.date)).toList(),
      );
}

/// Proventos, com cache e higienização de duplicatas exatas.
class DividendRepositoryImpl implements DividendRepository {
  final BrapiDatasource remote;
  final CacheDatabase? cache;

  DividendRepositoryImpl({required this.remote, required this.cache});

  @override
  Future<Result<List<DividendEvent>>> history(Ticker ticker) async {
    final db = cache;
    final fresh = db == null
        ? false
        : await _tryCache(() => db.isFresh(
                  CachePolicy.dividendsKey(ticker.value),
                  CachePolicy.dividends,
                )) ??
            false;
    if (fresh) {
      final rows = await _tryCache(() => db.dividendsOf(ticker.value));
      if (rows != null && rows.isNotEmpty) {
        return Ok(rows
            .map((r) => DividendEvent(
                  ticker: ticker,
                  exDate: DateTime.parse(r.exDate),
                  paymentDate: DateTime.parse(r.paymentDate),
                  amountPerShare: r.amount,
                  kind: DividendKind.fromLabel(r.label),
                  paymentDateEstimated: r.paymentDateEstimated,
                ))
            .toList());
      }
    }

    final fetched = await remote.dividends(ticker);
    if (fetched.isErr) return fetched;

    final events = fetched.unwrap();
    if (db != null) {
      await _tryCache(() async {
        await db.upsertDividends([
          for (final e in events)
            CachedDividendsCompanion.insert(
              ticker: ticker.value,
              exDate: BrapiJson.isoDay(e.exDate),
              paymentDate: BrapiJson.isoDay(e.paymentDate),
              amount: e.amountPerShare,
              label: e.kind.label,
              paymentDateEstimated: Value(e.paymentDateEstimated),
            ),
        ]);
        await db.touch(CachePolicy.dividendsKey(ticker.value));
      });
    }
    return Ok(events);
  }

  @override
  Future<Result<Map<Ticker, List<DividendEvent>>>> historyBatch(
    List<Ticker> tickers,
  ) async {
    final out = <Ticker, List<DividendEvent>>{};
    final failures = <String>[];
    // A brapi não aceita lote em dividends; a concorrência é contida pelo
    // ThrottleInterceptor.
    for (final ticker in tickers) {
      final result = await history(ticker);
      result.fold(
        (events) => out[ticker] = events,
        (failure) => failures.add('${ticker.value}: ${failure.message}'),
      );
    }
    if (out.isEmpty && failures.isNotEmpty) {
      return Err(InsufficientData(
        'Nenhum histórico de proventos obtido. ${failures.join('; ')}',
      ));
    }
    return Ok(out);
  }

  @override
  Future<Result<double>> publishedTrailingYield(Ticker ticker) async {
    final db = cache;
    if (db != null) {
      final cached = await _tryCache(() => db.profileOf(ticker.value));
      if (cached?.publishedDividendYield != null) {
        return Ok(cached!.publishedDividendYield!);
      }
    }
    return remote.publishedDividendYield(ticker);
  }
}

/// Fundamentos e perfil cadastral.
class FundamentalsRepositoryImpl implements FundamentalsRepository {
  final BrapiDatasource remote;
  final CacheDatabase? cache;

  FundamentalsRepositoryImpl({required this.remote, required this.cache});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker) async {
    final db = cache;
    final fresh = db == null
        ? false
        : await _tryCache(() => db.isFresh(
                  CachePolicy.fundamentalsKey(ticker.value),
                  CachePolicy.fundamentals,
                )) ??
            false;
    if (fresh) {
      final rows = await _tryCache(() => db.fundamentalsOf(ticker.value));
      if (rows != null && rows.isNotEmpty) {
        return Ok(rows.map((r) => _toDomain(ticker, r)).toList());
      }
    }

    final fetched = await remote.fundamentalsHistory(ticker);
    if (fetched.isErr) return fetched;

    final snapshots = fetched.unwrap();
    if (db == null) return Ok(snapshots);
    await _tryCache(() async {
      await db.upsertFundamentals([
      for (final s in snapshots)
        CachedFundamentalsTableCompanion.insert(
          ticker: ticker.value,
          fiscalPeriodEnd: BrapiJson.isoDay(s.fiscalPeriodEnd),
          totalRevenue: Value(s.totalRevenue),
          ebit: Value(s.ebit),
          ebitda: Value(s.ebitda),
          netIncome: Value(s.netIncome),
          incomeBeforeTax: Value(s.incomeBeforeTax),
          incomeTaxExpense: Value(s.incomeTaxExpense),
          interestExpense: Value(s.interestExpense),
          earningsPerShare: Value(s.earningsPerShare),
          cash: Value(s.cash),
          shortTermInvestments: Value(s.shortTermInvestments),
          shortTermDebt: Value(s.shortTermDebt),
          longTermDebt: Value(s.longTermDebt),
          totalStockholderEquity: Value(s.totalStockholderEquity),
          bookValuePerShare: Value(s.bookValuePerShare),
          operatingCashFlow: Value(s.operatingCashFlow),
          investmentCashFlow: Value(s.investmentCashFlow),
          freeCashFlow: Value(s.freeCashFlow),
          sharesOutstanding: Value(s.sharesOutstanding),
          marketCap: Value(s.marketCap),
          enterpriseToEbitda: Value(s.enterpriseToEbitda),
        ),
      ]);
      await db.touch(CachePolicy.fundamentalsKey(ticker.value));
    });
    return Ok(snapshots);
  }

  @override
  Future<Result<Asset>> profile(Ticker ticker) async {
    final db = cache;
    final fresh = db == null
        ? false
        : await _tryCache(() => db.isFresh(
                  CachePolicy.profileKey(ticker.value),
                  CachePolicy.profile,
                )) ??
            false;
    if (fresh) {
      final row = await _tryCache(() => db.profileOf(ticker.value));
      if (row != null) {
        return Ok(Asset(
          ticker: ticker,
          name: row.name,
          sector: row.sectorKey == null
              ? Sector.unknown
              : Sector.fromKey(row.sectorKey!,
                  label: row.sectorLabel ?? row.sectorKey!),
          industry: row.industry,
        ));
      }
    }

    final fetched = await remote.profile(ticker);
    if (fetched.isErr) return fetched;

    final asset = fetched.unwrap();
    if (db == null) return Ok(asset);

    final yieldResult = await remote.publishedDividendYield(ticker);
    await _tryCache(() async {
      await db.upsertProfile(CachedProfilesCompanion.insert(
        ticker: ticker.value,
        name: asset.name,
        sectorKey: Value(asset.sector.isUnknown ? null : asset.sector.key),
        sectorLabel: Value(asset.sector.isUnknown ? null : asset.sector.label),
        industry: Value(asset.industry),
        publishedDividendYield: Value(yieldResult.valueOrNull),
      ));
      await db.touch(CachePolicy.profileKey(ticker.value));
    });
    return Ok(asset);
  }

  @override
  Future<Result<List<Ticker>>> universe() => remote.universe();

  FundamentalsSnapshot _toDomain(Ticker ticker, CachedFundamentals r) =>
      FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime.parse(r.fiscalPeriodEnd),
        totalRevenue: r.totalRevenue,
        ebit: r.ebit,
        ebitda: r.ebitda,
        netIncome: r.netIncome,
        incomeBeforeTax: r.incomeBeforeTax,
        incomeTaxExpense: r.incomeTaxExpense,
        interestExpense: r.interestExpense,
        earningsPerShare: r.earningsPerShare,
        cash: r.cash,
        shortTermInvestments: r.shortTermInvestments,
        shortTermDebt: r.shortTermDebt,
        longTermDebt: r.longTermDebt,
        totalStockholderEquity: r.totalStockholderEquity,
        bookValuePerShare: r.bookValuePerShare,
        operatingCashFlow: r.operatingCashFlow,
        investmentCashFlow: r.investmentCashFlow,
        freeCashFlow: r.freeCashFlow,
        sharesOutstanding: r.sharesOutstanding,
        marketCap: r.marketCap,
        enterpriseToEbitda: r.enterpriseToEbitda,
      );
}

/// Índice de mercado.
class BenchmarkRepositoryImpl implements BenchmarkRepository {
  final BrapiDatasource remote;

  BenchmarkRepositoryImpl(this.remote);

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    final fetched = await remote.ibovespa();
    return fetched.map((series) => PriceSeries(
          ticker: series.ticker,
          points:
              series.points.where((p) => range.contains(p.date)).toList(),
        ));
  }
}

/// Variáveis macroeconômicas do Banco Central.
class MacroRepositoryImpl implements MacroRepository {
  final BcbDatasource remote;
  final CacheDatabase? cache;

  MacroRepositoryImpl({required this.remote, required this.cache});

  @override
  Future<Result<RateSeries>> riskFreeDaily(DateRange range) =>
      _series(BcbDatasource.seriesCdiDaily, range);

  @override
  Future<Result<RateSeries>> inflationMonthly(DateRange range) =>
      _series(BcbDatasource.seriesIpcaMonthly, range);

  Future<Result<RateSeries>> _series(int seriesId, DateRange range) async {
    final db = cache;
    final fresh = db == null
        ? false
        : await _tryCache(() => db.isFresh(
                  CachePolicy.macroKey(seriesId),
                  CachePolicy.macro,
                )) ??
            false;
    if (fresh) {
      final rows = await _tryCache(() => db.macroIn(
            seriesId,
            BrapiJson.isoDay(range.start),
            BrapiJson.isoDay(range.end),
          ));
      if (rows != null && rows.isNotEmpty) {
        return Ok(RateSeries(
          dates: rows.map((r) => DateTime.parse(r.date)).toList(),
          rates: rows.map((r) => r.value).toList(),
        ));
      }
    }

    final fetched = await remote.series(seriesId, range);
    if (fetched.isErr) return fetched;

    final series = fetched.unwrap();
    if (db == null) return Ok(series);
    await _tryCache(() async {
      await db.upsertMacro([
        for (var i = 0; i < series.rates.length; i++)
          CachedMacroRatesCompanion.insert(
            seriesId: seriesId,
            date: BrapiJson.isoDay(series.dates[i]),
            value: series.rates[i],
          ),
      ]);
      await db.touch(CachePolicy.macroKey(seriesId));
    });
    return Ok(series);
  }
}
