// D1 — gabarito da cascata: a condição para quebrar `_evaluateLane`.
//
// Quebrar `_evaluateLane` em estágios é refatoração pura: **nenhum número pode
// mudar**. A cascata é determinística — é regra do núcleo —, então isso é
// verificável ao bit: este gabarito grava a saída completa do universo, e o
// modo `--conferir` refaz e compara.
//
// **Nove montagens por ativo**, para que todo caminho do método seja
// exercitado com dado real:
//
//   doisPontos   fonte de mercado, taxa livre de risco de dois pontos
//   curva        mais a curva do Tesouro (decisão 74)
//   aplicativo   contagem oficial, curva, CVM, setor da B3, prazo das outorgas
//                e beta de retorno total — a montagem do aplicativo
//   ancorada     a do aplicativo, com a série de doze meses (decisão 73)
//   prior        a do aplicativo mais o prior do beta: é a única que liga o
//                ponto fixo das taxas, a rota derivada, os passes do veredito e
//                a estrutura recusada — o aplicativo não resolve o prior (B11),
//                e sem esta montagem esses caminhos ficariam fora do gabarito
//   monteCarlo   a do prior com cenários sorteados, que chamam a avaliação por
//                premissa nas duas vias
//   viaFirma     a do prior com a via da firma imposta
//   viaAcionista a do prior com a via do acionista imposta
//   impostos     a do prior com crescimento, fator de base, retorno terminal,
//                freio e convenção de caixa impostos
//
// Cada montagem grava o resultado inteiro **e o rastro de auditoria**: um passo
// fora de ordem ou uma variável trocada no rastro é mudança que o resultado não
// mostra.
//
// **O gabarito congela a entrada junto com a saída.** O cache da validação
// expira e o Ibovespa vem da rede sem cache — em meia hora, 26 ativos mudaram de
// valor sem mudança de código. Por isso a gravação copia o cache para
// `data/gabarito/`, trata toda entrada presente como fresca, grava o Ibovespa
// servido e a conferência repete os dois sem ir à rede. Confira primeiro o
// código intacto, como controle: divergência ali é defeito do congelamento, não
// refatoração.
//
// Uso:
//   dart run tool/gabarito_cascata.dart                # grava o gabarito
//   dart run tool/gabarito_cascata.dart --conferir     # compara com o gravado
//   dart run tool/gabarito_cascata.dart --regravar --saida <arq>
//                                                      # regrava sem mexer na
//                                                      # entrada congelada
//   dart run tool/gabarito_cascata.dart --rastro PETR4 # rastro de um ativo
//   dart run tool/gabarito_cascata.dart --monotonia docs/validacao/monotonia_vias.json
//   dart run tool/gabarito_cascata.dart --nivel GOAU4  # a grade de um ativo, aberta
//
// **`--monotonia`** usa a mesma entrada congelada para a varredura do item
// B10: desloca o nível da taxa livre de risco — a corrente, a de equilíbrio e a
// curva inteira — de −3 a +3 p.p., de 25 em 25 pontos-base, nas montagens
// `aplicativo` e `prior`, e confere se o preço justo cai quando o capital
// encarece. Conta também o que muda de via e o que alterna entre avaliado e
// recusado no meio da grade.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'validation/context.dart';

final _today = DateTime(2026, 9, 14);
const _file = 'docs/validacao/gabarito_cascata.json';
const _folder = 'data/gabarito';
const _cache = '$_folder/cache.sqlite';
const _ibovespa = '$_folder/ibovespa.json';
const _universe = '$_folder/universo.json';

/// O Ibovespa servido, por janela: gravado na primeira execução e repetido nas
/// seguintes. Janela que não foi gravada é recusada, e a divergência aparece.
class _FrozenIbovespa implements BenchmarkRepository {
  _FrozenIbovespa(this.network, this.saved);
  final BenchmarkRepository? network;
  final Map<String, PriceSeries> saved;

