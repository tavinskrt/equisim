// A entrada congelada do gabarito, para quem só quer medir sobre ela.
//
// **Por que existe.** O gabarito da cascata (`tool/gabarito_cascata.dart`)
// congela cache, Ibovespa e universo, e monta a entrada a partir dos pacotes
// versionados — é a única forma de medir o efeito de uma mudança sem misturá-lo
// com a deriva do dado de mercado. As medições dos itens B12, B14 e B15
// precisam da mesma entrada, e reescrever a montagem em cada uma é como duas
// cópias divergem.
//
// **Este módulo não grava nada e não vai à rede**: ele exige que o gabarito já
// tenha congelado a entrada, e falha dizendo o que rodar antes. Quem grava
// continua sendo o gabarito.
//
// **A conferência é parte do contrato.** [Frozen.checkAgainstAnswerKey]
// compara as avaliações deste módulo com as que o gabarito gravou na montagem
// `aplicativo`: se as duas montagens divergirem, a medição não vale, e o
// programa que a usa precisa saber disso antes de imprimir número.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'context.dart';

/// A data de referência da entrada congelada — a mesma do gabarito.
final DateTime frozenToday = DateTime(2026, 9, 14);

const _folder = 'data/gabarito';
const _cache = '$_folder/cache.sqlite';
const _ibovespa = '$_folder/ibovespa.json';
const _universe = '$_folder/universo.json';

/// O pacote do prêmio implícito (decisão 142).
const _premiumPackage = 'assets/mercado/premio_implicito.json';
const _answerKey = 'docs/validacao/gabarito_cascata.json';

/// O Ibovespa gravado pelo gabarito. Janela não gravada é recusada — ir à rede
/// aqui descongelaria a entrada sem avisar.
class _SavedIbovespa implements BenchmarkRepository {
  _SavedIbovespa(this.saved);
  final Map<String, PriceSeries> saved;

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    final k = '${range.start.toIso8601String()}|${range.end.toIso8601String()}';
    final g = saved[k];
    if (g != null) return Ok(g);
    return Err(InsufficientData('Ibovespa não gravado para $k'));
  }

  static Map<String, PriceSeries> read(Map<String, dynamic> j) => {
        for (final e in j.entries)
          e.key: PriceSeries(
            ticker: Ticker.parse((e.value as Map)['ticker'] as String),
            points: [
              for (final p in ((e.value as Map)['pontos'] as List).cast<List>())
                PricePoint(
                  date: DateTime.parse(p[0] as String),
                  close: (p[1] as num).toDouble(),
                  adjustedClose: (p[2] as num?)?.toDouble(),
                  volume: (p[3] as num?)?.toDouble(),
                ),
            ],
          ),
      };
}

