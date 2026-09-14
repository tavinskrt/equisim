/// Últimos doze meses, e a série anual ancorada no trimestre mais recente.
///
/// **O problema que isto resolve.** A §0.2 do plano mediu que o potencial do
/// motor é lento: autocorrelação de posto de +0,666 entre coortes anuais. Entre
/// duas DFPs o preço justo fica congelado e o potencial só se move com o preço.
/// A CVM publica ITR a cada trimestre, com defasagem mediana de **40 dias**
/// contra os 78 da DFP (conferido em 11/09/2026).
///
/// **O que isto não faz, e por quê.** Não põe trimestres na série. O motor
/// presume **um exercício por ano** em quase toda guarda — retorno do capital
/// `lucro_t ÷ base_{t−1}`, crescimento por diferença anual, janela de ciclo,
/// oito exercícios na Porta 0 —, e um ponto a seis meses do anterior entraria
/// como se fosse um ano.
///
/// **O que faz: ancora a série.** Se o documento mais recente publicado é o ITR
/// de 30/06, a série inteira vira doze meses terminados em 30/06 de cada ano —
/// todos a exatamente um ano de distância. Toda guarda anual continua valendo,
/// e o ponto mais recente carrega seis meses de informação que a DFP não tem.
///
/// Ver a decisão 73.
library;

import '../../entities/fundamentals.dart';

/// Tipo de documento entregue à CVM.
enum CvmDocumentKind {
  /// Demonstração anual — o exercício social completo.
  dfp,

  /// Informação trimestral — acumulado do exercício até o trimestre.
  itr,
}

/// Um documento com o período das suas contas de fluxo.
///
/// O snapshot sozinho não basta para somar períodos: ele não diz onde o
/// acumulado começa, e um exercício social de abril a março soma de outro
/// jeito que um de janeiro a dezembro.
class CvmPeriodDocument {
  /// DFP ou ITR.
  final CvmDocumentKind kind;

  /// Primeiro dia do período acumulado dos fluxos.
  final DateTime periodStart;

  /// Data de referência — último dia do período e data do balanço.
  final DateTime periodEnd;

  /// Fluxos **acumulados** do período, e balanço em [periodEnd].
  final FundamentalsSnapshot current;

  /// Fluxos do **mesmo período no exercício anterior**, que o ITR traz como
  /// comparativo. `null` na DFP, que não precisa dele.
  final FundamentalsSnapshot? prior;

  /// Primeiro dia do período de [prior].
  final DateTime? priorStart;

  /// Declara o documento.
  const CvmPeriodDocument({
    required this.kind,
    required this.periodStart,
    required this.periodEnd,
    required this.current,
    this.prior,
    this.priorStart,
  });
}

/// Montagem dos últimos doze meses.
abstract final class TrailingTwelveMonths {
  /// Folga, em dias, para casar datas de período entre documentos.
  ///
  /// Fim de semana e encerramento em dia útil deslocam a data de referência
  /// por poucos dias; mais que isso é período diferente, e a soma recusa.
  static const int toleranciaDias = 4;

