/// Mescla de fundamentos entre duas fontes, com **procedência por campo**.
///
/// **Por que a mescla existe, e por que não é substituição.** A CVM publica a
/// demonstração — receita, resultado, balanço, fluxo — com precisão e
/// profundidade que a fonte de preços não tem: lucro de banco, ativo total,
/// data de recebimento, ação em tesouraria. Mas ela **não publica mercado**:
/// preço, valor de mercado e a contagem corrente de papéis não estão lá, e são
/// o que forma o preço com que o valor justo é comparado.
///
/// Nenhuma das duas basta sozinha, e por isso o exercício é montado das duas.
///
/// **Por que a procedência é obrigatória.** Um número mesclado sem origem é
/// pior que um número de fonte única: quando ele diverge do esperado, não há
/// como saber qual fonte revisar. O inventário de limitações vira ficção na
/// primeira divergência entre fontes se não houver como dizer de onde cada
/// campo veio — foi por isso que o D2 do plano acompanha o eixo A em vez de
/// vir depois.
library;

import '../../entities/fundamentals.dart';

/// De onde um campo veio.
enum FieldSource {
  /// Demonstração entregue à CVM — DFP ou ITR.
  cvm,

  /// Fonte de cotações e dados de mercado.
  market,

  /// Calculado a partir de outros campos, e não publicado por ninguém.
  derived,

  /// Nenhuma fonte forneceu.
  missing;
}

/// Origem de cada campo de um exercício mesclado.
///
/// **É mapa e não classe com um campo por atributo**, de propósito: a lista de
/// campos do domínio muda, e uma classe espelhada precisaria mudar junto ou
/// mentiria por omissão.
class FundamentalsProvenance {
  /// Nome do campo → origem.
  final Map<String, FieldSource> byField;

  /// Declara a procedência, congelando o mapa.
  FundamentalsProvenance(Map<String, FieldSource> byField)
      : byField = Map.unmodifiable(byField);

  /// De onde veio [field]. [FieldSource.missing] quando ninguém informou.
  FieldSource of(String field) => byField[field] ?? FieldSource.missing;

  /// Quantos campos vieram de cada fonte.
  Map<FieldSource, int> get count {
    final out = <FieldSource, int>{};
    for (final v in byField.values) {
      out[v] = (out[v] ?? 0) + 1;
    }
    return out;
  }
}

/// Um exercício mesclado, com o que veio de onde.
class MergedFundamentals {
  /// O exercício montado.
  final FundamentalsSnapshot snapshot;

  /// Origem de cada campo dele.
  final FundamentalsProvenance provenance;

  /// Declara o par.
  const MergedFundamentals(this.snapshot, this.provenance);
}

/// Monta o exercício a partir das duas fontes.
abstract final class FundamentalsMerge {
  /// Campos que **só** a fonte de mercado tem, e que a CVM nunca sobrescreve.
  ///
  /// Estão nomeados porque a regra "CVM ganha" precisa de exceção explícita:
  /// valor de mercado e contagem corrente descrevem o **hoje** do papel, não o
  /// exercício, e a CVM não os publica.
  static const Set<String> marketOnly = {
    'marketCap',
    'sharesOutstanding',
    'enterpriseToEbitda',
    // **Contagem do exercício também**, pela decisão 70: o
    // `QT_ACAO_TOTAL_CAP_INTEGR` da CVM não tem escala declarada — 60,9% dos
    // exercícios vêm em unidades e 34,5% em milhares. Importá-lo levou a
    // MILS3 a +14.037% de potencial. A ferramenta de ingestão já deixou de
    // preenchê-lo; a regra fica **aqui** para que outra montagem não o
    // reintroduza, que é a lição do veto de `CvmBridge.withoutBridge`.
    'sharesOutstandingAsOf',
    // O VPA **da CVM** também nunca entra. Desde a decisão 81 o VPA do
    // exercício mesclado é derivado — PL da CVM sobre a contagem do mercado —,
    // e só recua para o do mercado quando a CVM não traz o PL.
    'bookValuePerShare',
    // **LPA também.** A conta `3.99` da CVM vem **exatamente zero em 14.684 de
    // 15.206** exercícios ingeridos (96,6%). Zero não é nulo, e a regra "CVM
    // vence" o preferia ao LPA do mercado — o que desligava em silêncio o
    // árbitro `lucro ÷ LPA` de `reconciledShares`, que recusa LPA nulo.
    'earningsPerShare',
  };

