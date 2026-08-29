import '../value_objects/ticker.dart';

/// Fotografia dos fundamentos de um exercício social.
///
/// A fonte fornece **apenas granularidade anual** (16 exercícios, 2010–2025).
/// Não existe recorte trimestral — limitação a declarar na metodologia.
///
/// Campos derivados relevantes que a fonte não entrega prontos:
/// - D&A       = `cleanEbitda − cleanEbit`
/// - alíquota  = `incomeTaxExpense / incomeBeforeTax`
/// - dív. líq. = `(curto + longo prazo) − (caixa + aplicações)`
class FundamentalsSnapshot {
  /// Ativo a que o exercício pertence.
  final Ticker ticker;

  /// Encerramento do exercício a que os números se referem.
  ///
  /// É a data que [PointInTimeView] compara com o corte de publicação para
  /// decidir se o exercício já era público numa data de análise.
  final DateTime fiscalPeriodEnd;

  // --- Demonstração de resultado ---
  // Todos os campos abaixo são `null` quando a fonte não os informa para o
  // exercício. Valores monetários vêm em reais, na escala publicada pela
  // fonte (unidades, não milhares), e por ação onde o nome indica.
  final double? totalRevenue;
  final double? ebit;
  final double? ebitda;
  final double? netIncome;
  final double? incomeBeforeTax;
  final double? incomeTaxExpense;
  final double? interestExpense;
  final double? earningsPerShare;

  // --- Balanço patrimonial ---
  final double? cash;
  final double? shortTermInvestments;
  final double? shortTermDebt;
  final double? longTermDebt;
  final double? totalStockholderEquity;
  final double? bookValuePerShare;

  // --- Fluxo de caixa ---
  final double? operatingCashFlow;
  final double? investmentCashFlow;
  final double? freeCashFlow;

  // --- Mercado ---
  final double? sharesOutstanding;
  final double? marketCap;
  final double? enterpriseToEbitda;

  const FundamentalsSnapshot({
    required this.ticker,
    required this.fiscalPeriodEnd,
    this.totalRevenue,
    this.ebit,
    this.ebitda,
    this.netIncome,
    this.incomeBeforeTax,
    this.incomeTaxExpense,
    this.interestExpense,
    this.earningsPerShare,
    this.cash,
    this.shortTermInvestments,
    this.shortTermDebt,
    this.longTermDebt,
    this.totalStockholderEquity,
    this.bookValuePerShare,
    this.operatingCashFlow,
    this.investmentCashFlow,
    this.freeCashFlow,
    this.sharesOutstanding,
    this.marketCap,
    this.enterpriseToEbitda,
  });

  /// Depreciação e amortização, derivada de EBITDA − EBIT.
  double? get depreciationAndAmortization {
    if (ebitda == null || ebit == null) return null;
    final da = ebitda! - ebit!;
    return da >= 0 ? da : null;
  }

  /// Alíquota efetiva de imposto, limitada a [0, 0.5] para conter distorções
  /// de exercícios com prejuízo ou créditos fiscais extraordinários.
  double? get effectiveTaxRate {
    if (incomeBeforeTax == null || incomeTaxExpense == null) return null;
    if (incomeBeforeTax! <= 0) return null;
    final rate = incomeTaxExpense!.abs() / incomeBeforeTax!;
    if (rate.isNaN || rate.isInfinite) return null;
    return rate.clamp(0.0, 0.5);
  }

  /// Dívida bruta: curto mais longo prazo.
  ///
  /// **Trata ausência como zero.** Uma parcela não informada pela fonte é
  /// indistinguível aqui de uma parcela realmente nula, e o efeito não é
  /// neutro: dívida subestimada infla o equity no *bridge* do DCF
  /// (`Equity = EV − dívida líquida`). Quem precisa distinguir "sem dívida" de
  /// "sem dado" deve inspecionar [shortTermDebt] e [longTermDebt] diretamente.
  double get totalDebt => (shortTermDebt ?? 0) + (longTermDebt ?? 0);

  /// Caixa e equivalentes: disponibilidades mais aplicações de curto prazo.
  ///
  /// Trata ausência como zero, com a ressalva simétrica à de [totalDebt] — aqui
  /// o viés é conservador, porque caixa subestimado **reduz** o equity.
  double get totalCash => (cash ?? 0) + (shortTermInvestments ?? 0);

  /// Dívida líquida: [totalDebt] menos [totalCash]. Negativa em empresa com
  /// caixa maior que a dívida, e é assim que entra no *bridge* do DCF.
  double get netDebt => totalDebt - totalCash;

  /// Custo da dívida implícito: despesa financeira sobre dívida bruta.
  double? get costOfDebt {
    if (interestExpense == null || totalDebt <= 0) return null;
    final kd = interestExpense!.abs() / totalDebt;
    if (kd.isNaN || kd.isInfinite) return null;
    return kd.clamp(0.0, 1.0);
  }

  /// CapEx aproximado pelo fluxo de investimento.
  ///
  /// Aproximação imperfeita: `investmentCashFlow` inclui M&A e aplicações
  /// financeiras, não só imobilizado. Declarar como limitação.
  double? get approximateCapex => investmentCashFlow?.abs();
}