  /// Doze meses terminados em `itr.periodEnd`: `anual + acumulado − anterior`.
  ///
  /// - [anual]: a DFP do exercício que terminou **imediatamente antes** do
  ///   acumulado começar.
  /// - [itr]: o documento trimestral, com o comparativo do ano anterior.
  ///
  /// **Recusa, com `null`, em vez de somar períodos que não fecham.** Três
  /// conferências: o acumulado começa no dia seguinte ao fim do exercício
  /// anual; o comparativo começa onde o exercício anual começou; e os dois
  /// acumulados têm o mesmo comprimento. Qualquer uma falhando, a soma
  /// produziria um número de outro intervalo — e sem aviso.
  ///
  /// **Campo de fluxo ausente em qualquer das três parcelas fica ausente.**
  /// Somar dois termos e tratar o terceiro como zero seria a leitura que a
  /// decisão 52 proíbe.
  ///
  /// A aritmética é em `double` e é **exata** aqui: os valores da CVM são
  /// inteiros em milhares de reais, e a soma de três inteiros abaixo de 2⁵³
  /// não arredonda.
  static FundamentalsSnapshot? build({
    required CvmPeriodDocument anual,
    required CvmPeriodDocument itr,
  }) {
    if (anual.kind != CvmDocumentKind.dfp) return null;
    if (itr.kind != CvmDocumentKind.itr) return null;
    final prior = itr.prior;
    final priorStart = itr.priorStart;
    if (prior == null || priorStart == null) return null;

    // 1. O acumulado começa no dia seguinte ao fim do exercício anual.
    if (!_perto(itr.periodStart, anual.periodEnd.add(const Duration(days: 1)))) {
      return null;
    }
    // 2. O comparativo começa onde o exercício anual começou.
    if (!_perto(priorStart, anual.periodStart)) return null;
    // 3. Os dois acumulados têm o mesmo comprimento.
    final lenAtual = itr.periodEnd.difference(itr.periodStart).inDays;
    final fimAnterior = DateTime.utc(
      itr.periodEnd.year - 1,
      itr.periodEnd.month,
      itr.periodEnd.day,
    );
    final lenAnterior = fimAnterior
        .difference(DateTime.utc(
            priorStart.year, priorStart.month, priorStart.day))
        .inDays;
    if ((lenAtual - lenAnterior).abs() > toleranciaDias) return null;

    final a = anual.current;
    final y = itr.current;
    final p = prior;

    double? soma(double? fa, double? fy, double? fp) {
      if (fa == null || fy == null || fp == null) return null;
      final v = fa + fy - fp;
      return v.isFinite ? v : null;
    }

    final ebitTtm = soma(a.ebit, y.ebit, p.ebit);
    final daTtm = soma(
      a.depreciationAndAmortization,
      y.depreciationAndAmortization,
      p.depreciationAndAmortization,
    );

    return FundamentalsSnapshot(
      ticker: y.ticker,
      fiscalPeriodEnd: itr.periodEnd,
      receiptDate: y.receiptDate,
      // --- fluxo: doze meses ---
      totalRevenue: soma(a.totalRevenue, y.totalRevenue, p.totalRevenue),
      ebit: ebitTtm,
      ebitda: (ebitTtm != null && daTtm != null) ? ebitTtm + daTtm : null,
      netIncome: soma(a.netIncome, y.netIncome, p.netIncome),
      incomeBeforeTax:
          soma(a.incomeBeforeTax, y.incomeBeforeTax, p.incomeBeforeTax),
      incomeTaxExpense:
          soma(a.incomeTaxExpense, y.incomeTaxExpense, p.incomeTaxExpense),
      interestExpense:
          soma(a.interestExpense, y.interestExpense, p.interestExpense),
      nopat: soma(a.nopat, y.nopat, p.nopat),
      operatingCashFlow:
          soma(a.operatingCashFlow, y.operatingCashFlow, p.operatingCashFlow),
      investmentCashFlow: soma(
          a.investmentCashFlow, y.investmentCashFlow, p.investmentCashFlow),
      freeCashFlow: soma(a.freeCashFlow, y.freeCashFlow, p.freeCashFlow),
      equityIncomeResult: soma(
          a.equityIncomeResult, y.equityIncomeResult, p.equityIncomeResult),
      // LPA não se soma: é por ação, e a contagem muda entre os períodos.
      earningsPerShare: null,
      // --- estoque: na data do trimestre ---
      cash: y.cash,
      shortTermInvestments: y.shortTermInvestments,
      shortTermDebt: y.shortTermDebt,
      longTermDebt: y.longTermDebt,
      totalStockholderEquity: y.totalStockholderEquity,
      propertyPlantEquipment: y.propertyPlantEquipment,
      intangibleAssets: y.intangibleAssets,
      totalCurrentAssets: y.totalCurrentAssets,
      currentLiabilities: y.currentLiabilities,
      realizedShareCapital: y.realizedShareCapital,
      profitReserves: y.profitReserves,
      minorityInterest: y.minorityInterest,
      totalAssets: y.totalAssets,
      treasuryShares: y.treasuryShares,
      treasuryFraction: y.treasuryFraction,
    );
  }