  /// O que o mercado **empresta** a um ponto de outra data (decisão 78).
  ///
  /// - **O que descreve hoje**: valor de mercado, contagem corrente e
  ///   EV/EBITDA, que a fonte sobrescreve em toda linha com o snapshot
  ///   corrente. Não têm janela.
  /// - **O par por ação do último encerramento**: VPA e contagem do exercício.
  ///   São estoque, e não fluxo, e entram **juntos** — é do produto dos dois que
  ///   a cascata reconstitui o patrimônio (`equityBookValue`), e metade do par
  ///   de uma data com metade de outra mistura escalas. Sem eles a cascata não
  ///   tem base de patrimônio e recusa o ativo como insolvente: medido em
  ///   04/09/2024, 106 de 113 avaliados perdidos na série ancorada.
  ///
  /// **O preço disso é declarado:** num ponto de junho, a base de patrimônio é
  /// a do dezembro anterior. A saída certa é a cascata ler o patrimônio da CVM
  /// na data do ponto — item A1.11 do plano.
  ///
  /// **Fluxo nunca é emprestado**, e o LPA é fluxo por ação: com ele, o
  /// árbitro `lucro ÷ LPA` dividiria o lucro de uma janela pelo LPA de outra.
  static const Set<String> borrowable = {
    'marketCap',
    'sharesOutstanding',
    'enterpriseToEbitda',
    'sharesOutstandingAsOf',
    'bookValuePerShare',
  };

  /// Folga, em dias, para dois exercícios serem da mesma janela. Cobre o
  /// fevereiro bissexto — a CAML3 encerra em 28 ou 29 — e fim de mês em dia
  /// não útil.
  static const int windowMarginDays = 4;

  /// `true` quando os dois exercícios terminam na mesma data, dentro da folga.
  static bool sameWindow(DateTime a, DateTime b) {
    final dayA = DateTime.utc(a.year, a.month, a.day);
    final dayB = DateTime.utc(b.year, b.month, b.day);
    return dayA.difference(dayB).inDays.abs() <= windowMarginDays;
  }

