import 'dart:math';

/// Biblioteca de funções matemáticas e cálculos de engenharia financeira.
class FinancialCalculations {
  // Construtor privado para impedir instanciação da classe utilitária
  FinancialCalculations._();

  /// Calcula a Taxa de Crescimento Anual Composta (CAGR) da carteira.
  static double calculateCAGR(double initialValue, double finalValue, double years) {
    if (initialValue <= 0 || years <= 0) return 0;
    
    try {
      final cagr = (pow(finalValue / initialValue, 1 / years) - 1) * 100;
      return (cagr.isFinite ? cagr : 0).toDouble();
    } catch (e) {
      return 0;
    }
  }

  /// Calcula a rentabilidade histórica percentual total nominal.
  static double calculateTotalReturn(double initialValue, double finalValue) {
    if (initialValue <= 0) return 0;
    return ((finalValue - initialValue) / initialValue) * 100;
  }

  /// Calcula o retorno real ajustado pela taxa de inflação do período.
  static double calculateRealReturn(double nominalReturn, double inflationRate) {
    return ((1 + nominalReturn) / (1 + inflationRate) - 1) * 100;
  }

  /// Calcula a fração exata de anos entre duas datas (considerando anos bissextos).
  static double yearsBetweenDates(DateTime startDate, DateTime endDate) {
    final daysDifference = endDate.difference(startDate).inDays;
    return daysDifference / 365.25;
  }

  /// Calcula a média geométrica de uma série temporal de retornos.
  static double geometricMean(List<double> values) {
    if (values.isEmpty || values.any((v) => v <= 0)) return 0;
    
    final product = values.fold(1.0, (acc, val) => acc * val);
    return pow(product, 1.0 / values.length).toDouble();
  }

  /// Calcula a volatilidade histórica (desvio padrão) de uma lista de retornos.
  static double calculateVolatility(List<double> returns) {
    if (returns.length < 2) return 0;
    
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns.fold(0.0, (sum, value) {
      return sum + pow(value - mean, 2);
    }) / (returns.length - 1);
    
    return sqrt(variance);
  }

  /// Calcula o índice Sharpe (retorno excedente ponderado pelo risco).
  static double calculateSharpeRatio(
    double portfolioReturn,
    double volatility, {
    double riskFreeRate = 0.06,
  }) {
    if (volatility == 0) return 0;
    return (portfolioReturn - riskFreeRate) / volatility;
  }

  /// Calcula o Maximum Drawdown (a maior perda percentual registrada do pico ao vale).
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

  /// Calcula o índice de custo-benefício acumulado.
  static double calculateBenefitCostRatio(double totalDividends, double totalInvested) {
    if (totalInvested == 0) return 0;
    return totalDividends / totalInvested;
  }

  /// Calcula o ponto de equilíbrio de vendas (Breakeven).
  static double calculateBreakeven(
    double fixedCost,
    double unitPrice,
    double unitVariableCost,
  ) {
    if (unitPrice <= unitVariableCost) return 0;
    return fixedCost / (unitPrice - unitVariableCost);
  }

  /// Projeta o valor futuro capitalizado por juros compostos.
  static double calculateFutureValue(
    double presentValue,
    double rate,
    int periods,
  ) {
    return presentValue * pow(1 + rate, periods).toDouble();
  }

  /// Desconta um montante futuro trazendo-o a valor presente.
  static double calculatePresentValue(
    double futureValue,
    double rate,
    int periods,
  ) {
    if (pow(1 + rate, periods) == 0) return 0;
    return futureValue / pow(1 + rate, periods).toDouble();
  }

  /// Calcula a quantidade inteira máxima de cotas compráveis com o caixa disponível.
  static int buyWholeShares(double cash, double price) {
    if (price <= 0) return 0;
    return (cash / price).toInt();
  }

  /// Calcula o saldo de caixa residual após a aquisição de uma quantidade de ativos.
  static double calculateRemainingCash(double cash, double price, int sharesBought) {
    return cash - (sharesBought * price);
  }

  /// Calcula o preço médio ponderado de aquisição de um ativo.
  static double calculateAveragePrice(
    double totalInvested,
    int totalShares,
  ) {
    if (totalShares <= 0) return 0;
    return totalInvested / totalShares;
  }

  /// Calcula o Dividend Yield bruto em base percentual.
  static double calculateDividendYield(double annualDividend, double price) {
    if (price <= 0) return 0;
    return (annualDividend / price) * 100;
  }

  /// Calcula a relação de preço/lucro sobre a taxa de crescimento (Índice PEG).
  static double calculatePEGRatio(double pl, double growthRate) {
    if (growthRate <= 0 || pl <= 0) return 0;
    return pl / growthRate;
  }

  /// Calcula a relação do Preço sobre o Valor Patrimonial por Ação (P/VPA).
  static double calculatePriceToBook(double price, double bvps) {
    if (bvps <= 0) return 0;
    return price / bvps;
  }

  /// Converte uma taxa equivalente de capitalização mensal para anual.
  static double monthlyToAnnualRate(double monthlyRate) {
    return (pow(1 + monthlyRate, 12) - 1) * 100;
  }

  /// Converte uma taxa equivalente de capitalização anual para mensal.
  static double annualToMonthlyRate(double annualRate) {
    return (pow(1 + annualRate, 1 / 12) - 1) * 100;
  }
}
