import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'cache_database.g.dart';

/// Cotações diárias. Um fechamento por ticker por pregão.
@DataClassName('CachedPrice')
class CachedPrices extends Table {
  TextColumn get ticker => text()();

  /// Data do pregão em `yyyy-MM-dd`, para permitir comparação lexicográfica
  /// em consultas de intervalo sem conversão.
  TextColumn get date => text()();

  RealColumn get close => real()();
  RealColumn get adjustedClose => real().nullable()();

  @override
  Set<Column> get primaryKey => {ticker, date};
}

/// Proventos. A chave composta inclui valor e rótulo porque uma mesma data-ex
/// pode legitimamente ter várias tranches (ex.: BBAS3 em 11/03/2025 com dois
/// JCP e um dividendo). A chave elimina apenas duplicatas **exatas**, que a
/// fonte de fato produz.
@DataClassName('CachedDividend')
class CachedDividends extends Table {
  TextColumn get ticker => text()();
  TextColumn get exDate => text()();
  TextColumn get paymentDate => text()();
  RealColumn get amount => real()();
  TextColumn get label => text()();
  BoolColumn get paymentDateEstimated =>
      boolean().withDefault(const Constant(false))();
  TextColumn get remarks => text().nullable()();

  @override
  Set<Column> get primaryKey => {ticker, exDate, paymentDate, amount, label};
}

/// Fundamentos anuais consolidados de todos os demonstrativos.
@DataClassName('CachedFundamentals')
class CachedFundamentalsTable extends Table {
  TextColumn get ticker => text()();
  TextColumn get fiscalPeriodEnd => text()();

  RealColumn get totalRevenue => real().nullable()();
  RealColumn get ebit => real().nullable()();
  RealColumn get ebitda => real().nullable()();
  RealColumn get netIncome => real().nullable()();
  RealColumn get incomeBeforeTax => real().nullable()();
  RealColumn get incomeTaxExpense => real().nullable()();
  RealColumn get interestExpense => real().nullable()();
  RealColumn get earningsPerShare => real().nullable()();
  RealColumn get cash => real().nullable()();
  RealColumn get shortTermInvestments => real().nullable()();
  RealColumn get shortTermDebt => real().nullable()();
  RealColumn get longTermDebt => real().nullable()();
  RealColumn get totalStockholderEquity => real().nullable()();
  RealColumn get bookValuePerShare => real().nullable()();
  RealColumn get operatingCashFlow => real().nullable()();
  RealColumn get investmentCashFlow => real().nullable()();
  RealColumn get freeCashFlow => real().nullable()();
  RealColumn get sharesOutstanding => real().nullable()();
  RealColumn get marketCap => real().nullable()();
  RealColumn get enterpriseToEbitda => real().nullable()();

  @override
  Set<Column> get primaryKey => {ticker, fiscalPeriodEnd};
}

/// Perfil cadastral e classificação setorial.
@DataClassName('CachedProfile')
class CachedProfiles extends Table {
  TextColumn get ticker => text()();
  TextColumn get name => text()();
  TextColumn get sectorKey => text().nullable()();
  TextColumn get sectorLabel => text().nullable()();
  TextColumn get industry => text().nullable()();

  /// Dividend yield 12m publicado pela fonte — insumo do portão de qualidade.
  RealColumn get publishedDividendYield => real().nullable()();

  @override
  Set<Column> get primaryKey => {ticker};
}

/// Séries macroeconômicas do Banco Central (SGS).
@DataClassName('CachedMacroRate')
class CachedMacroRates extends Table {
  /// Código da série no SGS (12 = CDI diário, 433 = IPCA mensal).
  IntColumn get seriesId => integer()();
  TextColumn get date => text()();

  /// Valor já convertido para fração (0,000374 = 0,0374% ao dia).
  RealColumn get value => real()();

  @override
  Set<Column> get primaryKey => {seriesId, date};
}

/// Registro de quando cada recurso foi buscado, para aplicar TTL.
@DataClassName('CacheEntry')
class CacheEntries extends Table {
  /// Chave lógica do recurso (ex.: `prices:PETR4`, `fundamentals:VALE3`).
  TextColumn get key => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    CachedPrices,
    CachedDividends,
    CachedFundamentalsTable,
    CachedProfiles,
    CachedMacroRates,
    CacheEntries,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'equisim_cache'));

  @override
  int get schemaVersion => 1;

  // ------------------------------------------------------------------ TTL --

  /// Verdadeiro se o recurso está em cache e ainda dentro da validade.
  Future<bool> isFresh(String key, Duration ttl) async {
    final entry = await (select(cacheEntries)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (entry == null) return false;
    return DateTime.now().difference(entry.fetchedAt) < ttl;
  }

  Future<void> touch(String key) => into(cacheEntries).insertOnConflictUpdate(
        CacheEntriesCompanion.insert(key: key, fetchedAt: DateTime.now()),
      );

  // --------------------------------------------------------------- Preços --

  Future<List<CachedPrice>> pricesIn(
    String ticker,
    String startIso,
    String endIso,
  ) =>
      (select(cachedPrices)
            ..where((t) =>
                t.ticker.equals(ticker) &
                t.date.isBiggerOrEqualValue(startIso) &
                t.date.isSmallerOrEqualValue(endIso))
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();

  Future<void> upsertPrices(List<CachedPricesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedPrices, rows));

  // ------------------------------------------------------------ Proventos --

  Future<List<CachedDividend>> dividendsOf(String ticker) =>
      (select(cachedDividends)
            ..where((t) => t.ticker.equals(ticker))
            ..orderBy([(t) => OrderingTerm.asc(t.exDate)]))
          .get();

  Future<void> upsertDividends(List<CachedDividendsCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedDividends, rows));

  // ----------------------------------------------------------- Fundamentos --

  Future<List<CachedFundamentals>> fundamentalsOf(String ticker) =>
      (select(cachedFundamentalsTable)
            ..where((t) => t.ticker.equals(ticker))
            ..orderBy([(t) => OrderingTerm.asc(t.fiscalPeriodEnd)]))
          .get();

  Future<void> upsertFundamentals(
    List<CachedFundamentalsTableCompanion> rows,
  ) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedFundamentalsTable, rows));

  // --------------------------------------------------------------- Perfil --

  Future<CachedProfile?> profileOf(String ticker) =>
      (select(cachedProfiles)..where((t) => t.ticker.equals(ticker)))
          .getSingleOrNull();

  Future<void> upsertProfile(CachedProfilesCompanion row) =>
      into(cachedProfiles).insertOnConflictUpdate(row);

  // ---------------------------------------------------------------- Macro --

  Future<List<CachedMacroRate>> macroIn(
    int seriesId,
    String startIso,
    String endIso,
  ) =>
      (select(cachedMacroRates)
            ..where((t) =>
                t.seriesId.equals(seriesId) &
                t.date.isBiggerOrEqualValue(startIso) &
                t.date.isSmallerOrEqualValue(endIso))
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();

  Future<void> upsertMacro(List<CachedMacroRatesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedMacroRates, rows));

  /// Limpa tudo. Usado em testes e na opção de reset do usuário.
  Future<void> clearAll() async {
    await batch((b) {
      b.deleteWhere(cachedPrices, (_) => const Constant(true));
      b.deleteWhere(cachedDividends, (_) => const Constant(true));
      b.deleteWhere(cachedFundamentalsTable, (_) => const Constant(true));
      b.deleteWhere(cachedProfiles, (_) => const Constant(true));
      b.deleteWhere(cachedMacroRates, (_) => const Constant(true));
      b.deleteWhere(cacheEntries, (_) => const Constant(true));
    });
  }
}
