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

final _hoje = DateTime(2026, 9, 14);
const _arquivo = 'docs/validacao/gabarito_cascata.json';
const _pasta = 'data/gabarito';
const _cache = '$_pasta/cache.sqlite';
const _ibovespa = '$_pasta/ibovespa.json';
const _universo = '$_pasta/universo.json';

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
  final iMonotonia = args.indexOf('--monotonia');
  final saidaMonotonia = iMonotonia >= 0 ? args[iMonotonia + 1] : null;
  final iNivel = args.indexOf('--nivel');
  final soNivel = iNivel >= 0 ? args[iNivel + 1] : null;
  final conferir = args.contains('--conferir') ||
      saidaMonotonia != null ||
      soNivel != null ||
      args.contains('--regravar');
  final iRastro = args.indexOf('--rastro');
  final soRastro = iRastro >= 0 ? args[iRastro + 1] : null;
  // **Regravar sobre a entrada já congelada.** Medir o efeito de uma mudança
  // pede gravar de novo *sem* atualizar cache, Ibovespa e universo — se a
  // entrada se mover junto com o código, a diferença mistura os dois. É o que
  // o `--conferir` já faz para comparar, e o que faltava para quantificar.
  final iSaida = args.indexOf('--saida');
  final saidaArquivo = iSaida >= 0 ? args[iSaida + 1] : _arquivo;
  final regravar = args.contains('--regravar');

  // **A entrada sai dos pacotes versionados, e não da base bruta.** Os
  // pacotes são o que o aplicativo lê, e vêm no clone: o gabarito passou a
  // reproduzir-se sem os 750 MB da CVM nem o arquivo do Tesouro, que não
  // sobrevivem a uma máquina nova. Antes a curva vinha do CSV do Tesouro e os
  // documentos, da base ingerida — as duas fontes de que o pacote é gerado.
  final curva = TreasuryCurve.at(
      TreasuryQuotesCodec.decode(
          jsonDecode(File('assets/tesouro/curva.json').readAsStringSync())
              as Map<String, dynamic>),
      _hoje);
  final registro = B3RegistryCodec.decodePackage(
      jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
          as Map<String, dynamic>);
  final docs = CvmDocumentCodec.decodePackage(
      jsonDecode(File('assets/cvm/documentos.json').readAsStringSync())
          as Map<String, dynamic>);
  final prazos = ConcessionTermsCodec.decode(
      jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
          as Map<String, dynamic>);
  final proventos = CashDividendsCodec.decode(
      jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
          as Map<String, dynamic>);
  // O prior do pacote e a composição declarada das units: são o que o
  // aplicativo lê, e por isso é deles que a montagem `aplicativo` parte
  // (itens B11 e B16). O prior **resolvido** sobre a entrada congelada continua
  // na montagem `prior`, que é o diagnóstico.
  final priorDoPacote = File('assets/mercado/beta_prior.json').existsSync()
      ? BetaPriorCodec.decode(
          jsonDecode(File('assets/mercado/beta_prior.json').readAsStringSync())
              as Map<String, dynamic>)
      : null;
  final units = File('assets/cvm/units.json').existsSync()
      ? UnitCompositionCodec.decodePackage(
          jsonDecode(File('assets/cvm/units.json').readAsStringSync())
              as Map<String, dynamic>)
      : const <String, List<UnitComposition>>{};

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
    // **O universo também é entrada**, e vem da rede: em 15/09/2026 a fonte
    // passou a listar a EQPA7 e deixou de listar a COCE3, e as duas apareciam
    // como divergência do gabarito sem que o código tivesse mudado. A gravação
    // guarda a lista, e a conferência a repete.
    final universoGravado = File(_universo);
    final List<Ticker> universoInteiro;
    if (!conferir && soRastro == null) {
      universoInteiro = (await ctx.fundamentals.universe()).unwrap();
      universoGravado.writeAsStringSync(
          jsonEncode([for (final t in universoInteiro) t.value]));
    } else if (universoGravado.existsSync()) {
      universoInteiro = [
        for (final s in (jsonDecode(universoGravado.readAsStringSync()) as List)
            .cast<String>())
          Ticker.parse(s),
      ];
    } else {
      universoInteiro = (await ctx.fundamentals.universe()).unwrap();
    }
    var universe = universoInteiro;
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
      tickers: universoInteiro,
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
        // A montagem do aplicativo usa o prior **do pacote**, que é o que ele
        // lê; a montagem `prior` usa o resolvido sobre a entrada congelada.
        betaPrior: comPrior ? prior : (app ? priorDoPacote?.prior : null),
        declaredSharesPerUnit: app
            ? UnitCompositionCodec.at(units[t.value] ?? const [], _hoje)?.shares
            : null,
      );
    }

    if (soNivel != null) {
      AuditRecorder.detach();
      for (final (nome, comPrior) in [('aplicativo', false), ('prior', true)]) {
        final p = await preparar(Ticker.parse(soNivel),
            fundamentos: comSetor, c: curva, app: true, comPrior: comPrior);
        if (p.isErr) continue;
        stdout.writeln('== $soNivel, $nome');
        _abrirGrade(p.unwrap());
      }
      return;
    }
    if (saidaMonotonia != null) {
      AuditRecorder.detach();
      await _varrerNivel(
        universe: universe,
        saida: saidaMonotonia,
        aplicativo: (t) =>
            preparar(t, fundamentos: comSetor, c: curva, app: true),
        prior: (t) => preparar(t,
            fundamentos: comSetor, c: curva, app: true, comPrior: true),
      );
      return;
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
    if (regravar) {
      File(saidaArquivo).writeAsStringSync(texto);
      stdout.writeln('gabarito regravado sobre a entrada congelada: '
          '${saida.length} ativos em $saidaArquivo');
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
      // Por montagem, primeiro: a entrada da CVM não é congelada, e uma
      // reingestão muda a `ancorada` sem que o código tenha mudado.
      final porMontagem = <String, int>{};
      for (final k in divergentes) {
        final m = k.substring(k.indexOf('/') + 1);
        porMontagem[m] = (porMontagem[m] ?? 0) + 1;
      }
      stdout.writeln('  por montagem: $porMontagem');
      for (final k in divergentes.where((k) => !k.endsWith('/ancorada'))) {
        stdout.writeln('  $k');
      }
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

/// Deslocamentos do nível da taxa livre de risco na varredura do B10.
final _grade = [for (var i = -12; i <= 12; i++) i * 0.0025];

/// A varredura do nível da curva (item B10): em cada ativo e montagem, o preço
/// justo ao longo da grade, e se ele sobe quando o capital encarece.
///
/// **Tolerância de 0,1% do preço de mercado**, a mesma do `dcf_reverso`:
/// variação abaixo disso é ruído de ponto flutuante, e não direção.
Future<void> _varrerNivel({
  required List<Ticker> universe,
  required String saida,
  required Future<Result<ValuationInputs>> Function(Ticker) aplicativo,
  required Future<Result<ValuationInputs>> Function(Ticker) prior,
}) async {
  final linhas = <String, Object?>{};
  final resumo = <String, Map<String, int>>{};
  void conta(String montagem, String k) {
    final m = resumo[montagem] ??= <String, int>{};
    m[k] = (m[k] ?? 0) + 1;
  }

  String estado(ValuationResult v) {
    final avisos = v.warnings.join(' ');
    if (avisos.contains('nenhuma das duas vias domina')) return 'mescla';
    if (avisos.contains('não sustenta a via')) return 'estruturaRecusada';
    if (avisos.contains('migra para o fluxo do acionista')) return 'migrada';
    return v.model.name;
  }

  var n = 0;
  for (final t in universe) {
    if (++n % 25 == 0) stderr.write('  $n/${universe.length}   \r');
    final linha = <String, Object?>{};
    for (final (nome, prep) in [('aplicativo', aplicativo), ('prior', prior)]) {
      final p = await prep(t);
      if (p.isErr) continue;
      final base = p.unwrap();
      final r0 = ValuationCascade.evaluate(base);
      if (r0.isErr) continue;
      conta(nome, 'avaliados na base');
      final preco = base.marketPrice;
      final justos = <double?>[];
      final estados = <String?>[];
      for (final d in _grade) {
        final r = ValuationCascade.evaluate(base.withRiskFreeShift(d));
        justos.add(r.isOk ? r.unwrap().fairValue.reais : null);
        estados.add(r.isOk ? estado(r.unwrap()) : null);
      }
      // Sobe quando o capital encarece: entre dois pontos avaliados em
      // sequência, o de taxa maior vale mais.
      final tol = preco * 1e-3;
      var subidas = 0;
      var maiorSubida = 0.0;
      double? anterior;
      for (final j in justos) {
        if (j == null) {
          anterior = null;
          continue;
        }
        if (anterior != null && j - anterior > tol) {
          subidas++;
          final rel = anterior > 0 ? (j - anterior) / anterior : double.infinity;
          if (rel > maiorSubida) maiorSubida = rel;
        }
        anterior = j;
      }
      final avaliados = [for (var i = 0; i < justos.length; i++) if (justos[i] != null) i];
      final lacunas = avaliados.isEmpty
          ? 0
          : [
              for (var i = avaliados.first; i <= avaliados.last; i++)
                if (justos[i] == null) i,
            ].length;
      final vias = {...estados.nonNulls};
      if (subidas > 0) conta(nome, 'não monótonos');
      if (subidas > 0 && vias.length > 1) conta(nome, 'não monótonos com troca de via');
      if (vias.length > 1) conta(nome, 'trocam de via na grade');
      if (lacunas > 0) conta(nome, 'recusados no meio da grade');
      linha[nome] = {
        'estadoNaBase': estado(r0.unwrap()),
        'justoNaBase': r0.unwrap().fairValue.reais,
        'preco': preco,
        'subidas': subidas,
        'maiorSubidaRelativa': maiorSubida.isFinite ? maiorSubida : null,
        'lacunas': lacunas,
        'vias': vias.toList()..sort(),
        'justos': justos,
      };
    }
    if (linha.isNotEmpty) linhas[t.value] = linha;
  }
  stderr.writeln('');
  File(saida).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'hoje': _hoje.toIso8601String().substring(0, 10),
    'grade': _grade,
    'resumo': resumo,
    'ativos': linhas,
  }));
  stdout.writeln('varredura do nível da curva, de −3 a +3 p.p.:');
  for (final e in resumo.entries) {
    stdout.writeln('  ${e.key}: ${e.value}');
  }
  stdout.writeln('gravado $saida');
}

