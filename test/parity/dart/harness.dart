// Oráculo de paridade, lado Dart: roda o núcleo Dart original, compilado para
// JavaScript pelo dart2js (a mesma semântica numérica do aplicativo Flutter na
// web), sobre os pacotes reais do repositório e um mercado sintético
// determinístico, e emite os números de referência gravados em
// test/parity/golden/. O lado TypeScript é test/parity/oracle.ts.
//
// Executado pela última vez sobre o núcleo Dart do commit 3388c0d, antes da
// remoção de packages/equisim_core (decisão 152). Para reproduzir, restaure
// esse diretório a partir daquele commit e siga test/parity/README.md.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

@JS('equisimRead')
external JSString _read(JSString name);

@JS('equisimEmit')
external void _emit(JSString name, JSString text);

@JS('equisimLimit')
external JSNumber _limit();

String readText(String name) => _read(name.toJS).toDart;
void emit(String name, String text) => _emit(name.toJS, text.toJS);
Map<String, dynamic> readJson(String name) =>
    jsonDecode(readText(name)) as Map<String, dynamic>;

final asOf = DateTime(2026, 10, 16);

// ── Utilitários numéricos ─────────────────────────────────────────────────

Object? n(double? x) => x == null ? null : (x.isFinite ? x : x.toString());

double normal(math.Random r) {
  final u1 = r.nextDouble();
  final u2 = r.nextDouble();
  return math.sqrt(-2 * math.log(1 - u1)) * math.cos(2 * math.pi * u2);
}

double round2(double x) => (x * 100).round() / 100;

String day(DateTime d) => d.toIso8601String().substring(0, 10);

