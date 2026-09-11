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
// 3. *Provento.* O retorno de referência é de preço, pela decisão 23. O valor
//    que o motor apura inclui a distribuição, então a medição **penaliza** o
//    motor em ativo de *payout* alto. O relatório traz também a leitura por
//    `adjustedClose`, com a ressalva da §0.4 da auditoria.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';
import 'validation/context.dart';

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
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final prices = _MemoPrices(ctx.prices);
  final fundamentals = _MemoFundamentals(ctx.fundamentals);
  final benchmark = _MemoBenchmark(ctx.benchmark);

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

    final linhas = <Map<String, dynamic>>[];
    for (final t in coortes) {
      final anchors = (await ResolveMarketAnchors.call(
        macro: ctx.macro,
        benchmark: benchmark,
        asOf: t,
      ))
          .getOrElse(MarketAnchors.fallback2026);

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

        final prep = await PrepareValuationInputs.call(
          ticker: ticker,
          prices: prices,
          fundamentals: _EscaladoFundamentals(fundamentals, hist),
          benchmark: benchmark,
          riskFreeRate: anchors.currentRiskFreeRate,
          asOf: t,
          perpetualGrowthCap: anchors.nominalEconomyGrowth,
          inflation: anchors.inflationCagr,
          terminalRiskFreeRate: anchors.riskFreeCagr,
          projectionYears: 10,
        );
        if (prep.isErr) continue;

        final r = ValuationCascade.evaluate(prep.unwrap());
        final upside = r.isOk ? r.unwrap().upside : null;
        if (upside != null) avaliados++;

        // Fatores ingênuos, sobre o mesmo exercício que o motor usou.
        final view = PointInTimeView(t);
        final pub = view.published(hist);
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

        // Roteamento, para separar quem chegou ao acionista por qual porta.
        // A Porta 1 é setorial; a Porta 3 é o fluxo da firma não sustentado.
        final perfil = await fundamentals.profile(ticker);
        final setor = perfil.isOk ? perfil.unwrap().sector.key : null;
        final porta1 = setor == 'servicos-financeiros';
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
        });
      }
      stderr.writeln('  ${t.year}: $avaliados avaliados de ${universe.length}'
          '   (rf=${(anchors.currentRiskFreeRate * 100).toStringAsFixed(2)}%, '
          'rf_inf=${(anchors.riskFreeCagr * 100).toStringAsFixed(2)}%)');
    }

    File('docs/validacao/backtest_valuation.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(linhas));
    stderr.writeln('escrito docs/validacao/backtest_valuation.json '
        '(${linhas.length} observações)');
  } finally {
    await ctx.dispose();
  }
}

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