  /// Mescla [cvm] sobre [market], preferindo a CVM onde ela tem o campo.
  ///
  /// - [cvm]: exercício montado da demonstração. `null` quando não há
  ///   documento para aquele período.
  /// - [market]: exercício da fonte de cotações. `null` quando ela não cobre.
  ///
  /// **A preferência é por campo, não por exercício.** A CVM pode ter o lucro
  /// e não ter o EBITDA; o mercado pode ter o valor de mercado e não ter o
  /// ativo total. Escolher a fonte inteira descartaria o que a outra sabe.
  ///
  /// **Mas só completa com exercício da mesma janela** (decisão 78). Um ponto
  /// de doze meses até junho completado pelo exercício de dezembro anterior
  /// levaria a despesa de juros de outra janela para o custo da dívida, e o
  /// LPA de outro lucro para o árbitro `lucro ÷ LPA` da contagem. Quando as
  /// datas diferem além de [windowMarginDays], do mercado vêm só os campos
  /// [borrowable]; o resto fica com a CVM, ou ausente.
  ///
  /// Devolve `null` quando as duas faltam.
  static MergedFundamentals? merge({
    FundamentalsSnapshot? cvm,
    FundamentalsSnapshot? market,
  }) {
    if (cvm == null && market == null) return null;
    if (cvm == null) {
      return MergedFundamentals(market!, _allFrom(market, FieldSource.market));
    }
    if (market == null) {
      return MergedFundamentals(cvm, _allFrom(cvm, FieldSource.cvm));
    }

    final origin = <String, FieldSource>{};
    final complete = sameWindow(cvm.fiscalPeriodEnd, market.fiscalPeriodEnd);

    /// Escolhe entre as duas e registra de onde veio.
    double? field(String name, double? fromCvm, double? rawMarketValue) {
      final marketMedians =
          complete || borrowable.contains(name) ? rawMarketValue : null;
      if (marketOnly.contains(name)) {
        if (marketMedians != null) origin[name] = FieldSource.market;
        return marketMedians;
      }
      if (fromCvm != null) {
        origin[name] = FieldSource.cvm;
        return fromCvm;
      }
      if (marketMedians != null) origin[name] = FieldSource.market;
      return marketMedians;
    }

    // **A base de patrimônio é o PL da CVM** (decisão 81). A cascata a
    // reconstitui como `VPA × contagem do exercício`, e a contagem continua
    // sendo a do mercado — a da CVM não tem escala (decisão 70). O VPA é que
    // passa a ser derivado: `PL ÷ contagem`, e o produto devolve o PL da
    // demonstração exatamente. Medido em 14/09/2026, a base de mercado já era
    // o PL consolidado da CVM em 99,4% dos 4.443 exercícios anuais, a 0,5%;
    // o que muda é o resto — a HAPV3 com R$ 373 bi contra R$ 48 bi —, e o
    // ponto de doze meses até junho, que deixa de levar o PL de dezembro.
    final fiscalYearCount = field('sharesOutstandingAsOf',
        cvm.sharesOutstandingAsOf, market.sharesOutstandingAsOf);
    final cvmEquity = cvm.totalStockholderEquity;
    final double? bookValuePerShare;
    if (cvmEquity != null &&
        cvmEquity.isFinite &&
        fiscalYearCount != null &&
        fiscalYearCount > 0) {
      bookValuePerShare = cvmEquity / fiscalYearCount;
      origin['bookValuePerShare'] = FieldSource.derived;
    } else {
      bookValuePerShare = field(
          'bookValuePerShare', cvm.bookValuePerShare, market.bookValuePerShare);
    }

    final assembled = FundamentalsSnapshot(
      ticker: market.ticker,
      fiscalPeriodEnd: cvm.fiscalPeriodEnd,
      totalRevenue: field('totalRevenue', cvm.totalRevenue, market.totalRevenue),
      ebit: field('ebit', cvm.ebit, market.ebit),
      ebitda: field('ebitda', cvm.ebitda, market.ebitda),
      netIncome: field('netIncome', cvm.netIncome, market.netIncome),
      incomeBeforeTax:
          field('incomeBeforeTax', cvm.incomeBeforeTax, market.incomeBeforeTax),
      incomeTaxExpense: field(
          'incomeTaxExpense', cvm.incomeTaxExpense, market.incomeTaxExpense),
      interestExpense:
          field('interestExpense', cvm.interestExpense, market.interestExpense),
      earningsPerShare:
          field('earningsPerShare', cvm.earningsPerShare, market.earningsPerShare),
      nopat: field('nopat', cvm.nopat, market.nopat),
      cash: field('cash', cvm.cash, market.cash),
      shortTermInvestments: field(
          'shortTermInvestments', cvm.shortTermInvestments, market.shortTermInvestments),
      shortTermDebt: field('shortTermDebt', cvm.shortTermDebt, market.shortTermDebt),
      longTermDebt: field('longTermDebt', cvm.longTermDebt, market.longTermDebt),
      totalStockholderEquity: field('totalStockholderEquity',
          cvm.totalStockholderEquity, market.totalStockholderEquity),
      bookValuePerShare: bookValuePerShare,
      propertyPlantEquipment: field('propertyPlantEquipment',
          cvm.propertyPlantEquipment, market.propertyPlantEquipment),
      intangibleAssets:
          field('intangibleAssets', cvm.intangibleAssets, market.intangibleAssets),
      totalCurrentAssets: field(
          'totalCurrentAssets', cvm.totalCurrentAssets, market.totalCurrentAssets),
      currentLiabilities: field(
          'currentLiabilities', cvm.currentLiabilities, market.currentLiabilities),
      realizedShareCapital: field(
          'realizedShareCapital', cvm.realizedShareCapital, market.realizedShareCapital),
      profitReserves:
          field('profitReserves', cvm.profitReserves, market.profitReserves),
      operatingCashFlow:
          field('operatingCashFlow', cvm.operatingCashFlow, market.operatingCashFlow),
      investmentCashFlow: field(
          'investmentCashFlow', cvm.investmentCashFlow, market.investmentCashFlow),
      freeCashFlow: field('freeCashFlow', cvm.freeCashFlow, market.freeCashFlow),
      sharesOutstanding:
          field('sharesOutstanding', cvm.sharesOutstanding, market.sharesOutstanding),
      sharesOutstandingAsOf: fiscalYearCount,
      marketCap: field('marketCap', cvm.marketCap, market.marketCap),
      enterpriseToEbitda: field(
          'enterpriseToEbitda', cvm.enterpriseToEbitda, market.enterpriseToEbitda),
      minorityInterest:
          field('minorityInterest', cvm.minorityInterest, market.minorityInterest),
      equityIncomeResult: field(
          'equityIncomeResult', cvm.equityIncomeResult, market.equityIncomeResult),
      totalAssets: field('totalAssets', cvm.totalAssets, market.totalAssets),
      treasuryShares:
          field('treasuryShares', cvm.treasuryShares, market.treasuryShares),
      treasuryFraction: field(
          'treasuryFraction', cvm.treasuryFraction, market.treasuryFraction),
      // A data de recebimento é da CVM por natureza: é ela que registra o
      // protocolo. Quando falta, a publicidade volta a ser presumida.
      receiptDate: cvm.receiptDate ?? (complete ? market.receiptDate : null),
    );
    if (assembled.receiptDate != null) {
      origin['receiptDate'] =
          cvm.receiptDate != null ? FieldSource.cvm : FieldSource.market;
    }

    return MergedFundamentals(assembled, FundamentalsProvenance(origin));
  }