List<DateTime> businessDays(DateTime from, DateTime to) {
  final out = <DateTime>[];
  var d = from;
  while (!d.isAfter(to)) {
    if (d.weekday <= 5) out.add(d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

// ── Mercado sintético ─────────────────────────────────────────────────────

class Market {
  final List<DateTime> days;
  final List<double> marketReturns;
  final PriceSeries ibovespa;
  final Map<String, PriceSeries> prices;
  final Map<String, List<FundamentalsSnapshot>> snapshots;
  final Map<String, Asset> profiles;
  final Set<String> failedProfiles;
  final Set<String> distressed;
  Market(this.days, this.marketReturns, this.ibovespa, this.prices,
      this.snapshots, this.profiles, this.failedProfiles, this.distressed);
}

const sectorKeys = [
  'servicos-financeiros',
  'energia',
  'materiais-basicos',
  'consumo',
  'saneamento',
  'tecnologia',
  'saude',
  'industria',
  '',
];

FundamentalsSnapshot copyAs(FundamentalsSnapshot c, Ticker t,
        {required double? marketCap, required double? shares}) =>
    FundamentalsSnapshot(
      ticker: t,
      fiscalPeriodEnd: c.fiscalPeriodEnd,
      totalRevenue: c.totalRevenue,
      ebit: c.ebit,
      ebitda: c.ebitda,
      netIncome: c.netIncome,
      incomeBeforeTax: c.incomeBeforeTax,
      incomeTaxExpense: c.incomeTaxExpense,
      interestExpense: c.interestExpense,
      earningsPerShare: c.earningsPerShare,
      nopat: c.nopat,
      cash: c.cash,
      shortTermInvestments: c.shortTermInvestments,
      shortTermDebt: c.shortTermDebt,
      longTermDebt: c.longTermDebt,
      totalStockholderEquity: c.totalStockholderEquity,
      bookValuePerShare: c.bookValuePerShare,
      propertyPlantEquipment: c.propertyPlantEquipment,
      intangibleAssets: c.intangibleAssets,
      totalCurrentAssets: c.totalCurrentAssets,
      currentLiabilities: c.currentLiabilities,
      realizedShareCapital: c.realizedShareCapital,
      profitReserves: c.profitReserves,
      operatingCashFlow: c.operatingCashFlow,
      investmentCashFlow: c.investmentCashFlow,
      freeCashFlow: c.freeCashFlow,
      sharesOutstanding: shares,
      sharesOutstandingAsOf: c.sharesOutstandingAsOf,
      marketCap: marketCap,
      enterpriseToEbitda: c.enterpriseToEbitda,
      minorityInterest: c.minorityInterest,
      equityIncomeResult: c.equityIncomeResult,
      receiptDate: null,
      treasuryShares: c.treasuryShares,
      treasuryFraction: c.treasuryFraction,
      totalAssets: c.totalAssets,
    );

Market buildMarket(List<String> tickers,
    Map<String, List<CvmPeriodDocument>> docs, Map<String, B3Issuer> registry) {
  final days = businessDays(DateTime(2011, 1, 3), asOf);
  final ibovRng = math.Random(20260914);
  var level = 60000.0;
  final rm = <double>[];
  final ibovPoints = <PricePoint>[];
  for (final d in days) {
    final r = 0.0004 + 0.013 * normal(ibovRng);
    level *= math.exp(r);
    rm.add(r);
    ibovPoints.add(PricePoint(date: d, close: round2(level)));
  }
  final ibov = PriceSeries(ticker: Ticker.parse('IBOV11'), points: ibovPoints);

  final prices = <String, PriceSeries>{};
  final snapshots = <String, List<FundamentalsSnapshot>>{};
  final profiles = <String, Asset>{};
  final failed = <String>{};
  final distressed = <String>{};
  for (var i = 0; i < tickers.length; i++) {
    final code = tickers[i];
    final t = Ticker.parse(code);
    final rng = math.Random(1000 + i);
    final beta = 0.3 + 1.4 * rng.nextDouble();
    final idio = 0.008 + 0.025 * rng.nextDouble();
    final drift = -0.0002 + 0.0006 * rng.nextDouble();
    final pbShock = normal(rng);
    final liquidityShock = normal(rng);
    final fallbackPrice = 5 + 45 * rng.nextDouble();
    final sharesDraw = rng.nextDouble();

    // O último DFP publicado ancora o nível de preço.
    final dfps = [
      for (final d in docs[code] ?? const <CvmPeriodDocument>[])
        if (d.kind == CvmDocumentKind.dfp && !d.periodEnd.isAfter(asOf)) d,
    ]..sort((a, b) => a.periodEnd.compareTo(b.periodEnd));
    final last = dfps.isEmpty ? null : dfps.last.current;
    final equity = last?.totalStockholderEquity;
    final shares = last?.sharesOutstanding ??
        registry[code.substring(0, 4)]?.totalShares ??
        (1e8 * (1 + 9 * sharesDraw)).roundToDouble();
    var target = (equity != null && equity > 0 && shares > 0)
        ? math.exp(-0.3 + 0.6 * pbShock) * equity / shares
        : fallbackPrice;
    if (target < 0.5) target = 0.5;
    if (target > 500) target = 500;

    var start = 0;
    if (i % 17 == 0) start = days.length - 200;
    final cum = <double>[];
    var acc = 0.0;
    for (var k = start; k < days.length; k++) {
      acc += drift + beta * (rm[k] - 0.0004) + idio * normal(rng);
      cum.add(acc);
    }
    final points = <PricePoint>[];
    final tradedValue = math.exp(math.log(1.2e7) + 1.4 * liquidityShock);
    for (var k = 0; k < cum.length; k++) {
      var close = round2(target * math.exp(cum[k] - cum.last));
      if (close < 0.01) close = 0.01;
      final double? volume = i % 13 == 0
          ? null
          : (tradedValue / close * math.exp(0.3 * normal(rng))).roundToDouble();
      points.add(PricePoint(date: days[start + k], close: close, volume: volume));
    }
    if (i % 23 != 0) prices[code] = PriceSeries(ticker: t, points: points);

    // Fundamentos «de mercado»: valor de mercado e ações no fim de cada ano;
    // um em cada quatro ativos traz o exercício inteiro, como a brapi.
    final market = <FundamentalsSnapshot>[];
    for (var y = 2011; y <= 2025; y++) {
      final end = DateTime(y, 12, 31);
      PricePoint? atEnd;
      for (final p in points) {
        if (!p.date.isAfter(end)) atEnd = p;
      }
      FundamentalsSnapshot? dfpOfYear;
      for (final d in dfps) {
        if (d.periodEnd.year == y) dfpOfYear = d.current;
      }
      final s = dfpOfYear?.sharesOutstanding ?? shares;
      final cap = atEnd == null ? null : atEnd.close * s;
      if (i % 4 == 0 && dfpOfYear != null) {
        market.add(copyAs(dfpOfYear, t, marketCap: cap, shares: s));
      } else {
        market.add(FundamentalsSnapshot(
          ticker: t,
          fiscalPeriodEnd: end,
          marketCap: cap,
          sharesOutstanding: s,
        ));
      }
    }
    snapshots[code] = market;

    if (i % 11 == 0) {
      failed.add(code);
    } else {
      final key = sectorKeys[i % sectorKeys.length];
      profiles[code] = Asset(
        ticker: t,
        name: 'Companhia $code',
        sector: key.isEmpty ? Sector.unknown : Sector.fromKey(key, label: key),
        industry: i % 5 == 0 ? 'Energia Elétrica' : null,
      );
    }
    if (i % 37 == 5) distressed.add(code);
  }
  return Market(days, rm, ibov, prices, snapshots, profiles, failed, distressed);
}

// ── Repositórios em memória ───────────────────────────────────────────────

class MemoryPrices implements PriceRepository {
  final Market m;
  MemoryPrices(this.m);

  @override
  Future<Result<PriceSeries>> daily(Ticker ticker, DateRange range) async {
    final s = m.prices[ticker.value];
    if (s == null) {
      return Err(InsufficientData('Sem cotações de ${ticker.value}.',
          subject: ticker.value));
    }
    return Ok(PriceSeries(
      ticker: ticker,
      points: [for (final p in s.points) if (range.contains(p.date)) p],
    ));
  }

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
      List<Ticker> tickers, DateRange range) async {
    final out = <Ticker, PriceSeries>{};
    for (final t in tickers) {
      final r = await daily(t, range);
      if (r.isOk) out[t] = r.unwrap();
    }
    return Ok(out);
  }

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(
          Ticker ticker, DateRange range) =>
      daily(ticker, range);
}

class MemoryBenchmark implements BenchmarkRepository {
  final Market m;
  MemoryBenchmark(this.m);

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async => Ok(PriceSeries(
        ticker: m.ibovespa.ticker,
        points: [
          for (final p in m.ibovespa.points)
            if (range.contains(p.date)) p,
        ],
      ));
}

class MemoryMacro implements MacroRepository {
  final Market m;
  MemoryMacro(this.m);

  @override
  Future<Result<RateSeries>> riskFreeDaily(DateRange range) async {
    final pts = <RatePoint>[];
    for (var k = 0; k < m.days.length; k++) {
      final d = m.days[k];
      if (!range.contains(d)) continue;
      final annual = 0.10 + 0.04 * math.sin(k / 400);
      pts.add(RatePoint(date: d, rate: math.pow(1 + annual, 1 / 252) - 1));
    }
    return Ok(RateSeries(pts));
  }

  List<DateTime> _months(DateRange range) => [
        for (var y = 2011; y <= 2026; y++)
          for (var mo = 1; mo <= 12; mo++)
            if (range.contains(DateTime(y, mo, 1))) DateTime(y, mo, 1),
      ];

  @override
  Future<Result<RateSeries>> inflationMonthly(DateRange range) async {
    final ms = _months(range);
    return Ok(RateSeries([
      for (var k = 0; k < ms.length; k++)
        RatePoint(date: ms[k], rate: 0.0035 + 0.0015 * math.sin(k / 5)),
    ], basis: TimeBasis.monthly));
  }

  @override
  Future<Result<RateSeries>> activityIndexMonthly(DateRange range) async {
    final ms = _months(range);
    return Ok(RateSeries([
      for (var k = 0; k < ms.length; k++)
        RatePoint(
            date: ms[k],
            rate: 130 * math.pow(1.002, k) * (1 + 0.01 * math.sin(k / 3))),
    ], basis: TimeBasis.monthly));
  }
}

class MemoryFundamentals implements FundamentalsRepository {
  final Market m;
  final List<Ticker> all;
  MemoryFundamentals(this.m, this.all);

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker) async {
    final s = m.snapshots[ticker.value];
    if (s == null) {
      return Err(InsufficientData('Sem exercícios de ${ticker.value}.'));
    }
    return Ok(s);
  }

  @override
  Future<Result<Asset>> profile(Ticker ticker) async {
    final p = m.profiles[ticker.value];
    if (p == null) {
      return Err(InsufficientData('Perfil de ${ticker.value} indisponível.'));
    }
    return Ok(p);
  }

  @override
  Future<Result<List<Ticker>>> universe() async => Ok(all);
}

class FromCvm implements FundamentalsRepository {
  final FundamentalsRepository market;
  final Map<String, List<CvmPeriodDocument>> docs;
  final bool anchored;
  FromCvm(this.market, this.docs, {this.anchored = false});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await market.history(t);
    if (base.isErr) return base;
    final own = docs[t.value];
    if (own == null || own.isEmpty) return base;
    return Ok(CvmSeries.build(
      documents: own,
      market: base.unwrap(),
      published: PointInTimeView(asOf).isPublished,
      anchored: anchored,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => market.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => market.universe();
}

class OfficialSector implements FundamentalsRepository {
  final FundamentalsRepository inner;
  final Map<String, B3Issuer> registry;
  OfficialSector(this.inner, this.registry);

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) =>
      inner.history(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();

  @override
  Future<Result<Asset>> profile(Ticker ticker) async {
    final profile = await inner.profile(ticker);
    final t = ticker.value;
    final official = t.length < 4 ? null : registry[t.substring(0, 4)]?.classification;
    if (official == null) return profile;
    final sector = Sector(key: official.sectorKey, label: official.sector);
    final industry = official.industry.isEmpty ? null : official.industry;
    return Ok(Asset(
      ticker: ticker,
      name: profile.isOk ? profile.unwrap().name : ticker.value,
      sector: sector,
      industry: industry,
    ));
  }
}

// ── Serialização ──────────────────────────────────────────────────────────

Map<String, Object?> failureJson(Failure f) => {
      'falha': f.runtimeType.toString(),
      'mensagem': f.message,
    };

Map<String, Object?>? normalizationJson(BaseNormalization? b) => b == null
    ? null
    : {
        'lane': b.lane.name,
        'latestYear': b.latestYear,
        'latestReturn': n(b.latestReturn),
        'cycleWindow': [
          for (final w in b.cycleWindow) [w.year, n(w.value)],
        ],
        'cycleReturn': n(b.cycleReturn),
        'ratio': n(b.ratio),
        'robustZ': n(b.robustZ),
        'deviates': b.deviates,
        'trendSlope': n(b.trendSlope),
        'trendT': n(b.trendT),
        'trendCriticalT': n(b.trendCriticalT),
        'trendDominates': b.trendDominates,
        'cyclicalPrecedence': b.cyclicalPrecedence,
        'operationalDecline': n(b.operationalDecline),
        'healthCapped': b.healthCapped,
        'healthExempt': b.healthExempt,
        'rawFactor': n(b.rawFactor),
        'factor': n(b.factor),
        'saturated': b.saturated,
        'rebuilt': b.rebuilt,
        'rebuiltPositiveShare': n(b.rebuiltPositiveShare),
        'imposed': b.imposed,
        'publishedProfit': n(b.publishedProfit),
        'baseProfit': n(b.baseProfit),
        'outcome': b.outcome.key,
      };

Map<String, Object?>? diagnosticsJson(ValuationDiagnostics? d) => d == null
    ? null
    : {
        'terminalShare': n(d.terminalShare),
        'equityShare': n(d.equityShare),
        'baseFactor': n(d.baseFactor),
        'growthIdentified': d.growthIdentified,
        'moatApplied': d.moatApplied,
        'terminalDiscountRate': n(d.terminalDiscountRate),
        'terminalRetainedSpread': n(d.terminalRetainedSpread),
        'growthRate': n(d.growthRate),
        'returnOnCapital': n(d.returnOnCapital),
        'terminalReturnOnCapital': n(d.terminalReturnOnCapital),
        'firmTaxRate': n(d.firmTaxRate),
        'terminalCostOfEquity': n(d.terminalCostOfEquity),
        'costOfEquity': n(d.costOfEquity),
        'retentionPath': [for (final x in d.retentionPath) n(x)],
        'growthPath': [for (final x in d.growthPath) n(x)],
        'terminalExcessShare': n(d.terminalExcessShare),
        'impliedTerminalReturn': n(d.impliedTerminalReturn),
        'terminalEquityShare': n(d.terminalEquityShare),
        'postStatementCapital': n(d.postStatementCapital),
        'baseNormalization': normalizationJson(d.baseNormalization),
        'caveats': [for (final c in d.caveats) c.key],
      };

Map<String, Object?>? triangulationJson(PeerTriangulation? t) => t == null
    ? null
    : {
        'readings': [
          for (final r in t.readings)
            {
              'kind': r.kind.key,
              'fairValuePerShare': n(r.fairValuePerShare),
              'peer': r.peer == null
                  ? null
                  : {
                      'median': n(r.peer!.median),
                      'peers': r.peer!.peers,
                      'group': r.peer!.group,
                    },
              'refusal': r.refusal?.key,
              'applied': r.applied,
            },
        ],
        'consolidated': n(t.consolidated),
        'divergence': n(t.divergence),
        'asOf': t.asOf.toIso8601String(),
        'applied': t.applied,
        'diverges': t.diverges,
      };

late List<CalibratedBandTable> bandTables;

Map<String, Object?> resultJson(Result<ValuationResult> r) {
  if (r.isErr) return failureJson(r.failureOrNull!);
  final v = r.unwrap();
  final dist = v.distribution;
  return {
    'ticker': v.ticker.value,
    'asOf': v.asOf.toIso8601String(),
    'model': v.model.name,
    'fairValue': v.fairValue.cents,
    'marketPrice': v.marketPrice.cents,
    'discountRate': n(v.discountRate),
    'marginOfSafety': n(v.marginOfSafety),
    'mode': v.mode.name,
    'discreteScenarios': v.discreteScenarios == null
        ? null
        : {
            for (final e in v.discreteScenarios!.entries)
              e.key.name: e.value.cents,
          },
    'distribution': dist == null
        ? null
        : {
            'n': dist.sortedValues.length,
            'p5': n(dist.p5),
            'median': n(dist.median),
            'p95': n(dist.p95),
            'mean': n(dist.mean),
            'aboveMarket': n(dist.probabilityAbove(v.marketPrice.reais)),
            'values': dist.sortedValues.join(','),
          },
    'warnings': v.warnings,
    'diagnostics': diagnosticsJson(v.diagnostics),
    'priceVolatility': n(v.priceVolatility),
    'triangulation': triangulationJson(v.triangulation),
    'safetyPrice': v.safetyPrice.cents,
    'upside': n(v.upside),
    'isUndervalued': v.isUndervalued,
    'bands': [
      for (final t in bandTables)
        () {
          final b = CalibratedBand.of(v.fairValue, t,
              marketPrice: v.marketPrice, volatility: v.priceVolatility);
          return b == null ? null : [t.months, b.low.cents, b.high.cents];
        }(),
    ],
  };
}

// ── Montagens ─────────────────────────────────────────────────────────────

AuditEvent? lastEvent;

Map<String, Object?> evaluate(String key, ValuationInputs i,
    {bool random = false}) {
  lastEvent = null;
  final r = ValuationCascade.evaluate(
    i,
    scenarioBuilder: random ? StochasticScenarios.around : null,
    monteCarloSamples: 300,
  );
  final ev = lastEvent;
  final j = ev?.toJson();
  if (j != null) {
    emit('trace:$key', jsonEncode({
      'endpoint': j['endpoint'],
      'entrada': j['inputPayload'],
      'saida': j['outputPayload'],
      'calculos': j['calculations'],
    }));
  }
  return resultJson(r);
}

Future<void> main() async {
  final curve = TreasuryCurve.at(
      TreasuryQuotesCodec.decode(readJson('assets/tesouro/curva.json')), asOf);
  final registry =
      B3RegistryCodec.decodePackage(readJson('assets/b3/emissores.json'));
  final docs =
      CvmDocumentCodec.decodePackage(readJson('assets/cvm/documentos.json'));
  final terms = ConcessionTermsCodec.decode(readJson('assets/cvm/outorgas.json'));
  final dividends = CashDividendsCodec.decode(readJson('assets/b3/proventos.json'));
  final packagePrior =
      BetaPriorCodec.decode(readJson('assets/mercado/beta_prior.json'));
  final premiumPackage =
      ImpliedPremiumCodec.decode(readJson('assets/mercado/premio_implicito.json'));
  final packagePremium = premiumPackage?.normalizedAt(asOf);
  final capital =
      CapitalEventsCodec.decodePackage(readJson('assets/cvm/capital.json'));
  final units =
      UnitCompositionCodec.decodePackage(readJson('assets/cvm/units.json'));
  final control =
      ShareholderControlHistory.decode(readJson('assets/cvm/controle.json'))
              ?.byIssuer ??
          const <String, List<ShareholderControlPeriod>>{};
  final peers =
      PeerMultipleCodec.decode(readJson('assets/mercado/multiplos_setoriais.json'));
  bandTables =
      CalibratedBandCodec.decode(readJson('assets/validacao/banda_calibrada.json'));

  final codes = docs.keys.toList()..sort();
  final limit = _limit().toDartInt;
  final tickers = [for (final c in codes) Ticker.parse(c)];
  final market = buildMarket(codes, docs, registry);
  final memory = MemoryFundamentals(market, tickers);
  final prices = MemoryPrices(market);
  final benchmark = MemoryBenchmark(market);
  final macro = MemoryMacro(market);

  bool stateOwned(Ticker t) {
    final p = control[t.value.substring(0, 4)];
    return p != null && ShareholderControlHistory.at(p, asOf) == ShareholderControl.state;
  }

  AuditRecorder.attach((e) => lastEvent = e);

  final anchors = (await ResolveMarketAnchors.call(
    macro: macro,
    benchmark: benchmark,
    asOf: asOf,
  ))
      .getOrElse(MarketAnchors.fallback2026);

  final withSector = OfficialSector(FromCvm(memory, docs), registry);
  final anchoredWithSector =
      OfficialSector(FromCvm(memory, docs, anchored: true), registry);
  List<CashDividend> dividendsOf(Ticker t) =>
      CashDividendsCodec.forTicker(dividends, t.value);

  final prior = await ResolveBetaPrior.call(
    tickers: tickers,
    prices: prices,
    fundamentals: withSector,
    benchmark: benchmark,
    asOf: asOf,
    dividendsFor: dividendsOf,
  );

  emit('header', jsonEncode({
    'asOf': asOf.toIso8601String(),
    'tickers': codes.length,
    'anchors': {
      'riskFreeCagr': n(anchors.riskFreeCagr),
      'currentRiskFreeRate': n(anchors.currentRiskFreeRate),
      'marketCagr': n(anchors.marketCagr),
      'inflationCagr': n(anchors.inflationCagr),
      'realEconomyGrowth': n(anchors.realEconomyGrowth),
      'observedYears': anchors.observedYears,
      'nominalEconomyGrowth': n(anchors.nominalEconomyGrowth),
    },
    'curve': curve == null
        ? null
        : {
            'referenceDate': curve.referenceDate.toIso8601String(),
            'vertices': [
              for (final v in curve.vertices) [n(v.years), n(v.rate)],
            ],
          },
    'premium': n(packagePremium),
    'packagePrior': packagePrior == null
        ? null
        : {
            'universe': n(packagePrior.prior.unleveredUniverse),
            'dispersion': n(packagePrior.prior.dispersion),
            'sectors': {
              for (final e in packagePrior.prior.unleveredBySector.entries)
                e.key: n(e.value),
            },
          },
    'resolvedPrior': prior == null
        ? null
        : {
            'universe': n(prior.unleveredUniverse),
            'dispersion': n(prior.dispersion),
            'sectors': {
              for (final e in prior.unleveredBySector.entries) e.key: n(e.value),
            },
          },
    'bandTables': bandTables.length,
  }));

  Future<Result<ValuationInputs>> prepare(
    Ticker t, {
    required FundamentalsRepository fundamentals,
    YieldCurve? c,
    bool app = false,
    bool withPrior = false,
    double marginOfSafety = 0.0,
    int projectionYears = 10,
  }) {
    final e = t.value.length < 4 ? null : registry[t.value.substring(0, 4)];
    return PrepareValuationInputs.call(
      ticker: t,
      prices: prices,
      fundamentals: fundamentals,
      benchmark: benchmark,
      riskFreeRate: anchors.currentRiskFreeRate,
      asOf: asOf,
      marketPremium: app && packagePremium != null
          ? packagePremium
          : CapmInputs.defaultMarketPremium,
      premiumSource: app && packagePremium != null
          ? MarketPremiumSource.impliedNormalized
          : MarketPremiumSource.parameterized,
      perpetualGrowthCap: anchors.nominalEconomyGrowth,
      inflation: anchors.inflationCagr,
      terminalRiskFreeRate: anchors.riskFreeCagr,
      riskFreeCurve: c,
      marginOfSafety: marginOfSafety,
      projectionYears: projectionYears,
      officialShares: app && e?.totalShares != null
          ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
          : null,
      isDistressed: app && market.distressed.contains(t.value),
      concessionEnd: app ? terms[t.value]?.end : null,
      dividends: app ? dividendsOf(t) : null,
      betaPrior: withPrior ? prior : (app ? packagePrior?.prior : null),
      declaredSharesPerUnit: app
          ? UnitCompositionCodec.at(units[t.value] ?? const [], asOf)?.shares
          : null,
      peerMultiples: app ? peers[t.value] : null,
      shareEvents: app ? capital[t.value]?.shareEvents ?? const [] : const [],
      shareIssues: app ? capital[t.value]?.issues ?? const [] : const [],
      stateControlled: app && stateOwned(t),
    );
  }

  final shifts = [-0.02, -0.005, 0.01, 0.03];
  final priorInputs = <String, ValuationInputs>{};
  var count = 0;
  for (final t in tickers) {
    if (limit > 0 && count >= limit) break;
    count++;
    final row = <String, Object?>{};
    Future<void> assembly(
      String name,
      Future<Result<ValuationInputs>> prep,
      Map<String, Object?> Function(String key, ValuationInputs) f,
    ) async {
      lastEvent = null;
      final p = await prep;
      if (p.isErr) {
        final ev = lastEvent;
        row[name] = {
          'preparo': failureJson(p.failureOrNull!),
          'evento': ev == null
              ? null
              : jsonEncode({
                  'endpoint': ev.endpoint,
                  'entrada': ev.inputPayload,
                  'saida': ev.outputPayload,
                }),
        };
        return;
      }
      row[name] = f('${t.value}/$name', p.unwrap());
    }

    await assembly('doisPontos', prepare(t, fundamentals: memory), evaluate);
    await assembly('curva', prepare(t, fundamentals: memory, c: curve), evaluate);
    await assembly('aplicativo',
        prepare(t, fundamentals: withSector, c: curve, app: true), evaluate);
    await assembly('ancorada',
        prepare(t, fundamentals: anchoredWithSector, c: curve, app: true),
        evaluate);
    await assembly('semCurva',
        prepare(t, fundamentals: withSector, app: true), evaluate);
    final withPrior =
        prepare(t, fundamentals: withSector, c: curve, app: true, withPrior: true);
    await assembly('prior', withPrior, (k, i) {
      priorInputs[t.value] = i;
      return evaluate(k, i);
    });
    await assembly('monteCarlo', withPrior,
        (k, i) => evaluate(k, i, random: true));
    await assembly('viaFirma', withPrior,
        (k, i) => evaluate(k, i.withOverrides(lane: ValuationLane.firm)));
    await assembly('viaAcionista', withPrior,
        (k, i) => evaluate(k, i.withOverrides(lane: ValuationLane.shareholder)));
    await assembly(
        'impostos',
        withPrior,
        (k, i) => evaluate(
            k,
            i.withOverrides(
              terminalReturn: 0.13,
              growth: 0.06,
              baseFactor: 1.1,
              reinvestment: ReinvestmentPolicy.realGrowth,
              cashTiming: CashTiming.endOfYear,
            )));
    await assembly(
        'margemCurta',
        prepare(t,
            fundamentals: withSector,
            c: curve,
            app: true,
            marginOfSafety: 0.25,
            projectionYears: 7),
        evaluate);
    await assembly('notas', withPrior, (k, i) {
      final r = ValuationCascade.evaluate(
          i.withContextNotes(['nota de contexto do oráculo']));
      return resultJson(r);
    });
    await assembly('deslocamentos', withPrior, (k, i) {
      return {
        for (final d in shifts)
          '$d': () {
            final r = ValuationCascade.evaluate(i.withRiskFreeShift(d));
            if (r.isErr) return failureJson(r.failureOrNull!);
            final v = r.unwrap();
            return {
              'model': v.model.name,
              'fairValue': v.fairValue.cents,
              'discountRate': n(v.discountRate),
              'warnings': v.warnings.length,
            };
          }(),
      };
    });
    emit('row:${t.value}', jsonEncode(row));
  }
  AuditRecorder.detach();
  emit('services', jsonEncode(services(
    market: market,
    tickers: tickers,
    anchors: anchors,
    priorInputs: priorInputs,
    withSector: withSector,
    histories: {
      for (final t in tickers)
        t.value: (await withSector.history(t)).valueOrNull ??
            const <FundamentalsSnapshot>[],
    },
    profiles: {
      for (final t in tickers) t.value: (await withSector.profile(t)).valueOrNull,
    },
    skill: SkillReadingCodec.decode(readJson('assets/validacao/habilidade.json')),
    premium: packagePremium ?? CapmInputs.defaultMarketPremium,
  )));
  emit('done', '$count');
}

// ── Serviços além da cascata ──────────────────────────────────────────────

Map<String, Object?> premisesJson(ManualPremises p) => {
      'baseProfit': n(p.baseProfit),
      'growth': n(p.growth),
      'growthPath': p.growthPath.name,
      'discountRate': n(p.discountRate),
      'ratePath': p.ratePath.name,
      'perpetualGrowth': n(p.perpetualGrowth),
      'reinvestment': p.reinvestment.name,
      'returnOnCapital': n(p.returnOnCapital),
      'retention': n(p.retention),
      'terminalReturn': n(p.terminalReturn),
    };

Map<String, Object?> manualOutcomeJson(Result<ManualOutcome> r) {
  if (r.isErr) return failureJson(r.failureOrNull!);
  final o = r.unwrap();
  return {
    'fairValuePerShare': n(o.fairValuePerShare),
    'equityValue': n(o.equityValue),
    'explicitPresentValue': n(o.explicitPresentValue),
    'terminalValue': n(o.terminalValue),
    'terminalPresentValue': n(o.terminalPresentValue),
    'minorityInterest': n(o.minorityInterest),
    'postStatementCapital': n(o.postStatementCapital),
    'terminalRate': n(o.terminalRate),
    'capitalCostRates': o.capitalCostRates == null
        ? null
        : [for (final x in o.capitalCostRates!) n(x)],
    'terminalCapitalCost': n(o.terminalCapitalCost),
    'terminalKind': o.terminalKind.name,
    'years': [
      for (final y in o.years)
        [
          y.year,
          n(y.growth),
          n(y.plannedGrowth),
          n(y.profit),
          n(y.retention),
          n(y.firmFlow),
          n(y.debtService),
          n(y.flow),
          n(y.rate),
          n(y.discountFactor),
          n(y.presentValue),
        ],
    ],
    'notices': [
      for (final x in o.notices) [x.kind.name, x.years],
    ],
  };
}

Map<String, Object?> manualJson(ManualValuation m, math.Random rng, Ticker t) {
  final engine = m.enginePremises;
  double jitter(double x, double spread) => x + spread * (2 * rng.nextDouble() - 1);
  final variants = <ManualPremises>[
    engine,
    engine.copyWith(growth: jitter(engine.growth, 0.05)),
    engine.copyWith(discountRate: jitter(engine.discountRate, 0.03)),
    engine.copyWith(
        perpetualGrowth: jitter(engine.perpetualGrowth, 0.01),
        growthPath: ManualGrowthPath.constant),
    engine.copyWith(
        reinvestment: ManualReinvestment.fixedFraction,
        retention: 0.2 + 0.6 * rng.nextDouble()),
    engine.copyWith(
        returnOnCapital: jitter(engine.returnOnCapital, 0.08),
        terminalReturn: 0.08 + 0.1 * rng.nextDouble()),
    engine.copyWith(
        ratePath: ManualRatePath.constant,
        discountRate: jitter(engine.discountRate, 0.02),
        baseProfit: engine.baseProfit * (0.7 + 0.6 * rng.nextDouble())),
    engine.copyWith(baseProfit: -1.0),
  ];
  final last = variants[6];
  final record = ManualValuationRecord.capture(
    id: 'oraculo-${t.value}',
    ticker: t,
    engineAsOf: asOf,
    valuation: m,
    premises: last,
    savedAt: DateTime.utc(2026, 10, 16, 12, 30),
  );
  final recordJson = record.isOk ? record.unwrap().toJson() : null;
  final reread =
      recordJson == null ? null : ManualValuationRecord.fromJson(jsonDecode(jsonEncode(recordJson)) as Map<String, dynamic>);
  return {
    'lane': m.lane.name,
    'shares': n(m.shares),
    'marketPrice': n(m.marketPrice),
    'engineFairValue': n(m.engineFairValue),
    'projectionYears': m.projectionYears,
    'isConcession': m.isConcession,
    'engine': premisesJson(engine),
    'variants': [
      for (final v in variants)
        {
          'premises': premisesJson(v),
          'outcome': manualOutcomeJson(m.evaluate(v)),
        },
    ],
    'attribution': [
      for (final s in m.attribution(last))
        {'groups': [for (final g in s.groups) g.name], 'from': n(s.from), 'to': n(s.to)},
    ],
    'solve': [
      for (final f in ManualField.values)
        () {
          final s = m.solve(f, last);
          return [f.name, n(s.target), n(s.value), n(s.closestValue), n(s.closestPrice)];
        }(),
    ],
    'record': record.isErr ? failureJson(record.failureOrNull!) : jsonEncode(recordJson),
    'reread': reread == null ? null : jsonEncode(reread.toJson()),
  };
}

String seriesText(List<double> xs) => xs.join(',');

Map<String, Object?> backtestJson(Result<BacktestOutcome> r) {
  if (r.isErr) return failureJson(r.failureOrNull!);
  final o = r.unwrap();
  final m = o.metrics;
  final tickers = o.perAsset.keys.toList()..sort();
  return {
    'start': o.effectivePeriod.start.toIso8601String(),
    'end': o.effectivePeriod.end.toIso8601String(),
    'dates': o.dates.length,
    'firstDate': o.dates.isEmpty ? null : o.dates.first.toIso8601String(),
    'lastDate': o.dates.isEmpty ? null : o.dates.last.toIso8601String(),
    'wealth': seriesText(o.wealth),
    'base100': seriesText(o.base100),
    'totalContributed': o.totalContributed.cents,
    'totalAllocated': o.totalAllocated.cents,
    'transactionCosts': o.transactionCosts.cents,
    'finalValue': o.finalValue.cents,
    'residualCash': o.residualCash.cents,
    'metrics': {
      'twr': n(m.timeWeightedReturn),
      'mwr': n(m.moneyWeightedReturn),
      'cagr': n(m.cagr),
      'volatility': n(m.volatility),
      'maxDrawdown': n(m.maxDrawdown),
      'sharpe': n(m.sharpe),
      'sortino': n(m.sortino),
      'calmar': n(m.calmar),
    },
    'perAsset': [
      for (final t in tickers)
        () {
          final a = o.perAsset[t]!;
          return [
            t.value,
            n(a.targetWeight.value),
            n(a.currentWeight),
            n(a.totalReturn),
            a.invested.cents,
            a.finalValue.cents,
            a.cash.cents,
            a.shares,
            n(a.drift),
          ];
        }(),
    ],
    'warnings': o.warnings,
  };
}

Map<String, Object?> services({
  required Market market,
  required List<Ticker> tickers,
  required MarketAnchors anchors,
  required Map<String, ValuationInputs> priorInputs,
  required FundamentalsRepository withSector,
  required Map<String, List<FundamentalsSnapshot>> histories,
  required Map<String, Asset?> profiles,
  required SkillReading? skill,
  required double premium,
}) {
  final valuations = <Ticker, ValuationResult>{};
  final manual = <String, Object?>{};
  var i = 0;
  for (final t in tickers) {
    final inputs = priorInputs[t.value];
    i++;
    if (inputs == null) continue;
    final r = ValuationCascade.evaluate(inputs);
    if (r.isErr) continue;
    final v = r.unwrap();
    valuations[t] = v;
    final m = v.manual;
    if (m != null) manual[t.value] = manualJson(m, math.Random(7000 + i), t);
  }

  final priced = [for (final t in tickers) if (market.prices.containsKey(t.value)) t];
  final longPriced = [
    for (final t in priced)
      if (market.prices[t.value]!.points.length > 1000) t,
  ];
  Asset assetOf(Ticker t) =>
      profiles[t.value] ?? Asset(ticker: t, name: t.value);

  final costs = [
    TransactionCosts.none,
    TransactionCosts.b3,
    TransactionCosts(
        feePartsPerMillion: 250, brokeragePerOrder: Money.fromReais(4.5)),
  ];
  final backtests = <Object?>[];
  final alignments = <Object?>[];
  final concentrations = <Object?>[];
  final swaps = <Object?>[];
  final portfolios = <Portfolio>[];
  for (var j = 0; j < 80; j++) {
    final rng = math.Random(9000 + j);
    final k = 1 + rng.nextInt(15);
    final chosen = <Ticker>[];
    var guard = 0;
    while (chosen.length < k && guard < 200) {
      guard++;
      final pool = j % 6 == 5 ? priced : longPriced;
      final t = pool[rng.nextInt(pool.length)];
      if (!chosen.contains(t)) chosen.add(t);
    }
    final kind = j % 5 == 4 ? PortfolioKind.reserve : PortfolioKind.principal;
    final Result<Portfolio> built;
    if (j % 3 == 0) {
      final raw = [for (final _ in chosen) 0.2 + rng.nextDouble()];
      final total = raw.fold<double>(0, (a, b) => a + b);
      built = Ok(Portfolio(
        id: 'p$j',
        name: 'Carteira $j',
        kind: kind,
        entries: {
          for (var q = 0; q < chosen.length; q++)
            chosen[q]: PortfolioEntry(
                asset: assetOf(chosen[q]),
                weight: Weight.fraction(raw[q] / total)),
        },
      ));
    } else {
      built = Portfolio.equalWeighted(
          id: 'p$j',
          name: 'Carteira $j',
          kind: kind,
          assets: [for (final t in chosen) assetOf(t)]);
    }
    final initial = rng.nextDouble() < 0.2 ? 0.0 : 1000 + 99000 * rng.nextDouble();
    final monthly = rng.nextDouble() < 0.25 ? 0.0 : 100 + 4900 * rng.nextDouble();
    final day = 1 + rng.nextInt(28);
    final startIndex = rng.nextInt(market.days.length - 300);
    final length = 250 + rng.nextInt(2500);
    final endIndex = math.min(startIndex + length, market.days.length - 1);
    final range = DateRange(market.days[startIndex], market.days[endIndex]);
    final rf = j % 4 == 0 ? 0.0 : anchors.currentRiskFreeRate;
    if (built.isErr) {
      backtests.add(failureJson(built.failureOrNull!));
      continue;
    }
    final portfolio = built.unwrap();
    portfolios.add(portfolio);
    final prices = <Ticker, PriceSeries>{
      for (final t in chosen)
        if (j % 7 != 3 || t != chosen.first) t: market.prices[t.value]!,
    };
    final outcome = PortfolioBacktest.run(
      portfolio: portfolio,
      prices: prices,
      plan: ContributionPlan(
        initial: Money.fromReais(initial),
        monthly: Money.fromReais(monthly),
        contributionDay: day,
      ),
      range: range,
      riskFreeRate: rf,
      costs: costs[j % 3],
    );
    backtests.add({
      'tickers': [for (final t in portfolio.tickers) t.value],
      'weights': [for (final t in portfolio.tickers) n(portfolio.entries[t]!.weight.value)],
      'outcome': backtestJson(outcome),
    });

    final report = SectorConcentration.analyze(portfolio);
    concentrations.add([
      for (final e in report.concentrated) [e.sector.key, e.sector.label, e.count, n(e.weight)],
    ]);

    final goalResult = FinancialGoal.create(
      initialContribution: Money.fromReais(initial),
      monthlyContribution: Money.fromReais(monthly),
      months: 12 + rng.nextInt(360),
      targetWealth: Money.fromReais(50000 + 5e6 * rng.nextDouble()),
    );
    if (goalResult.isErr) {
      alignments.add(failureJson(goalResult.failureOrNull!));
    } else {
      final goal = goalResult.unwrap();
      final signals = {
        for (final t in portfolio.tickers)
          t: TransversalSignals.fromHistory(histories[t.value] ?? const [],
              asOf: asOf, potential: valuations[t]?.upside),
      };
      final crossSection = [for (final v in valuations.values) v.upside];
      Map<String, Object?> alignmentJson(Result<GoalAlignment> a) {
        if (a.isErr) return failureJson(a.failureOrNull!);
        final g = a.unwrap();
        return {
          'requiredMonthly': n(g.required.monthly),
          'requiredAnnual': n(g.required.annual),
          'expected': n(g.expectedReturn),
          'coverage': n(g.valuationCoverage),
          'gap': n(g.gap),
          'meets': g.meetsGoal,
          'weak': g.coverageIsWeak,
        };
      }

      alignments.add({
        'crossSectional': alignmentJson(EvaluateGoalAlignment.call(
          portfolio: portfolio,
          goal: goal,
          valuations: valuations,
          anchors: anchors,
          crossSection: crossSection,
          riskPremium: premium,
        )),
        'ordered': alignmentJson(EvaluateGoalAlignment.call(
          portfolio: portfolio,
          goal: goal,
          valuations: valuations,
          anchors: anchors,
          ordering: skill?.premiumOrdering,
          signals: signals,
          riskPremium: premium,
        )),
        'orderedNone': alignmentJson(EvaluateGoalAlignment.call(
          portfolio: portfolio,
          goal: goal,
          valuations: valuations,
          anchors: anchors,
          ordering: TransversalOrdering.values[j % 3],
          signals: signals,
        )),
        'feasibility': () {
          final req = RequiredReturnSolver.solve(goal);
          if (req.isErr) return failureJson(req.failureOrNull!);
          final f = GoalFeasibility.assess(
              required: req.unwrap(), anchors: anchors, goal: goal);
          return [f.level.name, f.reason.name, n(f.requiredAnnualRate), n(f.marketMultiple)];
        }(),
      });
    }
  }

  for (var j = 0; j + 1 < portfolios.length; j += 2) {
    final a = portfolios[j];
    final b = portfolios[j + 1];
    final principal = a.kind == PortfolioKind.principal ? a : b;
    final reserve = Portfolio(
        id: 'r$j', name: 'Reserva $j', kind: PortfolioKind.reserve,
        entries: (a.kind == PortfolioKind.principal ? b : a).entries);
    final ticker = (j % 4 == 0 ? reserve : principal).tickers.first;
    final r = SwapAssetBetweenPortfolios.call(
      principal: principal,
      reserve: reserve,
      ticker: ticker,
      toPrincipal: j % 4 == 0,
    );
    swaps.add(r.isErr
        ? failureJson(r.failureOrNull!)
        : {
            'principal': [
              for (final t in r.unwrap().principal.tickers)
                [t.value, n(r.unwrap().principal.entries[t]!.weight.value)],
            ],
            'reserve': [
              for (final t in r.unwrap().reserve.tickers)
                [t.value, n(r.unwrap().reserve.entries[t]!.weight.value)],
            ],
          });
  }

  final goals = <Object?>[];
  for (var j = 0; j < 150; j++) {
    final rng = math.Random(11000 + j);
    final initial = rng.nextDouble() < 0.15 ? 0.0 : 200000 * rng.nextDouble();
    final monthly = rng.nextDouble() < 0.15 ? 0.0 : 10000 * rng.nextDouble();
    final months = j % 29 == 0 ? 0 : 1 + rng.nextInt(480);
    final target = j % 31 == 0 ? -5.0 : 1e4 + 1e7 * rng.nextDouble();
    final g = FinancialGoal.create(
      initialContribution: Money.fromReais(initial),
      monthlyContribution: Money.fromReais(monthly),
      months: months,
      targetWealth: Money.fromReais(target),
    );
    if (g.isErr) {
      goals.add(failureJson(g.failureOrNull!));
      continue;
    }
    final goal = g.unwrap();
    final req = RequiredReturnSolver.solve(goal);
    if (req.isErr) {
      goals.add({
        'falha': failureJson(req.failureOrNull!),
        'unsolvable': GoalFeasibility.unsolvable(anchors: anchors).reason.name,
      });
      continue;
    }
    final rr = req.unwrap();
    final f = GoalFeasibility.assess(required: rr, anchors: anchors, goal: goal);
    goals.add({
      'monthly': n(rr.monthly),
      'annual': n(rr.annual),
      'fv': n(RequiredReturnSolver.futureValue(
          rate: rr.monthly,
          initial: goal.initialContribution.reais,
          monthly: goal.monthlyContribution.reais,
          months: goal.months)),
      'level': f.level.name,
      'reason': f.reason.name,
      'multiple': n(f.marketMultiple),
      'withoutReturn': goal.reachableWithoutReturn,
      'total': goal.totalContributed.cents,
    });
  }

  final crossSection = ExpectedReturn.crossSection(
    upsides: {for (final e in valuations.entries) e.key: e.value.upside},
    spotRiskFree: anchors.currentRiskFreeRate,
    costOfEquity: {
      for (final e in valuations.entries)
        if (e.value.diagnostics != null) e.key: e.value.diagnostics!.costOfEquity,
    },
    riskPremium: premium,
  );

  final calendar = <Object?>[];
  for (var j = 0; j < 120; j++) {
    final rng = math.Random(13000 + j);
    final a = DateTime(2000 + rng.nextInt(30), 1 + rng.nextInt(12), 1 + rng.nextInt(28));
    final b = DateTime(a.year, a.month, a.day + rng.nextInt(800));
    calendar.add([
      a.toIso8601String(),
      b.toIso8601String(),
      BrazilianCalendar.businessDaysBetween(a, b),
      BrazilianCalendar.isBusinessDay(a),
      BrazilianCalendar.isTradingDay(b),
      BrazilianCalendar.nextTradingSession(a).toIso8601String(),
      BrazilianCalendar.treasurySettlement(b).toIso8601String(),
    ]);
  }
  final easter = [
    for (var y = 1900; y <= 2100; y++) BrazilianCalendar.easter(y).toIso8601String(),
  ];

  return {
    'valuations': valuations.length,
    'manual': manual,
    'backtests': backtests,
    'concentrations': concentrations,
    'alignments': alignments,
    'swaps': swaps,
    'goals': goals,
    'crossSection': [
      for (final e in crossSection.entries)
        [e.key.value, n(e.value.z), n(e.value.expected), e.value.floored, e.value.anchoredOnCostOfEquity],
    ],
    'calendar': calendar,
    'easter': easter,
  };
}
