// Validação preditiva do motor de avaliação, *point-in-time*.
//
// **A pergunta.** O potencial que o motor apura ordena o retorno que veio
// depois? Sem essa medição, o motor tem consistência interna e cobertura
// declarada — e nenhuma evidência de que serve para decidir.
//
// **Como.** Para cada data de coorte, a cascata roda com o que era público
// naquele dia: exercícios filtrados por `PointInTimeView`, preço e beta na
// janela que termina ali, âncoras macro resolvidas naquela data. O potencial
// resultante é confrontado com o retorno realizado nos 12 e nos 36 meses
// seguintes — 36 é o horizonte de convergência da decisão 26.
//
// **Contra o quê.** Sozinho, um coeficiente de correlação não diz se a
// sofisticação se paga. O potencial é medido lado a lado com dois fatores
// ingênuos que usam os mesmos dados e nenhuma modelagem: o valor patrimonial
// sobre o preço e o lucro sobre o preço. Se o motor não os supera, a cascata
// inteira está cobrando um custo de complexidade que não entrega.
//
// **Vieses que esta medição NÃO remove**, e que o relatório declara:
//
// 1. *Sobrevivência.* O universo é o que está listado hoje. Quem fechou
//    capital ou quebrou entre a coorte e o resgate não está aqui, e isso
//    infla o retorno de todas as carteiras medidas — inclusive as ingênuas.
//    Afeta o **nível**; afeta menos a **ordenação**, que é o que se mede.
// 2. *Reapresentação.* Os exercícios vêm como a fonte os publica hoje, não
//    como estavam no dia da coorte. Reapresentação contábil entra como
//    conhecimento futuro.
// 3. *Provento.* O retorno de referência continua o de preço, e ao lado dele
//    sai o **retorno total** — `ret12tot` e `ret36tot` —, com os proventos da
//    B3 reinvestidos na data ex (item A4, decisão 89). O valor que o motor
//    apura inclui a distribuição, então só o de preço **penaliza** o motor em
//    ativo de *payout* alto. A leitura por `adjustedClose` segue, secundária:
//    a conferência de `tool/proventos_conferir.dart` mede o ajuste da fonte.
//
// **Duas montagens.** `mercado` é a das medições de 11/09/2026: só a fonte de
// preços, com a taxa de dois pontos. `aplicativo` é a montagem do aplicativo
// **na data de cada coorte**, peça a peça:
//
// - a curva do Tesouro daquele dia (decisão 74);
// - a CVM mesclada, com os documentos recebidos até ali (decisões 69 a 81);
// - o setor da B3 (decisão 87) — a classificação é a de hoje, e setor muda
//   pouco; é a única peça que não é da data;
// - o prazo das outorgas do Formulário de Referência recebido até ali
//   (decisão 88, `tool/cvm/outorgas_por_data.dart`);
// - o beta sobre retorno total, com os proventos da B3 (decisão 89).
//
// A contagem oficial da B3 fica de fora por construção: ela é de hoje, e a
// reescala abaixo reconstrói o valor de mercado da coorte.
//
// Na montagem `aplicativo` cada linha leva também o que o C2 e o C0 medem: a
// banda dos cenários discretos, os quantis da distribuição de Monte Carlo com
// os sorteios padrão do aplicativo, a liquidez da Porta 0 e, para ativo
// recusado, o potencial sem o corte de liquidez.
//
// Uso:
//   dart run tool/backtest_valuation.dart                        # mercado
//   dart run tool/backtest_valuation.dart --montagem aplicativo
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'b3/proventos.dart';
import 'curva_ligar.dart' show lerTesouro;
import 'cvm/documentos.dart';
import 'cvm/outorgas_por_data.dart';
import 'validation/context.dart';