  /// Procedência de um exercício de fonte única: todo campo preenchido veio
  /// dela.
  static FundamentalsProvenance _allFrom(
    FundamentalsSnapshot s,
    FieldSource source,
  ) {
    final out = <String, FieldSource>{};
    void mark(String name, double? v) {
      if (v != null) out[name] = source;
    }

    mark('totalRevenue', s.totalRevenue);
    mark('ebit', s.ebit);
    mark('ebitda', s.ebitda);
    mark('netIncome', s.netIncome);
    mark('incomeBeforeTax', s.incomeBeforeTax);
    mark('incomeTaxExpense', s.incomeTaxExpense);
    mark('interestExpense', s.interestExpense);
    mark('earningsPerShare', s.earningsPerShare);
    mark('nopat', s.nopat);
    mark('cash', s.cash);
    mark('shortTermInvestments', s.shortTermInvestments);
    mark('shortTermDebt', s.shortTermDebt);
    mark('longTermDebt', s.longTermDebt);
    mark('totalStockholderEquity', s.totalStockholderEquity);
    mark('bookValuePerShare', s.bookValuePerShare);
    mark('propertyPlantEquipment', s.propertyPlantEquipment);
    mark('intangibleAssets', s.intangibleAssets);
    mark('totalCurrentAssets', s.totalCurrentAssets);
    mark('currentLiabilities', s.currentLiabilities);
    mark('realizedShareCapital', s.realizedShareCapital);
    mark('profitReserves', s.profitReserves);
    mark('operatingCashFlow', s.operatingCashFlow);
    mark('investmentCashFlow', s.investmentCashFlow);
    mark('freeCashFlow', s.freeCashFlow);
    mark('sharesOutstanding', s.sharesOutstanding);
    mark('sharesOutstandingAsOf', s.sharesOutstandingAsOf);
    mark('marketCap', s.marketCap);
    mark('enterpriseToEbitda', s.enterpriseToEbitda);
    mark('minorityInterest', s.minorityInterest);
    mark('equityIncomeResult', s.equityIncomeResult);
    mark('totalAssets', s.totalAssets);
    mark('treasuryShares', s.treasuryShares);
    mark('treasuryFraction', s.treasuryFraction);
    if (s.receiptDate != null) out['receiptDate'] = source;
    return FundamentalsProvenance(out);
  }
}
