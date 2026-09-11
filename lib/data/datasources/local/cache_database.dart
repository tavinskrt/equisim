import 'package:drift/drift.dart';

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

  /// Volume negociado no pregão, em quantidade de papéis.
  ///
  /// Entra com a decisão 25: a Porta 0 filtra por volume financeiro médio, e
  /// sem ele o corte de liquidez não é computável. Nulo em série cacheada antes
  /// da versão 3 do esquema.
  RealColumn get volume => real().nullable()();

  @override
  Set<Column> get primaryKey => {ticker, date};
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

  /// Contagem de ações **do exercício**, antes da sobrescrita pela corrente.
  /// Sem ela não há patrimônio nem capital investido reconstituíveis.
  RealColumn get sharesOutstandingAsOf => real().nullable()();

  RealColumn get marketCap => real().nullable()();
  RealColumn get enterpriseToEbitda => real().nullable()();

  // Linhas que a decisão 25 passou a exigir: NOPAT publicado, o lado
  // operacional do capital investido e o que distingue emissão de bonificação.
  RealColumn get nopat => real().nullable()();
  RealColumn get propertyPlantEquipment => real().nullable()();
  RealColumn get intangibleAssets => real().nullable()();
  RealColumn get totalCurrentAssets => real().nullable()();
  RealColumn get currentLiabilities => real().nullable()();
  RealColumn get realizedShareCapital => real().nullable()();
  RealColumn get profitReserves => real().nullable()();

  // Os dois termos da ponte que a decisão 49 passou a exigir.
  RealColumn get minorityInterest => real().nullable()();
  RealColumn get equityIncomeResult => real().nullable()();

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
    CachedFundamentalsTable,
    CachedProfiles,
    CachedMacroRates,
    CacheEntries,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  /// O executor é injetado por quem constrói: o aplicativo usa o backend do
  /// Flutter, o executor de validação usa SQLite nativo e os testes usam banco
  /// em memória. Manter a escolha fora daqui é o que mantém esta camada livre
  /// de Flutter.
  CacheDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  /// Migrações do cache.
  ///
  /// **Descartar o cache seria alternativa legítima** — ele é reconstruível a
  /// partir da rede. A migração existe porque descartar obrigaria cada usuário
  /// a rebaixar anos de cotação por causa de uma tabela que saiu, e porque a
  /// versão 2 apaga dado que não se quer manter no disco de ninguém.
  ///
  /// v1 → v2: remoção dos proventos. Some a tabela `cached_dividends` inteira
  /// e a coluna `published_dividend_yield` do perfil — ver
  /// `docs/decisoes/023-remocao-de-proventos.md`. A coluna sai por
  /// [TableMigration], que recria a tabela copiando o que resta: `ALTER TABLE
  /// … DROP COLUMN` só existe a partir do SQLite 3.35 e o executor embarcado
  /// varia com o aparelho.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.database
                .customStatement('DROP TABLE IF EXISTS cached_dividends');
            await m.alterTable(TableMigration(cachedProfiles));
            await m.database.customStatement(
              "DELETE FROM cache_entries WHERE key LIKE 'dividends:%'",
            );
          }
          if (from < 3) {
            // v2 → v3: colunas novas da decisão 25. Todas nuláveis, então a
            // adição é aditiva e nenhuma linha existente precisa ser reescrita
            // — o cache repovoa sozinho na próxima busca.
            await m.addColumn(cachedPrices, cachedPrices.volume);
            for (final c in [
              cachedFundamentalsTable.sharesOutstandingAsOf,
              cachedFundamentalsTable.nopat,
              cachedFundamentalsTable.propertyPlantEquipment,
              cachedFundamentalsTable.intangibleAssets,
              cachedFundamentalsTable.totalCurrentAssets,
              cachedFundamentalsTable.currentLiabilities,
              cachedFundamentalsTable.realizedShareCapital,
              cachedFundamentalsTable.profitReserves,
            ]) {
              await m.addColumn(cachedFundamentalsTable, c);
            }
          }
          if (from < 4) {
            // v3 → v4: os dois termos da ponte de equity da decisão 49.
            // Aditivas e nuláveis, como as da v3 — mas, ao contrário
            // daquelas, **o cache não repovoa sozinho**: a validade dos
            // fundamentos é de 30 dias, e uma linha antiga responderia com os
            // campos vazios até ela vencer. A migração invalida a chave de
            // fundamentos para que a próxima leitura vá à fonte.
            for (final c in [
              cachedFundamentalsTable.minorityInterest,
              cachedFundamentalsTable.equityIncomeResult,
            ]) {
              await m.addColumn(cachedFundamentalsTable, c);
            }
            await m.database.customStatement(
              "DELETE FROM cache_entries WHERE key LIKE 'fundamentals:%'",
            );
          }
        },
      );

  // ------------------------------------------------------------------ TTL --

  /// Verdadeiro se o recurso está em cache e ainda dentro da validade.
  ///
  /// - [key]: chave do recurso, construída por `CachePolicy`.
  /// - [ttl]: validade admitida desde a última busca.
  ///
  /// A validade governa a **ponta da série**, não as linhas já guardadas:
  /// responder `false` provoca uma rebusca que soma dias novos aos antigos, e
  /// nunca um descarte. Recurso nunca buscado devolve `false`.
  ///
  /// Lê o relógio do sistema — é controle de cache, não cálculo, e por isso não
  /// viola o determinismo do domínio.
  Future<bool> isFresh(String key, Duration ttl) async {
    final entry = await (select(cacheEntries)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (entry == null) return false;
    return DateTime.now().difference(entry.fetchedAt) < ttl;
  }

  /// Marca o recurso como buscado agora, reiniciando sua validade.
  ///
  /// Chamar **depois** de gravar as linhas: entre a marcação e a gravação, uma
  /// falha deixaria o cache com validade renovada e conteúdo velho.
  Future<void> touch(String key) => into(cacheEntries).insertOnConflictUpdate(
        CacheEntriesCompanion.insert(key: key, fetchedAt: DateTime.now()),
      );

  // --------------------------------------------------------------- Preços --

  /// Cotações de um ativo no intervalo, em ordem cronológica.
  ///
  /// - [ticker]: código do ativo.
  /// - [startIso], [endIso]: bordas inclusivas, em `AAAA-MM-DD`.
  ///
  /// As datas são texto ISO justamente para que a comparação lexicográfica do
  /// SQLite coincida com a cronológica. Devolve lista vazia quando não há nada
  /// em cache — o que é indistinguível de um intervalo realmente sem pregões.
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

  /// Insere ou atualiza cotações em lote, pela chave `(ticker, date)`.
  Future<void> upsertPrices(List<CachedPricesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedPrices, rows));

  // ----------------------------------------------------------- Fundamentos --

  /// Exercícios de um ativo, do mais antigo ao mais recente.
  Future<List<CachedFundamentals>> fundamentalsOf(String ticker) =>
      (select(cachedFundamentalsTable)
            ..where((t) => t.ticker.equals(ticker))
            ..orderBy([(t) => OrderingTerm.asc(t.fiscalPeriodEnd)]))
          .get();

  /// Insere ou atualiza exercícios em lote, pela chave
  /// `(ticker, fiscalPeriodEnd)`.
  Future<void> upsertFundamentals(
    List<CachedFundamentalsTableCompanion> rows,
  ) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedFundamentalsTable, rows));

  // --------------------------------------------------------------- Perfil --

  /// Perfil cadastral de um ativo, ou `null` se não estiver em cache.
  Future<CachedProfile?> profileOf(String ticker) =>
      (select(cachedProfiles)..where((t) => t.ticker.equals(ticker)))
          .getSingleOrNull();

  /// Insere ou atualiza o perfil de um ativo.
  Future<void> upsertProfile(CachedProfilesCompanion row) =>
      into(cachedProfiles).insertOnConflictUpdate(row);

  // ---------------------------------------------------------------- Macro --

  /// Taxas de uma série macro no intervalo, em ordem cronológica.
  ///
  /// - [seriesId]: código SGS do Banco Central (12 = CDI, 433 = IPCA).
  /// - [startIso], [endIso]: bordas inclusivas, em `AAAA-MM-DD`.
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

  /// Insere ou atualiza taxas macro em lote, pela chave `(seriesId, date)`.
  Future<void> upsertMacro(List<CachedMacroRatesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(cachedMacroRates, rows));

  /// Limpa tudo. Usado em testes e na opção de reset do usuário.
  ///
  /// **Irreversível.** Apaga as linhas e as marcas de validade, de modo que a
  /// próxima consulta de cada recurso vá à rede.
  Future<void> clearAll() async {
    await batch((b) {
      b.deleteWhere(cachedPrices, (_) => const Constant(true));
      b.deleteWhere(cachedFundamentalsTable, (_) => const Constant(true));
      b.deleteWhere(cachedProfiles, (_) => const Constant(true));
      b.deleteWhere(cachedMacroRates, (_) => const Constant(true));
      b.deleteWhere(cacheEntries, (_) => const Constant(true));
    });
  }
}