  static String _key(DateRange r) =>
      '${r.start.toIso8601String()}|${r.end.toIso8601String()}';

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    final k = _key(range);
    final g = saved[k];
    if (g != null) return Ok(g);
    final source = network;
    if (source == null) {
      return Err(InsufficientData('Ibovespa não gravado para $k'));
    }
    final r = await source.ibovespa(range);
    if (r.isOk) saved[k] = r.unwrap();
    return r;
  }

  Map<String, Object?> toJson() => {
        for (final e in saved.entries)
          e.key: {
            'ticker': e.value.ticker.value,
            'pontos': [
              for (final p in e.value.points)
                [
                  p.date.toIso8601String(),
                  p.close,
                  p.adjustedClose,
                  p.volume,
                ],
            ],
          },
      };

  static Map<String, PriceSeries> fromJson(Map<String, dynamic> j) => {
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

/// FNV-1a de 64 bits sobre o texto. O rastro de auditoria do universo inteiro
/// passa de centenas de megabytes; o gabarito guarda a impressão dele, e o
/// modo `--rastro TICKER` mostra o rastro de um ativo para achar a diferença.
String _fingerprint(String text) {
  var h = 0xcbf29ce484222325;
  for (final u in utf8.encode(text)) {
    h ^= u;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Tudo o que o resultado expõe. `double.toString()` é a representação mais
/// curta que volta ao mesmo bit — é o que torna a comparação exata.
Map<String, Object?> _serialize(Result<ValuationResult> r) {
  if (r.isErr) return {'recusa': r.failureOrNull!.message};
  final v = r.unwrap();
  final d = v.diagnostics;
  final dist = v.distribution;
  return {
    'modelo': v.model.name,
    'justoCentavos': v.fairValue.cents,
    'precoCentavos': v.marketPrice.cents,
    'potencial': v.upside.toString(),
    'desconto': v.discountRate.toString(),
    'modo': v.mode.name,
    'cenarios': v.discreteScenarios == null
        ? null
        : {for (final e in v.discreteScenarios!.entries) e.key.name: e.value.cents},
    if (dist != null)
      'distribuicao': {
        'n': dist.sortedValues.length,
        'p5': dist.p5.toString(),
        'mediana': dist.median.toString(),
        'p95': dist.p95.toString(),
        'impressao': _fingerprint(dist.sortedValues.join(',')),
      },
    'avisos': v.warnings,
    if (d != null)
      'diagnostico': {
        'pesoTerminal': d.terminalShare.toString(),
        'excedenteTerminal': d.terminalExcessShare?.toString(),
        'retornoImplicitoTerminal': d.impliedTerminalReturn?.toString(),
        'pesoEquityTerminal': d.terminalEquityShare?.toString(),
        'pesoEquity': d.equityShare.toString(),
        'fatorBase': d.baseFactor.toString(),
        'crescimentoIdentificado': d.growthIdentified,
        'moat': d.moatApplied,
        'spreadRetido': d.terminalRetainedSpread.toString(),
        'crescimento': d.growthRate.toString(),
        'retornoTerminal': d.terminalReturnOnCapital?.toString(),
        'aliquota': d.firmTaxRate?.toString(),
        'retorno': d.returnOnCapital.toString(),
        'descontoTerminal': d.terminalDiscountRate.toString(),
        'keTerminal': d.terminalCostOfEquity?.toString(),
        'ke': d.costOfEquity.toString(),
        'caminhoCrescimento': [for (final x in d.growthPath) x.toString()],
        'caminhoRetencao': [for (final x in d.retentionPath) x.toString()],
        'ressalvas': [for (final c in d.caveats) c.key],
      },
  };
}

/// Os mesmos insumos com as imposições de diagnóstico.
///
/// **Pela cópia do núcleo** (item B27). A versão à mão perdia a composição
/// declarada da unit, a taxa de referência do crédito, a janela do beta e os
/// múltiplos de pares, e as montagens de diagnóstico rodavam outro divisor nas
/// units.
ValuationInputs _impose(
  ValuationInputs b, {
  ValuationLane? lane,
  bool everything = false,
}) =>
    b.withOverrides(
      lane: lane,
      terminalReturn: everything ? 0.13 : null,
      growth: everything ? 0.06 : null,
      baseFactor: everything ? 1.1 : null,
      reinvestment: everything ? ReinvestmentPolicy.realGrowth : null,
      cashTiming: everything ? CashTiming.endOfYear : null,
    );

class _FromCvm implements FundamentalsRepository {
  final FundamentalsRepository market;
  final Map<String, List<CvmPeriodDocument>> docs;
  final bool anchored;
  _FromCvm(this.market, this.docs, {this.anchored = false});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await market.history(t);
    if (base.isErr) return base;
    final ownDocs = docs[t.value];
    if (ownDocs == null || ownDocs.isEmpty) return base;
    return Ok(CvmSeries.build(
      documents: ownDocs,
      market: base.unwrap(),
      published: PointInTimeView(_today).isPublished,
      anchored: anchored,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => market.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => market.universe();
}

Future<void> main(List<String> args) async {
  final monotonicityIndex = args.indexOf('--monotonia');
  final monotonicityOutput = monotonicityIndex >= 0 ? args[monotonicityIndex + 1] : null;
  final levelIndex = args.indexOf('--nivel');
  final levelOnly = levelIndex >= 0 ? args[levelIndex + 1] : null;
  final check = args.contains('--conferir') ||
      monotonicityOutput != null ||
      levelOnly != null ||
      args.contains('--regravar');
  final traceIndex = args.indexOf('--rastro');
  final traceOnly = traceIndex >= 0 ? args[traceIndex + 1] : null;
  // **Regravar sobre a entrada já congelada.** Medir o efeito de uma mudança
  // pede gravar de novo *sem* atualizar cache, Ibovespa e universo — se a
  // entrada se mover junto com o código, a diferença mistura os dois. É o que
  // o `--conferir` já faz para comparar, e o que faltava para quantificar.
  final outputIndex = args.indexOf('--saida');
  final outputFile = outputIndex >= 0 ? args[outputIndex + 1] : _file;
  final rewrite = args.contains('--regravar');

  // **A entrada sai dos pacotes versionados, e não da base bruta.** Os
  // pacotes são o que o aplicativo lê, e vêm no clone: o gabarito passou a
  // reproduzir-se sem os 750 MB da CVM nem o arquivo do Tesouro, que não
  // sobrevivem a uma máquina nova. Antes a curva vinha do CSV do Tesouro e os
  // documentos, da base ingerida — as duas fontes de que o pacote é gerado.
  final curve = TreasuryCurve.at(
      TreasuryQuotesCodec.decode(
          jsonDecode(File('assets/tesouro/curva.json').readAsStringSync())
              as Map<String, dynamic>),
      _today);
  final registry = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final docs = CvmDocumentCodec.decodePackage(
      jsonDecode(File('assets/cvm/documentos.json').readAsStringSync())
          as Map<String, dynamic>);
  final terms = ConcessionTermsCodec.decode(
      jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
          as Map<String, dynamic>);
  final dividends = CashDividendsCodec.decode(
      jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
          as Map<String, dynamic>);
  // O prior do pacote e a composição declarada das units: são o que o
  // aplicativo lê, e por isso é deles que a montagem `aplicativo` parte
  // (itens B11 e B16). O prior **resolvido** sobre a entrada congelada continua
  // na montagem `prior`, que é o diagnóstico.
  final packagePrior = File('assets/mercado/beta_prior.json').existsSync()
      ? BetaPriorCodec.decode(
          jsonDecode(File('assets/mercado/beta_prior.json').readAsStringSync())
              as Map<String, dynamic>)
      : null;
  // O prêmio de mercado do pacote (decisão 142): a média de dez anos do
  // prêmio implícito na data do gabarito, que é o que o aplicativo lê. As
  // montagens `doisPontos` e `curva` ficam com os 5,5% parametrizados — são o
  // registro das montagens antigas, e não o aplicativo.
  final premiumPackage =
      File('assets/mercado/premio_implicito.json').existsSync()
          ? ImpliedPremiumCodec.decode(jsonDecode(
                  File('assets/mercado/premio_implicito.json')
                      .readAsStringSync()) as Map<String, dynamic>)
          : null;
  final packagePremium = premiumPackage?.normalizedAt(_today);
  if (packagePremium == null) {
    stderr.writeln('sem assets/mercado/premio_implicito.json utilizável: rode '
        'dart run tool/premio_implicito.dart --so-serie');
    exitCode = 2;
    return;
  }
  // Os eventos de capital do pacote (itens B28 e B29): a montagem do
  // aplicativo completa o ajuste da série e soma a emissão declarada.
  final capital = File('assets/cvm/capital.json').existsSync()
      ? CapitalEventsCodec.decodePackage(
          jsonDecode(File('assets/cvm/capital.json').readAsStringSync())
              as Map<String, dynamic>)
      : const <String, CapitalEvents>{};
  final units = File('assets/cvm/units.json').existsSync()
      ? UnitCompositionCodec.decodePackage(
          jsonDecode(File('assets/cvm/units.json').readAsStringSync())
              as Map<String, dynamic>)
      : const <String, List<UnitComposition>>{};
  // O controle acionário (item B46): a montagem do aplicativo leva a ressalva.
  final control = File('assets/cvm/controle.json').existsSync()
      ? ShareholderControlHistory.decode(
                  jsonDecode(File('assets/cvm/controle.json').readAsStringSync())
                      as Map<String, dynamic>)
              ?.byIssuer ??
          const <String, List<ShareholderControlPeriod>>{}
      : const <String, List<ShareholderControlPeriod>>{};
  bool stateOwned(Ticker t) {
    final p = control[t.value.substring(0, 4)];
    return p != null &&
        ShareholderControlHistory.at(p, _today) == ShareholderControl.state;
  }

  // O rastro de cada avaliação é capturado no fim da transação dela.
  AuditEvent? last;
  AuditRecorder.attach((e) => last = e);

  // A gravação parte de uma cópia do cache da validação; a conferência usa a
  // cópia que a gravação deixou.
  Directory(_folder).createSync(recursive: true);
  if (!check && traceOnly == null) {
    final origin = File('docs/validacao/${ValidationContext.cacheFileName}');
    if (origin.existsSync()) origin.copySync(_cache);
    if (File(_ibovespa).existsSync()) File(_ibovespa).deleteSync();
  } else if (!File(_cache).existsSync() || !File(_ibovespa).existsSync()) {
    stderr.writeln('sem entrada congelada em $_folder — grave o gabarito antes');
    exitCode = 2;
    return;
  }
  final ctx0 = ValidationContext.create(
      outputDir: 'docs/validacao', cacheFile: _cache, frozenCache: true);
  final ibov = _FrozenIbovespa(
    check || traceOnly != null ? null : ctx0.benchmark,
    check || traceOnly != null
        ? _FrozenIbovespa.fromJson(
            jsonDecode(File(_ibovespa).readAsStringSync())
                as Map<String, dynamic>)
        : {},
  );
  final ctx = (
    prices: ctx0.prices,
    fundamentals: ctx0.fundamentals,
    macro: ctx0.macro,
    benchmark: ibov as BenchmarkRepository,
  );
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _today,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    // **O universo também é entrada**, e vem da rede: em 15/09/2026 a fonte
    // passou a listar a EQPA7 e deixou de listar a COCE3, e as duas apareciam
    // como divergência do gabarito sem que o código tivesse mudado. A gravação
    // guarda a lista, e a conferência a repete.
    final savedUniverse = File(_universe);
    final List<Ticker> wholeUniverse;
    if (!check && traceOnly == null) {
      wholeUniverse = (await ctx.fundamentals.universe()).unwrap();
      savedUniverse.writeAsStringSync(
          jsonEncode([for (final t in wholeUniverse) t.value]));
    } else if (savedUniverse.existsSync()) {
      wholeUniverse = [
        for (final s in (jsonDecode(savedUniverse.readAsStringSync()) as List)
            .cast<String>())
          Ticker.parse(s),
      ];
    } else {
      wholeUniverse = (await ctx.fundamentals.universe()).unwrap();
    }
    var universe = wholeUniverse;
    if (traceOnly != null) {
      universe = [for (final t in universe) if (t.value == traceOnly) t];
    }

    B3Issuer? issuer(Ticker t) =>
        registry[t.value.length >= 4 ? t.value.substring(0, 4) : ''];
    Future<B3Classification?> shareClass(Ticker t) async =>
        issuer(t)?.classification;
    final fromCvm = _FromCvm(ctx.fundamentals, docs);
    final withSector = OfficialSectorFundamentalsRepository(
        inner: fromCvm, classification: shareClass);
    final anchoredWithSector = OfficialSectorFundamentalsRepository(
        inner: _FromCvm(ctx.fundamentals, docs, anchored: true),
        classification: shareClass);
    List<CashDividend> dividendsOf(Ticker t) =>
        CashDividendsCodec.forTicker(dividends, t.value);

    // O prior sai do universo inteiro, na montagem do aplicativo.
    final prior = await ResolveBetaPrior.call(
      tickers: wholeUniverse,
      prices: ctx.prices,
      fundamentals: withSector,
      benchmark: ctx.benchmark,
      asOf: _today,
      dividendsFor: dividendsOf,
    );
    if (prior == null) {
      stderr.writeln('sem prior do beta: as montagens com prior não valem');
      exitCode = 2;
      return;
    }

    Future<Result<ValuationInputs>> prepare(
      Ticker t, {
      required FundamentalsRepository fundamentals,
      YieldCurve? c,
      bool app = false,
      bool withPrior = false,
    }) {
      final e = issuer(t);
      return PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _today,
        marketPremium: app ? packagePremium : CapmInputs.defaultMarketPremium,
        premiumSource: app
            ? MarketPremiumSource.impliedNormalized
            : MarketPremiumSource.parameterized,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: c,
        projectionYears: 10,
        officialShares: app && e?.totalShares != null
            ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
            : null,
        concessionEnd: app ? terms[t.value]?.end : null,
        dividends: app ? dividendsOf(t) : null,
        // A montagem do aplicativo usa o prior **do pacote**, que é o que ele
        // lê; a montagem `prior` usa o resolvido sobre a entrada congelada.
        betaPrior: withPrior ? prior : (app ? packagePrior?.prior : null),
        declaredSharesPerUnit: app
            ? UnitCompositionCodec.at(units[t.value] ?? const [], _today)?.shares
            : null,
        shareEvents: app ? capital[t.value]?.shareEvents ?? const [] : const [],
        shareIssues: app ? capital[t.value]?.issues ?? const [] : const [],
        stateControlled: app && stateOwned(t),
      );
    }

    if (levelOnly != null) {
      AuditRecorder.detach();
      for (final (name, withPrior) in [('aplicativo', false), ('prior', true)]) {
        final p = await prepare(Ticker.parse(levelOnly),
            fundamentals: withSector, c: curve, app: true, withPrior: withPrior);
        if (p.isErr) continue;
        stdout.writeln('== $levelOnly, $name');
        _openGrid(p.unwrap());
      }
      return;
    }
    if (monotonicityOutput != null) {
      AuditRecorder.detach();
      await _sweepLevel(
        universe: universe,
        output: monotonicityOutput,
        app: (t) =>
            prepare(t, fundamentals: withSector, c: curve, app: true),
        prior: (t) => prepare(t,
            fundamentals: withSector, c: curve, app: true, withPrior: true),
      );
      return;
    }

    final traces = <String, Object?>{};
    Map<String, Object?> evaluate(ValuationInputs i, {bool random = false}) {
      last = null;
      final r = ValuationCascade.evaluate(
        i,
        scenarioBuilder: random ? StochasticScenarios.around : null,
        monteCarloSamples: 300,
      );
      final ev = last;
      // Pela serialização segura do evento (item D4): um `NaN` no rastro sai
      // como texto, em vez de derrubar a gravação do gabarito.
      final j = ev?.toJson();
      final trace = j == null
          ? null
          : jsonEncode({
              'entrada': j['inputPayload'],
              'saida': j['outputPayload'],
              'calculos': j['calculations'],
            });
      if (traceOnly != null) traces['${traces.length}'] = jsonDecode(trace ?? 'null');
      return {
        ..._serialize(r),
        'rastro': trace == null ? null : _fingerprint(trace),
      };
    }

    final output = <String, Object?>{};
    final coverage = <String, int>{};
    void account(String k) => coverage[k] = (coverage[k] ?? 0) + 1;
    var n = 0;
    for (final t in universe) {
      if (++n % 25 == 0) stderr.write('  $n/${universe.length}   \r');
      final row = <String, Object?>{};

      Future<void> assembly(
        String name,
        Future<Result<ValuationInputs>> prep,
        Map<String, Object?> Function(ValuationInputs) f,
      ) async {
        final p = await prep;
        if (p.isErr) {
          row[name] = {'preparo': p.failureOrNull!.message};
          return;
        }
        final s = f(p.unwrap());
        row[name] = s;
        final warnings = (s['avisos'] as List?)?.cast<String>() ?? const [];
        if (s.containsKey('recusa')) account('$name: recusa');
        if (warnings.any((a) => a.contains('resolvido ano a ano'))) {
          account('$name: taxas resolvidas');
        }
        if (warnings.any((a) => a.contains('não sustenta a via'))) {
          account('$name: estrutura recusada e migrada');
        }
        if (warnings.any((a) => a.contains('nenhuma das duas vias domina'))) {
          account('$name: vias mescladas');
        }
        if (warnings.any((a) => a.contains('migra para o fluxo do acionista'))) {
          account('$name: migração');
        }
        if (warnings.any((a) => a.contains('não se estabilizaram'))) {
          account('$name: veredito sem ponto fixo');
        }
        if (warnings.any((a) => a.contains('reconstruído do ciclo'))) {
          account('$name: base reconstruída');
        }
        if (warnings.any((a) => a.contains('até o fim do contrato'))) {
          account('$name: terminal do contrato');
        }
      }

      await assembly('doisPontos',
          prepare(t, fundamentals: ctx.fundamentals), evaluate);
      await assembly('curva',
          prepare(t, fundamentals: ctx.fundamentals, c: curve), evaluate);
      await assembly('aplicativo',
          prepare(t, fundamentals: withSector, c: curve, app: true), evaluate);
      await assembly(
          'ancorada',
          prepare(t, fundamentals: anchoredWithSector, c: curve, app: true),
          evaluate);
      final withPrior =
          prepare(t, fundamentals: withSector, c: curve, app: true, withPrior: true);
      await assembly('prior', withPrior, evaluate);
      await assembly(
          'monteCarlo', withPrior, (i) => evaluate(i, random: true));
      await assembly('viaFirma', withPrior,
          (i) => evaluate(_impose(i, lane: ValuationLane.firm)));
      await assembly('viaAcionista', withPrior,
          (i) => evaluate(_impose(i, lane: ValuationLane.shareholder)));
      await assembly(
          'impostos', withPrior, (i) => evaluate(_impose(i, everything: true)));
      output[t.value] = row;
    }
    stderr.writeln('');

    if (traceOnly != null) {
      stdout.writeln(const JsonEncoder.withIndent(' ').convert(traces));
      return;
    }

    final keys = coverage.keys.toList()..sort();
    stdout.writeln('cobertura dos caminhos (ativos por montagem):');
    for (final k in keys) {
      stdout.writeln('  ${k.padRight(44)} ${coverage[k]}');
    }
    final refusals = <String>{
      for (final l in output.values)
        for (final m in (l! as Map).values)
          if (m is Map && m['recusa'] != null)
            (m['recusa'] as String).replaceAll(RegExp(r'[\d.,]+'), '#'),
    };
    stdout.writeln('  formas distintas de recusa: ${refusals.length}');

    final text = const JsonEncoder.withIndent(' ').convert(output);
    if (!check) {
      File(_ibovespa).writeAsStringSync(jsonEncode(ibov.toJson()));
      File(_file).writeAsStringSync(text);
      stdout.writeln('gabarito gravado: ${output.length} ativos em $_file');
      return;
    }
    if (rewrite) {
      File(outputFile).writeAsStringSync(text);
      stdout.writeln('gabarito regravado sobre a entrada congelada: '
          '${output.length} ativos em $outputFile');
      return;
    }

    final saved = jsonDecode(File(_file).readAsStringSync())
        as Map<String, dynamic>;
    final now = jsonDecode(text) as Map<String, dynamic>;
    final divergent = <String>[];
    for (final k in {...saved.keys, ...now.keys}) {
      final g = saved[k] as Map<String, dynamic>?;
      final a = now[k] as Map<String, dynamic>?;
      for (final m in {...?g?.keys, ...?a?.keys}) {
        if (jsonEncode(g?[m]) != jsonEncode(a?[m])) divergent.add('$k/$m');
      }
    }
    divergent.sort();
    if (divergent.isEmpty) {
      stdout.writeln('GABARITO IDÊNTICO: ${now.length} ativos, nove '
          'montagens cada, saída completa e rastro bit a bit.');
    } else {
      stdout.writeln('GABARITO DIVERGE em ${divergent.length} montagem(ns):');
      // Por montagem, primeiro: a entrada da CVM não é congelada, e uma
      // reingestão muda a `ancorada` sem que o código tenha mudado.
      final byAssembly = <String, int>{};
      for (final k in divergent) {
        final m = k.substring(k.indexOf('/') + 1);
        byAssembly[m] = (byAssembly[m] ?? 0) + 1;
      }
      stdout.writeln('  por montagem: $byAssembly');
      for (final k in divergent.where((k) => !k.endsWith('/ancorada'))) {
        stdout.writeln('  $k');
      }
      for (final k in divergent.take(30)) {
        stdout.writeln('  $k');
      }
      exitCode = 1;
    }
  } finally {
    AuditRecorder.detach();
    await ctx0.dispose();
  }
}

/// Deslocamentos do nível da taxa livre de risco na varredura do B10.
final _grid = [for (var i = -12; i <= 12; i++) i * 0.0025];

/// A varredura do nível da curva (item B10): em cada ativo e montagem, o preço
/// justo ao longo da grade, e se ele sobe quando o capital encarece.
///
/// **Tolerância de 0,1% do preço de mercado**, a mesma do `dcf_reverso`:
/// variação abaixo disso é ruído de ponto flutuante, e não direção.
Future<void> _sweepLevel({
  required List<Ticker> universe,
  required String output,
  required Future<Result<ValuationInputs>> Function(Ticker) app,
  required Future<Result<ValuationInputs>> Function(Ticker) prior,
}) async {
  final rows = <String, Object?>{};
  final summary = <String, Map<String, int>>{};
  void account(String assembly, String k) {
    final m = summary[assembly] ??= <String, int>{};
    m[k] = (m[k] ?? 0) + 1;
  }

  String status(ValuationResult v) {
    final warnings = v.warnings.join(' ');
    if (warnings.contains('nenhuma das duas vias domina')) return 'mescla';
    if (warnings.contains('não sustenta a via')) return 'estruturaRecusada';
    if (warnings.contains('migra para o fluxo do acionista')) return 'migrada';
    return v.model.name;
  }

  var n = 0;
  for (final t in universe) {
    if (++n % 25 == 0) stderr.write('  $n/${universe.length}   \r');
    final row = <String, Object?>{};
    for (final (name, prep) in [('aplicativo', app), ('prior', prior)]) {
      final p = await prep(t);
      if (p.isErr) continue;
      final base = p.unwrap();
      final r0 = ValuationCascade.evaluate(base);
      if (r0.isErr) continue;
      account(name, 'avaliados na base');
      final price = base.marketPrice;
      final fairValues = <double?>[];
      final states = <String?>[];
      for (final d in _grid) {
        final r = ValuationCascade.evaluate(base.withRiskFreeShift(d));
        fairValues.add(r.isOk ? r.unwrap().fairValue.reais : null);
        states.add(r.isOk ? status(r.unwrap()) : null);
      }
      // Sobe quando o capital encarece: entre dois pontos avaliados em
      // sequência, o de taxa maior vale mais.
      final tol = price * 1e-3;
      var rises = 0;
      var largestRise = 0.0;
      double? previous;
      for (final j in fairValues) {
        if (j == null) {
          previous = null;
          continue;
        }
        if (previous != null && j - previous > tol) {
          rises++;
          final rel = previous > 0 ? (j - previous) / previous : double.infinity;
          if (rel > largestRise) largestRise = rel;
        }
        previous = j;
      }
      final evaluated = [for (var i = 0; i < fairValues.length; i++) if (fairValues[i] != null) i];
      final gaps = evaluated.isEmpty
          ? 0
          : [
              for (var i = evaluated.first; i <= evaluated.last; i++)
                if (fairValues[i] == null) i,
            ].length;
      final lanes = {...states.nonNulls};
      if (rises > 0) account(name, 'não monótonos');
      if (rises > 0 && lanes.length > 1) account(name, 'não monótonos com troca de via');
      if (lanes.length > 1) account(name, 'trocam de via na grade');
      if (gaps > 0) account(name, 'recusados no meio da grade');
      row[name] = {
        'estadoNaBase': status(r0.unwrap()),
        'justoNaBase': r0.unwrap().fairValue.reais,
        'preco': price,
        'subidas': rises,
        'maiorSubidaRelativa': largestRise.isFinite ? largestRise : null,
        'lacunas': gaps,
        'vias': lanes.toList()..sort(),
        'justos': fairValues,
      };
    }
    if (row.isNotEmpty) rows[t.value] = row;
  }
  stderr.writeln('');
  File(output).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'hoje': _today.toIso8601String().substring(0, 10),
    'grade': _grid,
    'resumo': summary,
    'ativos': rows,
  }));
  stdout.writeln('varredura do nível da curva, de −3 a +3 p.p.:');
  for (final e in summary.entries) {
    stdout.writeln('  ${e.key}: ${e.value}');
  }
  stdout.writeln('gravado $output');
}