/// A grade de um ativo, aberta: o que muda no diagnóstico a cada ponto.
void _abrirGrade(ValuationInputs base) {
  String pc(double? x) => x == null ? '—' : '${(x * 100).toStringAsFixed(2)}%';
  List<String>? avisosAnteriores;
  for (final d in _grade) {
    final r = ValuationCascade.evaluate(base.withRiskFreeShift(d));
    if (r.isErr) {
      stdout.writeln('${pc(d).padLeft(7)}  recusa: ${r.failureOrNull!.message}');
      avisosAnteriores = null;
      continue;
    }
    final v = r.unwrap();
    final g = v.diagnostics;
    stdout.writeln('${pc(d).padLeft(7)}  R\$ ${v.fairValue.reais.toStringAsFixed(2).padLeft(8)}'
        '  ${v.model.name.padRight(12)} desc ${pc(v.discountRate)}'
        '  g ${pc(g?.growthRate)}  base ${g?.baseFactor.toStringAsFixed(3)}'
        '  moat ${g?.moatApplied}  retido ${pc(g?.terminalRetainedSpread)}'
        '  rTerm ${pc(g?.terminalReturnOnCapital)}  equity ${pc(g?.equityShare)}'
        '  ressalvas ${g?.caveats.map((c) => c.name).join(',')}');
    // Os avisos que entram ou saem de um ponto para o outro: é onde está o
    // degrau, quando há um.
    final avisos = [
      for (final a in v.warnings) a.replaceAll(RegExp(r'[\d.,]+'), '#'),
    ];
    if (avisosAnteriores != null) {
      for (final a in avisos.where((a) => !avisosAnteriores!.contains(a))) {
        stdout.writeln('           + ${a.length > 150 ? a.substring(0, 150) : a}');
      }
      for (final a in avisosAnteriores.where((a) => !avisos.contains(a))) {
        stdout.writeln('           - ${a.length > 150 ? a.substring(0, 150) : a}');
      }
    }
    avisosAnteriores = avisos;
  }
}