/// CVM mesclada à série de mercado já reescalada, com o que era público na
/// data da coorte.
class _CvmNaData implements FundamentalsRepository {
  _CvmNaData(this.inner, this.hist, this.docs, this.data);
  final FundamentalsRepository inner;
  final List<FundamentalsSnapshot> hist;
  final List<CvmPeriodDocument>? docs;
  final DateTime data;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final meus = docs;
    if (meus == null || meus.isEmpty) return Ok(hist);
    return Ok(CvmSeries.build(
      documentos: meus,
      mercado: hist,
      asOf: data,
      publicado: PointInTimeView(data).isPublished,
      ancorada: false,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();
}

/// Sorteios da distribuição, iguais ao padrão do aplicativo.
const _sorteios = 10000;

/// Índice buscado uma vez e reaproveitado.
///
/// `BenchmarkRepositoryImpl` vai à rede a cada chamada, e o backtest a faria
/// milhares de vezes.
class _MemoBenchmark implements BenchmarkRepository {
  _MemoBenchmark(this.inner);
  final BenchmarkRepository inner;
  PriceSeries? _full;

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    if (_full == null) {
      final r = await inner.ibovespa(
        DateRange(DateTime(2000, 1, 1), DateTime(2100, 1, 1)),
      );
      if (r.isErr) return r;
      _full = r.unwrap();
    }
    return Ok(PriceSeries(
      ticker: _full!.ticker,
      points: _full!.points.where((p) => range.contains(p.date)).toList(),
    ));
  }
}

/// Fundamentos buscados uma vez por ativo e reaproveitados entre coortes.
class _MemoFundamentals implements FundamentalsRepository {
  _MemoFundamentals(this.inner);
  final FundamentalsRepository inner;
  final _hist = <String, Result<List<FundamentalsSnapshot>>>{};
  final _prof = <String, Result<Asset>>{};
  Result<List<Ticker>>? _uni;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async =>
      _hist[t.value] ??= await inner.history(t);

  @override
  Future<Result<Asset>> profile(Ticker t) async =>
      _prof[t.value] ??= await inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() async => _uni ??= await inner.universe();
}

/// Preços buscados uma vez por ativo, na janela inteira, e recortados em
/// memória para cada coorte.
class _MemoPrices implements PriceRepository {
  _MemoPrices(this.inner);
  final PriceRepository inner;
  final _all = <String, PriceSeries?>{};

  Future<PriceSeries?> _load(Ticker t) async {
    if (_all.containsKey(t.value)) return _all[t.value];
    final r = await inner.daily(
      t,
      DateRange(DateTime(2010, 1, 1), DateTime(2026, 9, 4)),
    );
    return _all[t.value] = r.isOk ? r.unwrap() : null;
  }

  @override
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range) async {
    final s = await _load(t);
    if (s == null) {
      return Err(InsufficientData('sem preços de ${t.value}', subject: t.value));
    }
    return Ok(PriceSeries(
      ticker: s.ticker,
      points: s.points.where((p) => range.contains(p.date)).toList(),
    ));
  }

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  ) async {
    final out = <Ticker, PriceSeries>{};
    for (final t in tickers) {
      final r = await daily(t, range);
      if (r.isOk) out[t] = r.unwrap();
    }
    return Ok(out);
  }

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker t, DateRange range) =>
      inner.adjustedCloseRaw(t, range);
}

/// Reescreve o valor de mercado de cada exercício para a escala da data da
/// coorte.
///
/// A fonte repete o valor de mercado **de hoje** em todos os exercícios —
/// conferido: ele não varia entre linhas em nenhum dos 363 ativos do cache.
/// Deixá-lo assim daria ao motor, numa avaliação de 2018, a capitalização de
/// 2026: conhecimento futuro no divisor da ponte e no peso do WACC.
///
/// A reconstrução usa a contagem do exercício, que é *point-in-time* por
/// construção, vezes o preço da data da coorte.
List<FundamentalsSnapshot> _reescala(
  List<FundamentalsSnapshot> snaps,
  double precoNaData,
) {
  return [
    for (final s in snaps)
      FundamentalsSnapshot(
        ticker: s.ticker,
        fiscalPeriodEnd: s.fiscalPeriodEnd,
        totalRevenue: s.totalRevenue,
        ebit: s.ebit,
        ebitda: s.ebitda,
        netIncome: s.netIncome,
        incomeBeforeTax: s.incomeBeforeTax,
        incomeTaxExpense: s.incomeTaxExpense,
        interestExpense: s.interestExpense,
        earningsPerShare: s.earningsPerShare,
        nopat: s.nopat,
        cash: s.cash,
        shortTermInvestments: s.shortTermInvestments,
        shortTermDebt: s.shortTermDebt,
        longTermDebt: s.longTermDebt,
        totalStockholderEquity: s.totalStockholderEquity,
        bookValuePerShare: s.bookValuePerShare,
        propertyPlantEquipment: s.propertyPlantEquipment,
        intangibleAssets: s.intangibleAssets,
        totalCurrentAssets: s.totalCurrentAssets,
        currentLiabilities: s.currentLiabilities,
        realizedShareCapital: s.realizedShareCapital,
        profitReserves: s.profitReserves,
        operatingCashFlow: s.operatingCashFlow,
        investmentCashFlow: s.investmentCashFlow,
        freeCashFlow: s.freeCashFlow,
        // A contagem corrente sai: ela é de hoje, e na coorte não existia.
        sharesOutstanding: s.sharesOutstandingAsOf,
        sharesOutstandingAsOf: s.sharesOutstandingAsOf,
        marketCap: (s.sharesOutstandingAsOf != null &&
                s.sharesOutstandingAsOf! > 0 &&
                precoNaData > 0)
            ? s.sharesOutstandingAsOf! * precoNaData
            : null,
        enterpriseToEbitda: null,
      ),
  ];
}