/// Fundamentos de mercado com a demonstração da CVM mesclada, como o
/// aplicativo faz.
class CvmFundamentals implements FundamentalsRepository {
  final FundamentalsRepository market;
  final Map<String, List<CvmPeriodDocument>> docs;
  final DateTime today;
  final bool anchored;
  CvmFundamentals(this.market, this.docs,
      {required this.today, this.anchored = false});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await market.history(t);
    if (base.isErr) return base;
    final ownDocs = docs[t.value];
    if (ownDocs == null || ownDocs.isEmpty) return base;
    return Ok(CvmSeries.build(
      documents: ownDocs,
      market: base.unwrap(),
      published: PointInTimeView(today).isPublished,
      anchored: anchored,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => market.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => market.universe();
}

/// A entrada congelada, montada.
class Frozen {
  Frozen._({
    required this.ctx,
    required this.fundamentals,
    required this.anchors,
    required this.curve,
    required this.universe,
    required this.prior,
    required this.registry,
    required this.terms,
    required this.dividends,
    required this.units,
    this.capital = const {},
    this.control = const {},
    this.premium = (
      value: CapmInputs.defaultMarketPremium,
      origin: MarketPremiumSource.parameterized,
    ),
  });

  final ValidationContext ctx;

  /// Fundamentos com a CVM mesclada e o setor da B3 por emissor.
  final FundamentalsRepository fundamentals;

  final MarketAnchors anchors;
  final YieldCurve? curve;
  final List<Ticker> universe;

  /// O prior do pacote — o que o aplicativo lê (decisão 105).
  final BetaPrior? prior;

  final Map<String, B3Issuer> registry;
  final Map<String, ConcessionTerm> terms;
  final Map<String, List<CashDividend>> dividends;
  final Map<String, List<UnitComposition>> units;

  /// Emissões e eventos de ações do pacote do aplicativo (itens B28 e B29).
  final Map<String, CapitalEvents> capital;

  /// O controle acionário de cada emissor, pela raiz do código (item B46).
  final Map<String, List<ShareholderControlPeriod>> control;

  /// `true` quando o emissor de [t] é de controle estatal na data congelada.
  bool stateOwned(Ticker t) {
    final p = control[t.value.substring(0, 4)];
    return p != null &&
        ShareholderControlHistory.at(p, frozenToday) ==
            ShareholderControl.state;
  }

  /// O prêmio de mercado da montagem do aplicativo, e de onde ele veio
  /// (decisão 142).
  final ({double value, MarketPremiumSource origin}) premium;

  /// O Ibovespa da janela do beta, já congelado.
  late final DateRange betaWindow = DateRange(
    DateTime(frozenToday.year - PrepareValuationInputs.betaWindowYears,
        frozenToday.month, frozenToday.day),
    frozenToday,
  );

  B3Issuer? issuer(Ticker t) =>
      registry[t.value.length >= 4 ? t.value.substring(0, 4) : ''];

  List<CashDividend> dividendsOf(Ticker t) =>
      CashDividendsCodec.forTicker(dividends, t.value);

  /// Monta a entrada, exigindo que o gabarito já tenha congelado a dele.
  ///
  /// Encerra o processo com código 2 quando falta a entrada congelada: medir
  /// sobre dado fresco daria outro número a cada execução, e é exatamente o que
  /// este módulo existe para não deixar acontecer.
  static Future<Frozen> build() async {
    for (final f in [_cache, _ibovespa, _universe]) {
      if (File(f).existsSync()) continue;
      stderr.writeln('sem entrada congelada em $f. Rode antes:');
      stderr.writeln('  dart run tool/gabarito_cascata.dart');
      exit(2);
    }

    Map<String, dynamic> read(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    final curve = TreasuryCurve.at(
        TreasuryQuotesCodec.decode(read('assets/tesouro/curva.json')),
        frozenToday);
    final registry = B3RegistryCodec.decodePackage(read('assets/b3/emissores.json'));
    final docs = CvmDocumentCodec.decodePackage(read('assets/cvm/documentos.json'));
    final terms = ConcessionTermsCodec.decode(read('assets/cvm/outorgas.json'));
    final dividends = CashDividendsCodec.decode(read('assets/b3/proventos.json'));
    final prior = File('assets/mercado/beta_prior.json').existsSync()
        ? BetaPriorCodec.decode(read('assets/mercado/beta_prior.json'))?.prior
        : null;
    final capital = File('assets/cvm/capital.json').existsSync()
        ? CapitalEventsCodec.decodePackage(read('assets/cvm/capital.json'))
        : const <String, CapitalEvents>{};
    final units = File('assets/cvm/units.json').existsSync()
        ? UnitCompositionCodec.decodePackage(read('assets/cvm/units.json'))
        : const <String, List<UnitComposition>>{};
    // O controle acionário (item B46), como o aplicativo o lê.
    final control = File('assets/cvm/controle.json').existsSync()
        ? ShareholderControlHistory.decode(read('assets/cvm/controle.json'))
                ?.byIssuer ??
            const <String, List<ShareholderControlPeriod>>{}
        : const <String, List<ShareholderControlPeriod>>{};
    // O prêmio de mercado do aplicativo (decisão 142): a média de dez anos da
    // série do pacote, na data congelada. Sem pacote, o recuo do aplicativo —
    // os 5,5% parametrizados —, dito no terminal.
    final premiumPackage = File(_premiumPackage).existsSync()
        ? ImpliedPremiumCodec.decode(read(_premiumPackage))
        : null;
    final mean = premiumPackage?.normalizedAt(frozenToday);
    final premium = mean == null
        ? (
            value: CapmInputs.defaultMarketPremium,
            origin: MarketPremiumSource.parameterized,
          )
        : (value: mean, origin: MarketPremiumSource.impliedNormalized);
    if (mean == null) {
      stderr.writeln('sem $_premiumPackage utilizável: o prêmio é o '
          'parametrizado de 5,5% (rode dart run tool/premio_implicito.dart '
          '--so-serie)');
    }

    final ctx0 = ValidationContext.create(
        outputDir: 'docs/validacao', cacheFile: _cache, frozenCache: true);
    final ibov = _SavedIbovespa(_SavedIbovespa.read(read(_ibovespa)));
    // O Ibovespa gravado no lugar do de rede; o resto do contexto é o mesmo.
    final ctx = ctx0.withBenchmark(ibov);

    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: frozenToday,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    final universe = [
      for (final s
          in (jsonDecode(File(_universe).readAsStringSync()) as List)
              .cast<String>())
        Ticker.parse(s),
    ];

    B3Issuer? issuer(Ticker t) =>
        registry[t.value.length >= 4 ? t.value.substring(0, 4) : ''];
    final fundamentals = OfficialSectorFundamentalsRepository(
      inner: CvmFundamentals(ctx.fundamentals, docs, today: frozenToday),
      classification: (t) async => issuer(t)?.classification,
    );

    return Frozen._(
      ctx: ctx,
      fundamentals: fundamentals,
      anchors: anchors,
      curve: curve,
      universe: universe,
      prior: prior,
      registry: registry,
      terms: terms,
      dividends: dividends,
      units: units,
      control: control,
      capital: capital,
      premium: premium,
    );
  }

  /// A entrada da montagem **do aplicativo**, a mesma do gabarito.
  ///
  /// [years] existe para a varredura do horizonte (item B6) e **nada mais**: o
  /// padrão de 10 é o do gabarito, e passar outro valor produz uma montagem que
  /// não é a dele — quem varre precisa dizer isso ao imprimir número.
  ///
  /// [premium] existe para a varredura do prêmio de risco de mercado (itens B3
  /// e B42), e tem a mesma ressalva: ausente, é o do aplicativo — a média de
  /// dez anos do prêmio implícito, do pacote (decisão 142) —, que é o do
  /// gabarito; informado, entra como parametrizado.
  ///
  /// [rate] troca a fonte da taxa livre de risco, para a medição da Selic
  /// prevista (`tool/selic_focus.dart`): `curva` no lugar da do Tesouro — nula,
  /// o motor usa os dois pontos do CDI — e `structural` no lugar da média
  /// decenal. Ausente, é a montagem do gabarito.
  ///
  /// [withPrior] falso tira o prior do beta, e o beta fica o medido, sem
  /// encolhimento — para a medição do item B46, que compara os dois. Com o
  /// padrão, é a montagem do gabarito.
  Future<Result<ValuationInputs>> prepare(
    Ticker t, {
    int years = 10,
    double? premium,
    ({YieldCurve? curve, double? structural})? rate,
    bool withPrior = true,
  }) {
    final e = issuer(t);
    return PrepareValuationInputs.call(
      ticker: t,
      prices: ctx.prices,
      fundamentals: fundamentals,
      benchmark: ctx.benchmark,
      riskFreeRate: anchors.currentRiskFreeRate,
      asOf: frozenToday,
      perpetualGrowthCap: anchors.nominalEconomyGrowth,
      inflation: anchors.inflationCagr,
      terminalRiskFreeRate: rate?.structural ?? anchors.riskFreeCagr,
      riskFreeCurve: rate == null ? curve : rate.curve,
      projectionYears: years,
      marketPremium: premium ?? this.premium.value,
      premiumSource: premium == null
          ? this.premium.origin
          : MarketPremiumSource.parameterized,
      officialShares: e?.totalShares != null
          ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
          : null,
      concessionEnd: terms[t.value]?.end,
      dividends: dividendsOf(t),
      betaPrior: withPrior ? prior : null,
      declaredSharesPerUnit:
          UnitCompositionCodec.at(units[t.value] ?? const [], frozenToday)
              ?.shares,
      shareEvents: capital[t.value]?.shareEvents ?? const [],
      shareIssues: capital[t.value]?.issues ?? const [],
      stateControlled: stateOwned(t),
    );
  }

  /// Confere as avaliações deste módulo contra o que o gabarito gravou.
  ///
  /// Devolve os tickers que divergem. Lista vazia com gabarito presente é a
  /// prova de que as duas montagens são a mesma; gabarito ausente devolve
  /// `null`, e quem chama precisa dizer que não conferiu.
  Future<List<String>?> checkAgainstAnswerKey(
    Map<Ticker, ValuationResult?> ownDocs,
  ) async {
    final file = File(_answerKey);
    if (!file.existsSync()) return null;
    final g = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final divergent = <String>[];
    for (final e in ownDocs.entries) {
      final saved = (g[e.key.value] as Map<String, dynamic>?)?['aplicativo'];
      final cents = saved is Map ? saved['justoCentavos'] : null;
      final own = e.value?.fairValue.cents;
      if (cents == null && own == null) continue;
      if (cents is! int || own != cents) divergent.add(e.key.value);
    }
    return divergent;
  }
}
