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
//   dart run tool/gabarito_cascata.dart --rastro PETR4 # rastro de um ativo
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'curva_ligar.dart' show lerTesouro;
import 'cvm/documentos.dart';
import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 14);
const _arquivo = 'docs/validacao/gabarito_cascata.json';
const _pasta = 'data/gabarito';
const _cache = '$_pasta/cache.sqlite';
const _ibovespa = '$_pasta/ibovespa.json';

/// O Ibovespa servido, por janela: gravado na primeira execução e repetido nas
/// seguintes. Janela que não foi gravada é recusada, e a divergência aparece.
class _IbovespaCongelado implements BenchmarkRepository {
  _IbovespaCongelado(this.rede, this.gravado);
  final BenchmarkRepository? rede;
  final Map<String, PriceSeries> gravado;

  static String _chave(DateRange r) =>
      '${r.start.toIso8601String()}|${r.end.toIso8601String()}';

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    final k = _chave(range);
    final g = gravado[k];
    if (g != null) return Ok(g);
    final fonte = rede;
    if (fonte == null) {
      return Err(InsufficientData('Ibovespa não gravado para $k'));
    }
    final r = await fonte.ibovespa(range);
    if (r.isOk) gravado[k] = r.unwrap();
    return r;
  }

  Map<String, Object?> toJson() => {
        for (final e in gravado.entries)
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
String _impressao(String texto) {
  var h = 0xcbf29ce484222325;
  for (final u in utf8.encode(texto)) {
    h ^= u;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Tudo o que o resultado expõe. `double.toString()` é a representação mais
/// curta que volta ao mesmo bit — é o que torna a comparação exata.
Map<String, Object?> _serializar(Result<ValuationResult> r) {
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
        'impressao': _impressao(dist.sortedValues.join(',')),
      },
    'avisos': v.warnings,
    if (d != null)
      'diagnostico': {
        'pesoTerminal': d.terminalShare.toString(),
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
        'ressalvas': [for (final c in d.caveats) c.name],
      },
  };
}

/// Os mesmos insumos com as imposições de diagnóstico. `ValuationInputs` não
/// tem cópia genérica, e é de propósito: as imposições não são do aplicativo.
ValuationInputs _impor(
  ValuationInputs b, {
  ValuationLane? via,
  bool tudo = false,
}) =>
    ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: b.capm,
      marginOfSafety: b.marginOfSafety,
      projectionYears: b.projectionYears,
      perpetualGrowthCap: b.perpetualGrowthCap,
      sectorKey: b.sectorKey,
      industry: b.industry,
      inflation: b.inflation,
      declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
      riskFreeCurve: b.riskFreeCurve,
      officialShares: b.officialShares,
      prices: b.prices,
      isDistressed: b.isDistressed,
      unleveredBeta: b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
      laneOverride: via,
      terminalReturnOverride: tudo ? 0.13 : null,
      growthOverride: tudo ? 0.06 : null,
      baseFactorOverride: tudo ? 1.1 : null,
      reinvestmentOverride: tudo ? ReinvestmentPolicy.crescimentoReal : null,
      cashTimingOverride: tudo ? CashTiming.fimDeAno : null,
    );

