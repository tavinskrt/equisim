import 'dart:math';

class FinancialCalculations {
  FinancialCalculations._(); // Construtor privado para evitar instanciação
  /// Calcula a Taxa de Crescimento Anual Composta (CAGR)
  static double calculateCAGR(double initialValue, double finalValue, double years) {
    if (initialValue <= 0 || years <= 0) return 0;
    
    try {
      final cagr = (pow(finalValue / initialValue, 1 / years) - 1) * 100;
      return (cagr.isFinite ? cagr : 0).toDouble();
    } catch (e) {
      return 0;
    }
  }

  /// Calcula o retorno total em percentual
  /// 
  /// Fórmula: Retorno = ((Valor Final - Inicial) / Inicial) * 100
  /// 
  /// Retorna: Retorno em percentual
  static double calculateTotalReturn(double initialValue, double finalValue) {
    if (initialValue <= 0) return 0;
    return ((finalValue - initialValue) / initialValue) * 100;
  }

  /// Calcula o retorno ajustado por inflação (simplificado)
  /// 
  /// Fórmula: Retorno Real = ((1 + Retorno Nominal) / (1 + Inflação)) - 1
  static double calculateRealReturn(double nominalReturn, double inflationRate) {
    return ((1 + nominalReturn) / (1 + inflationRate) - 1) * 100;
  }

  /// Calcula o número de anos decimais entre duas datas
  static double yearsBetweenDates(DateTime startDate, DateTime endDate) {
    final daysDifference = endDate.difference(startDate).inDays;
    return daysDifference / 365.25; // 365.25 leva em conta anos bissextos
  }

  /// Calcula a média geométrica (adequada para retornos)
  /// 
  /// Retorna: Média geométrica dos valores
  static double geometricMean(List<double> values) {
    if (values.isEmpty || values.any((v) => v <= 0)) return 0;
    
    final product = values.fold(1.0, (acc, val) => acc * val);
    return pow(product, 1.0 / values.length).toDouble();
  }

  /// Calcula a volatilidade (desvio padrão) de retornos
  static double calculateVolatility(List<double> returns) {
    if (returns.length < 2) return 0;
    
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns.fold(0.0, (sum, value) {
      return sum + pow(value - mean, 2);
    }) / (returns.length - 1);
    
    return sqrt(variance);
  }

  /// Calcula o Sharpe Ratio
  /// 
  /// Fórmula: Sharpe = (Retorno Carteira - Taxa Livre Risco) / Volatilidade
  /// 
  /// Parâmetros:
  /// - [portfolioReturn]: Retorno do portfólio em decimal (0.12 para 12%)
  /// - [riskFreeRate]: Taxa livre de risco em decimal (default 0.06 para 6%)
  /// - [volatility]: Volatilidade em decimal
  static double calculateSharpeRatio(
    double portfolioReturn,
    double volatility, {
    double riskFreeRate = 0.06,
  }) {
    if (volatility == 0) return 0;
    return (portfolioReturn - riskFreeRate) / volatility;
  }

  /// Calcula o Maximum Drawdown (maior queda do portfólio)
  /// 
  /// Retorna: Drawdown em percentual (ex: -30.5 para queda de 30.5%)
  static double calculateMaxDrawdown(List<double> portfolioValues) {
    if (portfolioValues.isEmpty) return 0;
    
    double maxDrawdown = 0;
    double runningMax = portfolioValues.first;
    
    for (final value in portfolioValues) {
      if (value > runningMax) {
        runningMax = value;
      }
      
      final drawdown = ((value - runningMax) / runningMax) * 100;
      if (drawdown < maxDrawdown) {
        maxDrawdown = drawdown;
      }
    }
    
    return maxDrawdown;
  }

  /// Calcula o Benefit-Cost Ratio (relação ganho/custo)
  /// 
  /// Retorna: Razão ganho/custo
  static double calculateBenefitCostRatio(double totalDividends, double totalInvested) {
    if (totalInvested == 0) return 0;
    return totalDividends / totalInvested;
  }

  /// Calcula o breakeven (ponto de equilíbrio)
  /// 
  /// Parâmetros:
  /// - [fixedCost]: Custo fixo
  /// - [unitPrice]: Preço por unidade
  /// - [unitVariableCost]: Custo variável por unidade
  /// 
  /// Retorna: Quantidade de unidades para breakeven
  static double calculateBreakeven(
    double fixedCost,
    double unitPrice,
    double unitVariableCost,
  ) {
    if (unitPrice <= unitVariableCost) return 0;
    return fixedCost / (unitPrice - unitVariableCost);
  }

  /// Calcula o valor futuro com juros compostos
  /// 
  /// Fórmula: VF = VP × (1 + taxa)^períodos
  static double calculateFutureValue(
    double presentValue,
    double rate,
    int periods,
  ) {
    return presentValue * pow(1 + rate, periods).toDouble();
  }

  /// Calcula o valor presente (desconto)
  /// 
  /// Fórmula: VP = VF / (1 + taxa)^períodos
  static double calculatePresentValue(
    double futureValue,
    double rate,
    int periods,
  ) {
    if (pow(1 + rate, periods) == 0) return 0;
    return futureValue / pow(1 + rate, periods).toDouble();
  }

  /// Arredonda para cima a compra de cotas inteiras
  /// 
  /// Exemplo: com R$ 1.000 e preço R$ 25, retorna 40 cotas (R$ 1.000)
  static int buyWholeShares(double cash, double price) {
    if (price <= 0) return 0;
    return (cash / price).toInt();
  }

  /// Calcula o caixa restante após compra de cotas inteiras
  static double calculateRemainingCash(double cash, double price, int sharesBought) {
    return cash - (sharesBought * price);
  }

  /// Calcula o preço médio de aquisição
  static double calculateAveragePrice(
    double totalInvested,
    int totalShares,
  ) {
    if (totalShares <= 0) return 0;
    return totalInvested / totalShares;
  }

  /// Calcula o dividendo yield (rendimento de dividendos)
  /// 
  /// Fórmula: DY = Dividendo Anual / Preço * 100
  static double calculateDividendYield(double annualDividend, double price) {
    if (price <= 0) return 0;
    return (annualDividend / price) * 100;
  }

  /// Calcula o PEG Ratio (P/L sobre crescimento)
  /// 
  /// Fórmula: PEG = P/L / Crescimento
  static double calculatePEGRatio(double pl, double growthRate) {
    if (growthRate <= 0 || pl <= 0) return 0;
    return pl / growthRate;
  }

  /// Calcula o Price to Book (P/VPA)
  static double calculatePriceToBook(double price, double bvps) {
    if (bvps <= 0) return 0;
    return price / bvps;
  }

  /// Converte taxa mensal para anual
  static double monthlyToAnnualRate(double monthlyRate) {
    return (pow(1 + monthlyRate, 12) - 1) * 100;
  }

  /// Converte taxa anual para mensal
  static double annualToMonthlyRate(double annualRate) {
    return (pow(1 + annualRate, 1 / 12) - 1) * 100;
  }
}
