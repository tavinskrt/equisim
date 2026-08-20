/// Como o custo de capital foi obtido — rastreabilidade exigida pela
/// reprodutibilidade acadêmica.
enum BetaSource {
  /// Calculado pelo próprio domínio contra o ^BVSP, janela declarada.
  computed,

  /// Informado pela fonte externa (janela e índice não documentados).
  apiProvided,

  /// Arbitrado pelo usuário.
  manual,
}

/// Como o prêmio de risco de mercado foi definido.
enum MarketPremiumSource {
  /// Parametrizado (padrão do sistema: 5–6% a.a.).
  parameterized,

  /// Média histórica do índice na janela declarada.
  historical,
}

/// Insumos do CAPM.
class CapmInputs {
  /// Taxa livre de risco anual, em fração. Deve vir do CDI observado.
  final double riskFreeRate;

  final double beta;
  final BetaSource betaSource;

  /// Prêmio de risco de mercado (Rm − Rf) anual, em fração.
  final double marketPremium;
  final MarketPremiumSource premiumSource;

  const CapmInputs({
    required this.riskFreeRate,
    required this.beta,
    required this.marketPremium,
    this.betaSource = BetaSource.computed,
    this.premiumSource = MarketPremiumSource.parameterized,
  });

  /// Prêmio padrão para o Brasil: 5,5% a.a., ponto médio da faixa de 5–6%
  /// adotada como parâmetro do projeto.
  static const double defaultMarketPremium = 0.055;

  /// Ke = Rf + β · (Rm − Rf)
  double get costOfEquity => riskFreeRate + beta * marketPremium;
}

/// Custo de capital da empresa.
///
/// **Ponto metodológico**: FCFF é fluxo disponível a *todos* os provedores de
/// capital e por isso deve ser descontado ao **WACC**, não ao Ke. Descontar
/// FCFF ao custo de capital próprio superestimaria a taxa e subavaliaria a
/// empresa — erro comum e facilmente cobrável em banca. O Ke sozinho só é
/// consistente com FCFE.
class CostOfCapital {
  final CapmInputs capm;

  /// Custo da dívida antes de impostos, em fração.
  final double costOfDebt;

  /// Alíquota efetiva de imposto, em fração.
  final double taxRate;

  /// Valor de mercado do equity.
  final double equityValue;

  /// Dívida bruta.
  final double debtValue;

  const CostOfCapital({
    required this.capm,
    required this.costOfDebt,
    required this.taxRate,
    required this.equityValue,
    required this.debtValue,
  });

  double get costOfEquity => capm.costOfEquity;

  double get totalCapital => equityValue + debtValue;

  double get equityShare =>
      totalCapital > 0 ? equityValue / totalCapital : 1.0;

  double get debtShare => totalCapital > 0 ? debtValue / totalCapital : 0.0;

  /// WACC = E/(E+D)·Ke + D/(E+D)·Kd·(1 − t)
  double get wacc =>
      equityShare * costOfEquity + debtShare * costOfDebt * (1.0 - taxRate);

  /// Empresa sem dívida: WACC degenera para Ke.
  factory CostOfCapital.unlevered(CapmInputs capm) => CostOfCapital(
        capm: capm,
        costOfDebt: 0.0,
        taxRate: 0.0,
        equityValue: 1.0,
        debtValue: 0.0,
      );
}