class _DaCvm implements FundamentalsRepository {
  final FundamentalsRepository mercado;
  final Map<String, List<CvmPeriodDocument>> docs;
  final bool ancorada;
  _DaCvm(this.mercado, this.docs, {this.ancorada = false});

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await mercado.history(t);
    if (base.isErr) return base;
    final meus = docs[t.value];
    if (meus == null || meus.isEmpty) return base;
    return Ok(CvmSeries.build(
      documentos: meus,
      mercado: base.unwrap(),
      asOf: _hoje,
      publicado: PointInTimeView(_hoje).isPublished,
      ancorada: ancorada,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => mercado.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => mercado.universe();
}

Future<void> main(List<String> args) async {
  final conferir = args.contains('--conferir');
  final iRastro = args.indexOf('--rastro');
  final soRastro = iRastro >= 0 ? args[iRastro + 1] : null;

  final curva = TreasuryCurve.at(
      lerTesouro('data/tesouro/precotaxatesourodireto.csv'), _hoje);
  final registro = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final docs = carregarDocumentos('data/cvm_exercicios.json');
  final prazos = ConcessionTermsCodec.decode(
      jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
          as Map<String, dynamic>);
  final proventos = CashDividendsCodec.decode(
      jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
          as Map<String, dynamic>);

  // O rastro de cada avaliação é capturado no fim da transação dela.
  AuditEvent? ultimo;
  AuditRecorder.attach((e) => ultimo = e);

  // A gravação parte de uma cópia do cache da validação; a conferência usa a
  // cópia que a gravação deixou.
  Directory(_pasta).createSync(recursive: true);
  if (!conferir && soRastro == null) {
    final origem = File('docs/validacao/${ValidationContext.cacheFileName}');
    if (origem.existsSync()) origem.copySync(_cache);
    if (File(_ibovespa).existsSync()) File(_ibovespa).deleteSync();
  } else if (!File(_cache).existsSync() || !File(_ibovespa).existsSync()) {
    stderr.writeln('sem entrada congelada em $_pasta — grave o gabarito antes');
    exitCode = 2;
    return;
  }
  final ctx0 = ValidationContext.create(
      outputDir: 'docs/validacao', cacheFile: _cache, frozenCache: true);
  final ibov = _IbovespaCongelado(
    conferir || soRastro != null ? null : ctx0.benchmark,
    conferir || soRastro != null
        ? _IbovespaCongelado.fromJson(
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
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    var universe = (await ctx.fundamentals.universe()).unwrap();
    if (soRastro != null) {
      universe = [for (final t in universe) if (t.value == soRastro) t];
    }

    B3Issuer? emissor(Ticker t) =>
        registro[t.value.length >= 4 ? t.value.substring(0, 4) : ''];
    Future<B3Classification?> classe(Ticker t) async =>
        emissor(t)?.classification;
    final daCvm = _DaCvm(ctx.fundamentals, docs);
    final comSetor = OfficialSectorFundamentalsRepository(
        inner: daCvm, classificacao: classe);
    final ancoradaComSetor = OfficialSectorFundamentalsRepository(
        inner: _DaCvm(ctx.fundamentals, docs, ancorada: true),
        classificacao: classe);
    List<CashDividend> proventosDe(Ticker t) =>
        CashDividendsCodec.forTicker(proventos, t.value);

    // O prior sai do universo inteiro, na montagem do aplicativo.
    final prior = await ResolveBetaPrior.call(
      tickers: (await ctx.fundamentals.universe()).unwrap(),
      prices: ctx.prices,
      fundamentals: comSetor,
      benchmark: ctx.benchmark,
      asOf: _hoje,
      dividendsFor: proventosDe,
    );
    if (prior == null) {
      stderr.writeln('sem prior do beta: as montagens com prior não valem');
      exitCode = 2;
      return;
    }

    Future<Result<ValuationInputs>> preparar(
      Ticker t, {
      required FundamentalsRepository fundamentos,
      YieldCurve? c,
      bool app = false,
      bool comPrior = false,
    }) {
      final e = emissor(t);
      return PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: fundamentos,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _hoje,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: c,
        projectionYears: 10,
        officialShares: app && e?.totalShares != null
            ? OfficialShareCount(total: e!.totalShares!, asOf: e.consultedOn)
            : null,
        concessionEnd: app ? prazos[t.value]?.end : null,
        dividends: app ? proventosDe(t) : null,
        betaPrior: comPrior ? prior : null,
      );
    }

    final rastros = <String, Object?>{};
    Map<String, Object?> avaliar(ValuationInputs i, {bool sorteio = false}) {
      ultimo = null;
      final r = ValuationCascade.evaluate(
        i,
        scenarioBuilder: sorteio ? StochasticScenarios.around : null,
        monteCarloSamples: 300,
      );
      final ev = ultimo;
      final rastro = ev == null
          ? null
          : jsonEncode({
              'entrada': ev.inputPayload,
              'saida': ev.outputPayload,
              'calculos': [for (final c in ev.calculations) c.toJson()],
            });
      if (soRastro != null) rastros['${rastros.length}'] = jsonDecode(rastro ?? 'null');
      return {
        ..._serializar(r),
        'rastro': rastro == null ? null : _impressao(rastro),
      };
    }

    final saida = <String, Object?>{};
    final cobertura = <String, int>{};
    void conta(String k) => cobertura[k] = (cobertura[k] ?? 0) + 1;
    var n = 0;
    for (final t in universe) {
      if (++n % 25 == 0) stderr.write('  $n/${universe.length}   \r');
      final linha = <String, Object?>{};

      Future<void> montagem(
        String nome,
        Future<Result<ValuationInputs>> prep,
        Map<String, Object?> Function(ValuationInputs) f,
      ) async {
        final p = await prep;
        if (p.isErr) {
          linha[nome] = {'preparo': p.failureOrNull!.message};
          return;
        }
        final s = f(p.unwrap());
        linha[nome] = s;
        final avisos = (s['avisos'] as List?)?.cast<String>() ?? const [];
        if (s.containsKey('recusa')) conta('$nome: recusa');
        if (avisos.any((a) => a.contains('resolvido ano a ano'))) {
          conta('$nome: taxas resolvidas');
        }
        if (avisos.any((a) => a.contains('não sustenta a via'))) {
          conta('$nome: estrutura recusada e migrada');
        }
        if (avisos.any((a) => a.contains('nenhuma das duas vias domina'))) {
          conta('$nome: vias mescladas');
        }
        if (avisos.any((a) => a.contains('migra para o fluxo do acionista'))) {
          conta('$nome: migração');
        }
        if (avisos.any((a) => a.contains('não se estabilizaram'))) {
          conta('$nome: veredito sem ponto fixo');
        }
        if (avisos.any((a) => a.contains('reconstruído do ciclo'))) {
          conta('$nome: base reconstruída');
        }
        if (avisos.any((a) => a.contains('até o fim do contrato'))) {
          conta('$nome: terminal do contrato');
        }
      }

      await montagem('doisPontos',
          preparar(t, fundamentos: ctx.fundamentals), avaliar);
      await montagem('curva',
          preparar(t, fundamentos: ctx.fundamentals, c: curva), avaliar);
      await montagem('aplicativo',
          preparar(t, fundamentos: comSetor, c: curva, app: true), avaliar);
      await montagem(
          'ancorada',
          preparar(t, fundamentos: ancoradaComSetor, c: curva, app: true),
          avaliar);
      final comPrior =
          preparar(t, fundamentos: comSetor, c: curva, app: true, comPrior: true);
      await montagem('prior', comPrior, avaliar);
      await montagem(
          'monteCarlo', comPrior, (i) => avaliar(i, sorteio: true));
      await montagem('viaFirma', comPrior,
          (i) => avaliar(_impor(i, via: ValuationLane.firm)));
      await montagem('viaAcionista', comPrior,
          (i) => avaliar(_impor(i, via: ValuationLane.shareholder)));
      await montagem(
          'impostos', comPrior, (i) => avaliar(_impor(i, tudo: true)));
      saida[t.value] = linha;
    }
    stderr.writeln('');

    if (soRastro != null) {
      stdout.writeln(const JsonEncoder.withIndent(' ').convert(rastros));
      return;
    }

    final chaves = cobertura.keys.toList()..sort();
    stdout.writeln('cobertura dos caminhos (ativos por montagem):');
    for (final k in chaves) {
      stdout.writeln('  ${k.padRight(44)} ${cobertura[k]}');
    }
    final recusas = <String>{
      for (final l in saida.values)
        for (final m in (l! as Map).values)
          if (m is Map && m['recusa'] != null)
            (m['recusa'] as String).replaceAll(RegExp(r'[\d.,]+'), '#'),
    };
    stdout.writeln('  formas distintas de recusa: ${recusas.length}');

    final texto = const JsonEncoder.withIndent(' ').convert(saida);
    if (!conferir) {
      File(_ibovespa).writeAsStringSync(jsonEncode(ibov.toJson()));
      File(_arquivo).writeAsStringSync(texto);
      stdout.writeln('gabarito gravado: ${saida.length} ativos em $_arquivo');
      return;
    }

    final gravado = jsonDecode(File(_arquivo).readAsStringSync())
        as Map<String, dynamic>;
    final agora = jsonDecode(texto) as Map<String, dynamic>;
    final divergentes = <String>[];
    for (final k in {...gravado.keys, ...agora.keys}) {
      final g = gravado[k] as Map<String, dynamic>?;
      final a = agora[k] as Map<String, dynamic>?;
      for (final m in {...?g?.keys, ...?a?.keys}) {
        if (jsonEncode(g?[m]) != jsonEncode(a?[m])) divergentes.add('$k/$m');
      }
    }
    divergentes.sort();
    if (divergentes.isEmpty) {
      stdout.writeln('GABARITO IDÊNTICO: ${agora.length} ativos, nove '
          'montagens cada, saída completa e rastro bit a bit.');
    } else {
      stdout.writeln('GABARITO DIVERGE em ${divergentes.length} montagem(ns):');
      for (final k in divergentes.take(30)) {
        stdout.writeln('  $k');
      }
      exitCode = 1;
    }
  } finally {
    AuditRecorder.detach();
    await ctx0.dispose();
  }
}
