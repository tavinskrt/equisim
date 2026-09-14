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
  cvm('CVM'),

  /// Fonte de cotações e dados de mercado.
  mercado('fonte de mercado'),

  /// Calculado a partir de outros campos, e não publicado por ninguém.
  derivado('derivado'),

  /// Nenhuma fonte forneceu.
  ausente('ausente');

  /// Rótulo para relatório e diagnóstico.
  final String label;

  const FieldSource(this.label);
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

  /// Procedência vazia — tudo ausente até que alguém informe.
  static final FundamentalsProvenance vazia = FundamentalsProvenance(const {});

  /// De onde veio [campo]. [FieldSource.ausente] quando ninguém informou.
  FieldSource of(String campo) => byField[campo] ?? FieldSource.ausente;

  /// Quantos campos vieram de cada fonte.
  Map<FieldSource, int> get contagem {
    final out = <FieldSource, int>{};
    for (final v in byField.values) {
      out[v] = (out[v] ?? 0) + 1;
    }
    return out;
  }

  /// Campos que vieram da CVM, em ordem alfabética.
  List<String> get daCvm => [
        for (final e in byField.entries)
          if (e.value == FieldSource.cvm) e.key,
      ]..sort();
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
  static const Set<String> somenteDeMercado = {
    'marketCap',
    'sharesOutstanding',
    'enterpriseToEbitda',
    // **Contagem do exercício também**, pela decisão 70: o
    // `QT_ACAO_TOTAL_CAP_INTEGR` da CVM não tem escala declarada — 60,9% dos
    // exercícios vêm em unidades e 34,5% em milhares. Importá-lo levou a
    // MILS3 a +14.037% de potencial. A ferramenta de ingestão já deixou de
    // preenchê-lo; a regra fica **aqui** para que outra montagem não o
    // reintroduza, que é a lição do veto de `CvmBridge.semPonte`.
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
  static const Set<String> emprestaveis = {
    'marketCap',
    'sharesOutstanding',
    'enterpriseToEbitda',
    'sharesOutstandingAsOf',
    'bookValuePerShare',
  };

  /// Folga, em dias, para dois exercícios serem da mesma janela. Cobre o
  /// fevereiro bissexto — a CAML3 encerra em 28 ou 29 — e fim de mês em dia
  /// não útil.
  static const int folgaDeJanelaDias = 4;

  /// `true` quando os dois exercícios terminam na mesma data, dentro da folga.
  static bool mesmaJanela(DateTime a, DateTime b) {
    final da = DateTime.utc(a.year, a.month, a.day);
    final db = DateTime.utc(b.year, b.month, b.day);
    return da.difference(db).inDays.abs() <= folgaDeJanelaDias;
  }

  /// Mescla [cvm] sobre [mercado], preferindo a CVM onde ela tem o campo.
  ///
  /// - [cvm]: exercício montado da demonstração. `null` quando não há
  ///   documento para aquele período.
  /// - [mercado]: exercício da fonte de cotações. `null` quando ela não cobre.
  ///
  /// **A preferência é por campo, não por exercício.** A CVM pode ter o lucro
  /// e não ter o EBITDA; o mercado pode ter o valor de mercado e não ter o
  /// ativo total. Escolher a fonte inteira descartaria o que a outra sabe.
  ///
  /// **Mas só completa com exercício da mesma janela** (decisão 78). Um ponto
  /// de doze meses até junho completado pelo exercício de dezembro anterior
  /// levaria a despesa de juros de outra janela para o custo da dívida, e o
  /// LPA de outro lucro para o árbitro `lucro ÷ LPA` da contagem. Quando as
  /// datas diferem além de [folgaDeJanelaDias], do mercado vêm só os campos
  /// [emprestaveis]; o resto fica com a CVM, ou ausente.
  ///
  /// Devolve `null` quando as duas faltam.
  static MergedFundamentals? merge({
    FundamentalsSnapshot? cvm,
    FundamentalsSnapshot? mercado,
  }) {
    if (cvm == null && mercado == null) return null;
    if (cvm == null) {
      return MergedFundamentals(mercado!, _todaDe(mercado, FieldSource.mercado));
    }
    if (mercado == null) {
      return MergedFundamentals(cvm, _todaDe(cvm, FieldSource.cvm));
    }

    final origem = <String, FieldSource>{};
    final completa = mesmaJanela(cvm.fiscalPeriodEnd, mercado.fiscalPeriodEnd);

    /// Escolhe entre as duas e registra de onde veio.
    double? campo(String nome, double? daCvm, double? doMercadoBruto) {
      final doMercado =
          completa || emprestaveis.contains(nome) ? doMercadoBruto : null;
      if (somenteDeMercado.contains(nome)) {
        if (doMercado != null) origem[nome] = FieldSource.mercado;
        return doMercado;
      }
      if (daCvm != null) {
        origem[nome] = FieldSource.cvm;
        return daCvm;
      }
      if (doMercado != null) origem[nome] = FieldSource.mercado;
      return doMercado;
    }

    // **A base de patrimônio é o PL da CVM** (decisão 81). A cascata a
    // reconstitui como `VPA × contagem do exercício`, e a contagem continua
    // sendo a do mercado — a da CVM não tem escala (decisão 70). O VPA é que
    // passa a ser derivado: `PL ÷ contagem`, e o produto devolve o PL da
    // demonstração exatamente. Medido em 14/09/2026, a base de mercado já era
    // o PL consolidado da CVM em 99,4% dos 4.443 exercícios anuais, a 0,5%;
    // o que muda é o resto — a HAPV3 com R$ 373 bi contra R$ 48 bi —, e o
    // ponto de doze meses até junho, que deixa de levar o PL de dezembro.
    final contagemDoExercicio = campo('sharesOutstandingAsOf',
        cvm.sharesOutstandingAsOf, mercado.sharesOutstandingAsOf);
    final plDaCvm = cvm.totalStockholderEquity;
    final double? vpa;
    if (plDaCvm != null &&
        plDaCvm.isFinite &&
        contagemDoExercicio != null &&
        contagemDoExercicio > 0) {
      vpa = plDaCvm / contagemDoExercicio;
      origem['bookValuePerShare'] = FieldSource.derivado;
    } else {
      vpa = campo(
          'bookValuePerShare', cvm.bookValuePerShare, mercado.bookValuePerShare);
    }

    final montado = FundamentalsSnapshot(
      ticker: mercado.ticker,
      fiscalPeriodEnd: cvm.fiscalPeriodEnd,
      totalRevenue: campo('totalRevenue', cvm.totalRevenue, mercado.totalRevenue),
      ebit: campo('ebit', cvm.ebit, mercado.ebit),
      ebitda: campo('ebitda', cvm.ebitda, mercado.ebitda),
      netIncome: campo('netIncome', cvm.netIncome, mercado.netIncome),
      incomeBeforeTax:
          campo('incomeBeforeTax', cvm.incomeBeforeTax, mercado.incomeBeforeTax),
      incomeTaxExpense: campo(
          'incomeTaxExpense', cvm.incomeTaxExpense, mercado.incomeTaxExpense),
      interestExpense:
          campo('interestExpense', cvm.interestExpense, mercado.interestExpense),
      earningsPerShare:
          campo('earningsPerShare', cvm.earningsPerShare, mercado.earningsPerShare),
      nopat: campo('nopat', cvm.nopat, mercado.nopat),
      cash: campo('cash', cvm.cash, mercado.cash),
      shortTermInvestments: campo(
          'shortTermInvestments', cvm.shortTermInvestments, mercado.shortTermInvestments),
      shortTermDebt: campo('shortTermDebt', cvm.shortTermDebt, mercado.shortTermDebt),
      longTermDebt: campo('longTermDebt', cvm.longTermDebt, mercado.longTermDebt),
      totalStockholderEquity: campo('totalStockholderEquity',
          cvm.totalStockholderEquity, mercado.totalStockholderEquity),
      bookValuePerShare: vpa,
      propertyPlantEquipment: campo('propertyPlantEquipment',
          cvm.propertyPlantEquipment, mercado.propertyPlantEquipment),
      intangibleAssets:
          campo('intangibleAssets', cvm.intangibleAssets, mercado.intangibleAssets),
      totalCurrentAssets: campo(
          'totalCurrentAssets', cvm.totalCurrentAssets, mercado.totalCurrentAssets),
      currentLiabilities: campo(
          'currentLiabilities', cvm.currentLiabilities, mercado.currentLiabilities),
      realizedShareCapital: campo(
          'realizedShareCapital', cvm.realizedShareCapital, mercado.realizedShareCapital),
      profitReserves:
          campo('profitReserves', cvm.profitReserves, mercado.profitReserves),
      operatingCashFlow:
          campo('operatingCashFlow', cvm.operatingCashFlow, mercado.operatingCashFlow),
      investmentCashFlow: campo(
          'investmentCashFlow', cvm.investmentCashFlow, mercado.investmentCashFlow),
      freeCashFlow: campo('freeCashFlow', cvm.freeCashFlow, mercado.freeCashFlow),
      sharesOutstanding:
          campo('sharesOutstanding', cvm.sharesOutstanding, mercado.sharesOutstanding),
      sharesOutstandingAsOf: contagemDoExercicio,
      marketCap: campo('marketCap', cvm.marketCap, mercado.marketCap),
      enterpriseToEbitda: campo(
          'enterpriseToEbitda', cvm.enterpriseToEbitda, mercado.enterpriseToEbitda),
      minorityInterest:
          campo('minorityInterest', cvm.minorityInterest, mercado.minorityInterest),
      equityIncomeResult: campo(
          'equityIncomeResult', cvm.equityIncomeResult, mercado.equityIncomeResult),
      totalAssets: campo('totalAssets', cvm.totalAssets, mercado.totalAssets),
      treasuryShares:
          campo('treasuryShares', cvm.treasuryShares, mercado.treasuryShares),
      treasuryFraction: campo(
          'treasuryFraction', cvm.treasuryFraction, mercado.treasuryFraction),
      // A data de recebimento é da CVM por natureza: é ela que registra o
      // protocolo. Quando falta, a publicidade volta a ser presumida.
      receiptDate: cvm.receiptDate ?? (completa ? mercado.receiptDate : null),
    );
    if (montado.receiptDate != null) {
      origem['receiptDate'] =
          cvm.receiptDate != null ? FieldSource.cvm : FieldSource.mercado;
    }

    return MergedFundamentals(montado, FundamentalsProvenance(origem));
  }

  /// Procedência de um exercício de fonte única: todo campo preenchido veio
  /// dela.
  static FundamentalsProvenance _todaDe(
    FundamentalsSnapshot s,
    FieldSource fonte,
  ) {
    final out = <String, FieldSource>{};
    void marca(String nome, double? v) {
      if (v != null) out[nome] = fonte;
    }

    marca('totalRevenue', s.totalRevenue);
    marca('ebit', s.ebit);
    marca('ebitda', s.ebitda);
    marca('netIncome', s.netIncome);
    marca('incomeBeforeTax', s.incomeBeforeTax);
    marca('incomeTaxExpense', s.incomeTaxExpense);
    marca('interestExpense', s.interestExpense);
    marca('earningsPerShare', s.earningsPerShare);
    marca('nopat', s.nopat);
    marca('cash', s.cash);
    marca('shortTermInvestments', s.shortTermInvestments);
    marca('shortTermDebt', s.shortTermDebt);
    marca('longTermDebt', s.longTermDebt);
    marca('totalStockholderEquity', s.totalStockholderEquity);
    marca('bookValuePerShare', s.bookValuePerShare);
    marca('propertyPlantEquipment', s.propertyPlantEquipment);
    marca('intangibleAssets', s.intangibleAssets);
    marca('totalCurrentAssets', s.totalCurrentAssets);
    marca('currentLiabilities', s.currentLiabilities);
    marca('realizedShareCapital', s.realizedShareCapital);
    marca('profitReserves', s.profitReserves);
    marca('operatingCashFlow', s.operatingCashFlow);
    marca('investmentCashFlow', s.investmentCashFlow);
    marca('freeCashFlow', s.freeCashFlow);
    marca('sharesOutstanding', s.sharesOutstanding);
    marca('sharesOutstandingAsOf', s.sharesOutstandingAsOf);
    marca('marketCap', s.marketCap);
    marca('enterpriseToEbitda', s.enterpriseToEbitda);
    marca('minorityInterest', s.minorityInterest);
    marca('equityIncomeResult', s.equityIncomeResult);
    marca('totalAssets', s.totalAssets);
    marca('treasuryShares', s.treasuryShares);
    marca('treasuryFraction', s.treasuryFraction);
    if (s.receiptDate != null) out['receiptDate'] = fonte;
    return FundamentalsProvenance(out);
  }
}
