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
// **A conferência é parte do contrato.** [Congelado.conferirContraGabarito]
// compara as avaliações deste módulo com as que o gabarito gravou na montagem
// `aplicativo`: se as duas montagens divergirem, a medição não vale, e o
// programa que a usa precisa saber disso antes de imprimir número.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'context.dart';

/// A data de referência da entrada congelada — a mesma do gabarito.
final DateTime hojeCongelado = DateTime(2026, 9, 14);

const _pasta = 'data/gabarito';
const _cache = '$_pasta/cache.sqlite';
const _ibovespa = '$_pasta/ibovespa.json';
const _universo = '$_pasta/universo.json';
const _gabarito = 'docs/validacao/gabarito_cascata.json';

/// O Ibovespa gravado pelo gabarito. Janela não gravada é recusada — ir à rede
/// aqui descongelaria a entrada sem avisar.
class _IbovespaGravado implements BenchmarkRepository {
  _IbovespaGravado(this.gravado);
  final Map<String, PriceSeries> gravado;

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    final k = '${range.start.toIso8601String()}|${range.end.toIso8601String()}';
    final g = gravado[k];
    if (g != null) return Ok(g);
    return Err(InsufficientData('Ibovespa não gravado para $k'));
  }

  static Map<String, PriceSeries> ler(Map<String, dynamic> j) => {
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
class FundamentosDaCvm implements FundamentalsRepository {
  final FundamentalsRepository mercado;
  final Map<String, List<CvmPeriodDocument>> docs;
  final DateTime hoje;
  final bool ancorada;
  FundamentosDaCvm(this.mercado, this.docs,
      {required this.hoje, this.ancorada = false});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await mercado.history(t);
    if (base.isErr) return base;
    final meus = docs[t.value];
    if (meus == null || meus.isEmpty) return base;
    return Ok(CvmSeries.build(
      documentos: meus,
      mercado: base.unwrap(),
      asOf: hoje,
      publicado: PointInTimeView(hoje).isPublished,
      ancorada: ancorada,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => mercado.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => mercado.universe();
}

/// A entrada congelada, montada.
class Congelado {
  Congelado._({
    required this.ctx,
    required this.fundamentos,
    required this.anchors,
    required this.curva,
    required this.universo,
    required this.prior,
    required this.registro,
    required this.prazos,
    required this.proventos,
    required this.units,
  });

  final ValidationContext ctx;

  /// Fundamentos com a CVM mesclada e o setor da B3 por emissor.
  final FundamentalsRepository fundamentos;

  final MarketAnchors anchors;
  final YieldCurve? curva;
  final List<Ticker> universo;

  /// O prior do pacote — o que o aplicativo lê (decisão 105).
  final BetaPrior? prior;

  final Map<String, B3Issuer> registro;
  final Map<String, ConcessionTerm> prazos;
  final Map<String, List<CashDividend>> proventos;
  final Map<String, List<UnitComposition>> units;

  /// O Ibovespa da janela do beta, já congelado.
  late final DateRange janelaDoBeta = DateRange(
    DateTime(hojeCongelado.year - PrepareValuationInputs.betaWindowYears,
        hojeCongelado.month, hojeCongelado.day),
    hojeCongelado,
  );

  B3Issuer? emissor(Ticker t) =>
      registro[t.value.length >= 4 ? t.value.substring(0, 4) : ''];

  List<CashDividend> proventosDe(Ticker t) =>
      CashDividendsCodec.forTicker(proventos, t.value);

  /// Monta a entrada, exigindo que o gabarito já tenha congelado a dele.
  ///
  /// Encerra o processo com código 2 quando falta a entrada congelada: medir
  /// sobre dado fresco daria outro número a cada execução, e é exatamente o que
  /// este módulo existe para não deixar acontecer.
  static Future<Congelado> montar() async {
    for (final f in [_cache, _ibovespa, _universo]) {
      if (File(f).existsSync()) continue;
      stderr.writeln('sem entrada congelada em $f. Rode antes:');
      stderr.writeln('  dart run tool/gabarito_cascata.dart');
      exit(2);
    }

    Map<String, dynamic> ler(String caminho) =>
        jsonDecode(File(caminho).readAsStringSync()) as Map<String, dynamic>;

    final curva = TreasuryCurve.at(
        TreasuryQuotesCodec.decode(ler('assets/tesouro/curva.json')),
        hojeCongelado);
    final registro = B3RegistryCodec.decodePackage(ler('assets/b3/emissores.json'));
    final docs = CvmDocumentCodec.decodePackage(ler('assets/cvm/documentos.json'));
    final prazos = ConcessionTermsCodec.decode(ler('assets/cvm/outorgas.json'));
    final proventos = CashDividendsCodec.decode(ler('assets/b3/proventos.json'));
    final prior = File('assets/mercado/beta_prior.json').existsSync()
        ? BetaPriorCodec.decode(ler('assets/mercado/beta_prior.json'))?.prior
        : null;
    final units = File('assets/cvm/units.json').existsSync()
        ? UnitCompositionCodec.decodePackage(ler('assets/cvm/units.json'))
        : const <String, List<UnitComposition>>{};

    final ctx0 = ValidationContext.create(
        outputDir: 'docs/validacao', cacheFile: _cache, frozenCache: true);
    final ibov = _IbovespaGravado(_IbovespaGravado.ler(ler(_ibovespa)));
    // O Ibovespa gravado no lugar do de rede; o resto do contexto é o mesmo.
    final ctx = ctx0.comBenchmark(ibov);

    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: hojeCongelado,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    final universo = [
      for (final s
          in (jsonDecode(File(_universo).readAsStringSync()) as List)
              .cast<String>())
        Ticker.parse(s),
    ];

    B3Issuer? emissor(Ticker t) =>
        registro[t.value.length >= 4 ? t.value.substring(0, 4) : ''];
    final fundamentos = OfficialSectorFundamentalsRepository(
      inner: FundamentosDaCvm(ctx.fundamentals, docs, hoje: hojeCongelado),
      classificacao: (t) async => emissor(t)?.classification,
    );

    return Congelado._(
      ctx: ctx,
      fundamentos: fundamentos,
      anchors: anchors,
      curva: curva,
      universo: universo,
      prior: prior,
      registro: registro,
      prazos: prazos,
      proventos: proventos,
      units: units,
    );
  }

  /// A entrada da montagem **do aplicativo**, a mesma do gabarito.
  Future<Result<ValuationInputs>> preparar(Ticker t) {
    final e = emissor(t);
    return PrepareValuationInputs.call(
      ticker: t,
      prices: ctx.prices,
      fundamentals: fundamentos,
      benchmark: ctx.benchmark,
      riskFreeRate: anchors.currentRiskFreeRate,
      asOf: hojeCongelado,
      perpetualGrowthCap: anchors.nominalEconomyGrowth,
      inflation: anchors.inflationCagr,
      terminalRiskFreeRate: anchors.riskFreeCagr,
      riskFreeCurve: curva,
      projectionYears: 10,
      officialShares: e?.totalShares != null
          ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
          : null,
      concessionEnd: prazos[t.value]?.end,
      dividends: proventosDe(t),
      betaPrior: prior,
      declaredSharesPerUnit:
          UnitCompositionCodec.at(units[t.value] ?? const [], hojeCongelado)
              ?.shares,
    );
  }

  /// Confere as avaliações deste módulo contra o que o gabarito gravou.
  ///
  /// Devolve os tickers que divergem. Lista vazia com gabarito presente é a
  /// prova de que as duas montagens são a mesma; gabarito ausente devolve
  /// `null`, e quem chama precisa dizer que não conferiu.
  Future<List<String>?> conferirContraGabarito(
    Map<Ticker, ValuationResult?> meus,
  ) async {
    final arquivo = File(_gabarito);
    if (!arquivo.existsSync()) return null;
    final g = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    final divergentes = <String>[];
    for (final e in meus.entries) {
      final gravado = (g[e.key.value] as Map<String, dynamic>?)?['aplicativo'];
      final centavos = gravado is Map ? gravado['justoCentavos'] : null;
      final meu = e.value?.fairValue.cents;
      if (centavos == null && meu == null) continue;
      if (centavos is! int || meu != centavos) divergentes.add(e.key.value);
    }
    return divergentes;
  }
}