/// A grade de um ativo, aberta: o que muda no diagnóstico a cada ponto.
void _openGrid(ValuationInputs base) {
  String pc(double? x) => x == null ? '—' : '${(x * 100).toStringAsFixed(2)}%';
  List<String>? previousWarnings;
  for (final d in _grid) {
    final r = ValuationCascade.evaluate(base.withRiskFreeShift(d));
    if (r.isErr) {
      stdout.writeln('${pc(d).padLeft(7)}  recusa: ${r.failureOrNull!.message}');
      previousWarnings = null;
      continue;
    }
    final v = r.unwrap();
    final g = v.diagnostics;
    stdout.writeln('${pc(d).padLeft(7)}  R\$ ${v.fairValue.reais.toStringAsFixed(2).padLeft(8)}'
        '  ${v.model.name.padRight(12)} desc ${pc(v.discountRate)}'
        '  g ${pc(g?.growthRate)}  base ${g?.baseFactor.toStringAsFixed(3)}'
        '  moat ${g?.moatApplied}  retido ${pc(g?.terminalRetainedSpread)}'
        '  rTerm ${pc(g?.terminalReturnOnCapital)}  equity ${pc(g?.equityShare)}'
        '  ressalvas ${g?.caveats.map((c) => c.key).join(',')}');
    // Os avisos que entram ou saem de um ponto para o outro: é onde está o
    // degrau, quando há um.
    final warnings = [
      for (final a in v.warnings) a.replaceAll(RegExp(r'[\d.,]+'), '#'),
    ];
    if (previousWarnings != null) {
      for (final a in warnings.where((a) => !previousWarnings!.contains(a))) {
        stdout.writeln('           + ${a.length > 150 ? a.substring(0, 150) : a}');
      }
      for (final a in previousWarnings.where((a) => !warnings.contains(a))) {
        stdout.writeln('           - ${a.length > 150 ? a.substring(0, 150) : a}');
      }
    }
    previousWarnings = warnings;
  }
}