double? _precoEm(PriceSeries s, DateTime data) {
  double? ultimo;
  for (final p in s.points) {
    if (p.date.isAfter(data)) break;
    ultimo = p.close;
  }
  return ultimo;
}

double? _ajustadoEm(PriceSeries s, DateTime data) {
  double? ultimo;
  for (final p in s.points) {
    if (p.date.isAfter(data)) break;
    ultimo = p.adjustedClose ?? p.close;
  }
  return ultimo;
}

Future<void> main(List<String> args) async {
  final iMontagem = args.indexOf('--montagem');
  final app = iMontagem >= 0 && args[iMontagem + 1] == 'aplicativo';
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final prices = _MemoPrices(ctx.prices);
  final fundamentals = _MemoFundamentals(ctx.fundamentals);
  final benchmark = _MemoBenchmark(ctx.benchmark);

  // Peças da montagem do aplicativo, lidas uma vez.
  final tesouro =
      app ? lerTesouro('data/tesouro/precotaxatesourodireto.csv') : null;
  final docsCvm = app ? carregarDocumentos('data/cvm_exercicios.json') : null;
  final registro = app
      ? B3RegistryCodec.decodePackage(
          jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
              as Map<String, dynamic>)
      : null;
  final pacoteDeProventos = app
      ? CashDividendsCodec.decode(
          jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
              as Map<String, dynamic>)
      : null;
  final outorgas = app ? OutorgasPorData.ler() : null;
  if (app && outorgas == null) {
    stderr.writeln('sem data/cvm/fre: rode python tool/cvm_baixar.py --docs FRE');
    exit(2);
  }
  if (app) {
    // O prazo lido na data de montagem do pacote tem de ser o do pacote.
    final pacote = ConcessionTermsCodec.decode(
        jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
            as Map<String, dynamic>);
    var iguais = 0;
    for (final e in pacote.entries) {
      final lido = outorgas!.naData(e.key, DateTime(2026, 9, 14));
      if (lido != null && lido.end == e.value.end) iguais++;
    }
    stderr.writeln('outorgas por data contra o pacote: $iguais de '
        '${pacote.length} iguais em 14/09/2026');
  }
  B3Classification? classe(Ticker t) => registro?[
          t.value.length >= 4 ? t.value.substring(0, 4) : '']
      ?.classification;

  // Coortes anuais. A primeira é 2018 porque a Porta 0 exige oito exercícios
  // publicados, e o oitavo (2017) só é público a partir de 2018.
  final coortes = [
    for (var ano = 2018; ano <= 2025; ano++) DateTime(ano, 9, 30),
  ];
  const fim = 2026;

  try {
    final universe = (await fundamentals.universe()).unwrap();
    stderr.writeln('universo: ${universe.length} ativos, '
        '${coortes.length} coortes');
    // Proventos da B3 e fechamento bruto do COTAHIST: o retorno total (A4).
    final proventos = lerProventos();
    final bruto = lerCotahistBruto({for (final t in universe) t.value});

    final linhas = <Map<String, dynamic>>[];
    for (final t in coortes) {
      final anchors = (await ResolveMarketAnchors.call(
        macro: ctx.macro,
        benchmark: benchmark,
        asOf: t,
      ))
          .getOrElse(MarketAnchors.fallback2026);
      final curvaDaCoorte = app ? TreasuryCurve.at(tesouro!, t) : null;
      if (app && curvaDaCoorte == null) {
        stderr.writeln('  ${t.year}: sem curva do Tesouro na data');
      }

      var i = 0, avaliados = 0;
      for (final ticker in universe) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  ${t.year}: $i/${universe.length}   \r');
        }

        final serieRes = await prices.daily(
          ticker,
          DateRange(DateTime(2010, 1, 1), DateTime(fim, 9, 4)),
        );
        if (serieRes.isErr) continue;
        final serie = serieRes.unwrap();
        final p0 = _precoEm(serie, t);
        if (p0 == null || p0 <= 0) continue;

        final histRes = await fundamentals.history(ticker);
        if (histRes.isErr) continue;
        final hist = _reescala(histRes.unwrap(), p0);

        final FundamentalsRepository fonte = app
            ? OfficialSectorFundamentalsRepository(
                inner: _CvmNaData(fundamentals, hist, docsCvm![ticker.value], t),
                classificacao: (x) async => classe(x),
              )
            : _EscaladoFundamentals(fundamentals, hist);
        final prep = await PrepareValuationInputs.call(
          ticker: ticker,
          prices: prices,
          fundamentals: fonte,
          benchmark: benchmark,
          riskFreeRate: anchors.currentRiskFreeRate,
          asOf: t,
          perpetualGrowthCap: anchors.nominalEconomyGrowth,
          inflation: anchors.inflationCagr,
          terminalRiskFreeRate: anchors.riskFreeCagr,
          projectionYears: 10,
          riskFreeCurve: curvaDaCoorte,
          concessionEnd: app ? outorgas!.naData(ticker.value, t)?.end : null,
          dividends: app
              ? CashDividendsCodec.forTicker(pacoteDeProventos!, ticker.value)
              : null,
        );
        if (prep.isErr) continue;
        final insumos = prep.unwrap();

        final r = ValuationCascade.evaluate(insumos);
        final upside = r.isOk ? r.unwrap().upside : null;
        if (upside != null) avaliados++;

        // Banda de Monte Carlo com os sorteios do aplicativo, e o potencial do
        // recusado sem o corte de liquidez — só na montagem do aplicativo.
        List<double>? quantis;
        if (app && r.isOk) {
          final mc = ValuationCascade.evaluate(
            insumos,
            scenarioBuilder: StochasticScenarios.around,
            monteCarloSamples: _sorteios,
          );
          final dist = mc.isOk ? mc.unwrap().distribution : null;
          if (dist != null && !dist.isEmpty) {
            quantis = [for (var q = 0; q <= 100; q++) dist.percentile(q / 100)];
          }
        }
        final cenarios = r.isOk ? r.unwrap().discreteScenarios : null;
        double? semLiquidez;
        if (app && r.isErr) {
          final contra = ValuationCascade.evaluate(_semSerie(insumos));
          if (contra.isOk) semLiquidez = contra.unwrap().upside;
        }
        final serieDaJanela = insumos.prices;
        final liquidez = serieDaJanela == null
            ? null
            : EligibilityGate.medianTradedValue(serieDaJanela);
        // Fração dos últimos pregões da janela de liquidez sem negócio.
        double? semNegocio;
        if (serieDaJanela != null && serieDaJanela.points.length >= 20) {
          final pts = serieDaJanela.points;
          final ini = pts.length > EligibilityGate.liquidityWindowDays
              ? pts.length - EligibilityGate.liquidityWindowDays
              : 0;
          final janela = pts.sublist(ini);
          semNegocio = janela.where((p) => (p.volume ?? 0) <= 0).length /
              janela.length;
        }

        // Fatores ingênuos, sobre o mesmo exercício que o motor usou — na
        // montagem do aplicativo, a série mesclada com a CVM.
        final view = PointInTimeView(t);
        final pub = view.published(insumos.fundamentals);
        final ultimo = pub.isEmpty ? null : pub.last;
        final pl = ultimo?.equityBookValue;
        final vm = ultimo?.marketCap;
        final bm = (pl != null && vm != null && vm > 0) ? pl / vm : null;
        final ey = (ultimo?.netIncome != null && vm != null && vm > 0)
            ? ultimo!.netIncome! / vm
            : null;

        double? retorno(int meses, {bool ajustado = false}) {
          final d = DateTime(t.year + meses ~/ 12, t.month, t.day);
          if (d.isAfter(DateTime(fim, 9, 4))) return null;
          final pa = ajustado ? _ajustadoEm(serie, t) : p0;
          final pf = ajustado ? _ajustadoEm(serie, d) : _precoEm(serie, d);
          if (pa == null || pf == null || pa <= 0) return null;
          return pf / pa - 1;
        }

        // Retorno de preço vezes o reinvestimento dos proventos da classe no
        // fechamento bruto da data ex. Sem COTAHIST do papel, não há total.
        final brutoDoPapel = bruto[ticker.value];
        double? total(int meses) {
          final preco = retorno(meses);
          if (preco == null || brutoDoPapel == null) return null;
          final r = TotalReturn.factor(
            dividends: proventosDo(proventos, ticker.value),
            de: t,
            ate: DateTime(t.year + meses ~/ 12, t.month, t.day),
            closeOnExDate: (d) =>
                pregaoApartir(brutoDoPapel, d, folgaDias: 5)?.close,
          );
          return (1 + preco) * r.factor - 1;
        }

        // O mesmo retorno total **começando um mês depois** da coorte (C0). O
        // sinal escalado pelo preço — B/M, potencial — divide pelo mesmo
        // fechamento em que o retorno começa, e em papel ilíquido esse
        // fechamento é ruído: quem saiu barato por acaso volta, e qualquer sinal
        // que dependa do preço "prevê" a volta. Pular o mês separa a reversão do
        // fechamento do que o sinal sabe.
        double? totalPulandoUmMes(int meses) {
          if (brutoDoPapel == null) return null;
          final de = DateTime(t.year, t.month + 1, t.day);
          final ate = DateTime(t.year + meses ~/ 12, t.month, t.day);
          if (ate.isAfter(DateTime(fim, 9, 4))) return null;
          final pa = _precoEm(serie, de);
          final pf = _precoEm(serie, ate);
          if (pa == null || pf == null || pa <= 0) return null;
          final r = TotalReturn.factor(
            dividends: proventosDo(proventos, ticker.value),
            de: de,
            ate: ate,
            closeOnExDate: (d) =>
                pregaoApartir(brutoDoPapel, d, folgaDias: 5)?.close,
          );
          return pf / pa * r.factor - 1;
        }

        // Roteamento, para separar quem chegou ao acionista por qual porta.
        // A Porta 1 é setorial; a Porta 3 é o fluxo da firma não sustentado.
        final setor = insumos.sectorKey;
        final porta1 = FinancialSectors.isFinancial(
          sectorKey: setor,
          industry: insumos.industry,
        );
        final sustentado = GrowthGuards.firmFlowIsSustained(pub);

        linhas.add({
          'coorte': t.year,
          'ticker': ticker.value,
          'preco': p0,
          'upside': upside,
          'setor': setor,
          'porta1': porta1,
          'fluxoSustentado': sustentado,
          'porta3': !porta1 && !sustentado,
          'ressalvas': r.isOk
              ? [for (final c in r.unwrap().diagnostics!.caveats) c.name]
              : null,
          'pesoTerminal': r.isOk ? r.unwrap().diagnostics!.terminalShare : null,
          'modelo': r.isOk ? r.unwrap().model.name : null,
          'recusa': r.isOk ? null : r.failureOrNull?.message,
          'bookToMarket': bm,
          'earningsYield': ey,
          'ret12': retorno(12),
          'ret36': retorno(36),
          'ret12aj': retorno(12, ajustado: true),
          'ret36aj': retorno(36, ajustado: true),
          'ret12tot': total(12),
          'ret36tot': total(36),
          if (app) ...{
            'justo': r.isOk ? r.unwrap().fairValue.reais : null,
            'pessimista': cenarios == null ? null : cenarios[ScenarioBand.bear]?.reais,
            'otimista': cenarios == null ? null : cenarios[ScenarioBand.bull]?.reais,
            'ke': r.isOk ? r.unwrap().diagnostics!.costOfEquity : null,
            'mcQuantis': quantis,
            'liquidez': liquidez,
            'upsideSemLiquidez': semLiquidez,
            'semNegocio': semNegocio,
            'ret12totPulo': totalPulandoUmMes(12),
            'ret36totPulo': totalPulandoUmMes(36),
            'fimDoContrato':
                insumos.concessionEnd?.toIso8601String().substring(0, 10),
          },
        });
      }
      stderr.writeln('  ${t.year}: $avaliados avaliados de ${universe.length}'
          '   (rf=${(anchors.currentRiskFreeRate * 100).toStringAsFixed(2)}%, '
          'rf_inf=${(anchors.riskFreeCagr * 100).toStringAsFixed(2)}%)');
    }

    final destino = app
        ? 'docs/validacao/backtest_aplicativo.json'
        : 'docs/validacao/backtest_valuation.json';
    File(destino).writeAsStringSync(app
        ? jsonEncode(linhas)
        : const JsonEncoder.withIndent(' ').convert(linhas));
    stderr.writeln('escrito $destino (${linhas.length} observações)');
  } finally {
    await ctx.dispose();
  }
}

/// Os mesmos insumos sem a série de cotações: a Porta 0 omite o corte de
/// liquidez sem ela, e nada mais na cascata lê a série.
ValuationInputs _semSerie(ValuationInputs b) => ValuationInputs(
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
      isDistressed: b.isDistressed,
      unleveredBeta: b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
    );

/// Devolve o histórico já reescalado, mantendo o resto do repositório.
class _EscaladoFundamentals implements FundamentalsRepository {
  _EscaladoFundamentals(this.inner, this.hist);
  final FundamentalsRepository inner;
  final List<FundamentalsSnapshot> hist;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async => Ok(hist);

  @override
  Future<Result<Asset>> profile(Ticker t) => inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();
}
