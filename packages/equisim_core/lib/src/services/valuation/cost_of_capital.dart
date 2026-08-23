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

  /// Custo da dívida antes de impostos **como observado**, em fração.
  ///
  /// Vem de `despesa financeira ÷ dívida bruta`, e a fonte torna essa razão
  /// pouco confiável: a despesa financeira publicada nem sempre é o juro da
  /// dívida, e a dívida bruta nem sempre está completa. Medido em 21/08/2026:
  /// PETR4 saiu com 0,9% a.a. e WEGE3 com 47,3% a.a. — nenhum dos dois é um
  /// custo de dívida. Por isso o valor usado no WACC é [effectiveCostOfDebt],
  /// não este.
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

  /// Prêmio de crédito máximo admitido sobre a taxa livre de risco.
  ///
  /// Dez pontos percentuais acomodam desde a empresa de primeira linha até a
  /// alavancada; acima disso a empresa não estaria se financiando.
  static const double maxCreditSpread = 0.10;

  double get costOfEquity => capm.costOfEquity;

  /// Custo da dívida efetivamente aplicado, dentro da banda de sanidade.
  ///
  /// **Piso na taxa livre de risco**: nenhuma empresa capta mais barato que o
  /// soberano da própria moeda. **Teto em Rf + [maxCreditSpread]**: acima
  /// disso a razão observada está medindo outra coisa que não juro de dívida.
  double get effectiveCostOfDebt => costOfDebt.clamp(
        capm.riskFreeRate,
        capm.riskFreeRate + maxCreditSpread,
      );

  /// `true` quando a banda precisou corrigir o valor observado.
  bool get costOfDebtWasClamped =>
      (effectiveCostOfDebt - costOfDebt).abs() > 1e-9;

  double get totalCapital => equityValue + debtValue;

  double get equityShare =>
      totalCapital > 0 ? equityValue / totalCapital : 1.0;

  double get debtShare => totalCapital > 0 ? debtValue / totalCapital : 0.0;

  /// WACC bruto: `E/(E+D)·Ke + D/(E+D)·Kd·(1 − t)`.
  double get rawWacc =>
      equityShare * costOfEquity +
      debtShare * effectiveCostOfDebt * (1.0 - taxRate);

  /// WACC aplicado ao desconto, nunca abaixo da taxa livre de risco.
  ///
  /// O benefício fiscal da dívida pode, na aritmética, empurrar o WACC abaixo
  /// de Rf numa empresa muito alavancada. Descontar um fluxo de risco a menos
  /// que o soberano não é custo de oportunidade defensável, e o efeito sobre a
  /// perpetuidade é violento: é o que produzia preços justos várias vezes
  /// acima do mercado. O piso mantém o número no terreno econômico, e
  /// [waccWasFloored] existe para que a interface diga que isso aconteceu.
  double get wacc => rawWacc < capm.riskFreeRate ? capm.riskFreeRate : rawWacc;

  bool get waccWasFloored => rawWacc < capm.riskFreeRate;

  /// Empresa sem dívida: WACC degenera para Ke.
  factory CostOfCapital.unlevered(CapmInputs capm) => CostOfCapital(
        capm: capm,
        costOfDebt: 0.0,
        taxRate: 0.0,
        equityValue: 1.0,
        debtValue: 0.0,
      );
}