  /// A série anual ancorada no documento mais recente publicado em [asOf].
  ///
  /// - [documentos]: DFPs e ITRs da companhia, em qualquer ordem.
  /// - [asOf]: data da avaliação.
  /// - [publicado]: se o documento já era público em [asOf]. Recebido pela
  ///   própria cascata, para que a regra de publicidade seja uma só.
  ///
  /// **Ancorada em DFP, devolve as DFPs** — é a série que o motor já usava.
  /// **Ancorada em ITR**, devolve os doze meses terminados na mesma data de
  /// cada ano, para todo ano em que o ITR daquele trimestre e a DFP anterior
  /// a ele existam e sejam públicos.
  ///
  /// O ponto que não fecha a soma é **omitido**, e não substituído pela DFP:
  /// misturar âncoras na mesma série é exatamente o que ela existe para evitar.
  ///
  /// **E a série com buraco não é devolvida** (decisão 73). Se entre dois
  /// pontos ancorados sobra mais de um ano, a série inteira recua para a âncora
  /// de DFP. A razão está medida: em 14/09/2026 a CVM **não publica o ITR de
  /// 2025** — o diretório pula de 2024 para 2026 —, e a primeira versão montou
  /// séries com junho/24 seguido de junho/26. As guardas anuais leram os dois
  /// anos como um: a QUAL3 foi de −22% a +908% de potencial, e a mediana do
  /// movimento no universo foi de 25,3%. Uma série anual com um ano faltando
  /// não é anual, e nenhum número que saia dela descreve a companhia.
  static List<FundamentalsSnapshot> serieAncorada(
    List<CvmPeriodDocument> documentos, {
    required DateTime asOf,
    required bool Function(FundamentalsSnapshot) publicado,
  }) {
    final visiveis = [
      for (final d in documentos)
        if (publicado(d.current)) d,
    ]..sort((x, y) => x.periodEnd.compareTo(y.periodEnd));
    if (visiveis.isEmpty) return const [];

    final ancora = visiveis.last;
    final dfps = [
      for (final d in visiveis)
        if (d.kind == CvmDocumentKind.dfp) d,
    ];
    if (ancora.kind == CvmDocumentKind.dfp) {
      return [for (final d in dfps) d.current];
    }

    final out = <FundamentalsSnapshot>[];
    for (final itr in visiveis) {
      if (itr.kind != CvmDocumentKind.itr) continue;
      if (itr.periodEnd.month != ancora.periodEnd.month) continue;
      if ((itr.periodEnd.day - ancora.periodEnd.day).abs() > toleranciaDias) {
        continue;
      }
      CvmPeriodDocument? anual;
      for (final dfp in dfps) {
        if (_perto(
          itr.periodStart,
          dfp.periodEnd.add(const Duration(days: 1)),
        )) {
          anual = dfp;
        }
      }
      if (anual == null) continue;
      final ttm = build(anual: anual, itr: itr);
      if (ttm != null) out.add(ttm);
    }

    // A âncora tem de ser o último ponto: sem ele a série ancorada não
    // descreve o documento que a escolheu.
    if (out.isEmpty ||
        out.last.fiscalPeriodEnd.year != ancora.periodEnd.year) {
      return [for (final d in dfps) d.current];
    }
    for (var i = 1; i < out.length; i++) {
      final salto =
          out[i].fiscalPeriodEnd.year - out[i - 1].fiscalPeriodEnd.year;
      if (salto != 1) return [for (final d in dfps) d.current];
    }
    return out;
  }

  /// `true` quando [serie] é ancorada em trimestre — ao menos um ponto não
  /// termina onde uma DFP terminaria.
  ///
  /// Serve para quem monta a série saber se a âncora de ITR vingou ou se
  /// houve recuo para a DFP.
  static bool isAnchoredOnQuarter(
    List<FundamentalsSnapshot> serie,
    List<CvmPeriodDocument> documentos,
  ) {
    if (serie.isEmpty) return false;
    final fimDfp = {
      for (final d in documentos)
        if (d.kind == CvmDocumentKind.dfp)
          DateTime.utc(d.periodEnd.year, d.periodEnd.month, d.periodEnd.day),
    };
    final ultimo = serie.last.fiscalPeriodEnd;
    return !fimDfp.contains(DateTime.utc(ultimo.year, ultimo.month, ultimo.day));
  }

  /// Duas datas no mesmo dia civil, dentro de [toleranciaDias].
  static bool _perto(DateTime a, DateTime b) {
    final da = DateTime.utc(a.year, a.month, a.day);
    final db = DateTime.utc(b.year, b.month, b.day);
    return da.difference(db).inDays.abs() <= toleranciaDias;
  }
}
