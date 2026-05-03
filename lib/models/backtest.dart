/// Define os métodos de valuation disponíveis
enum ValuationMethod {
  graham('Graham'),
  bazin('Bazin'),
  peterLynch('Peter Lynch'),
  dcf('DCF Simplificado');

  final String label;
  const ValuationMethod(this.label);
}

/// Configuração inicial do backtest
class BacktestConfig {
  final String stockTicker;
  final String fiiTicker;
  final DateTime startDate;
  final DateTime endDate;
  final double monthlyInvestment;
  final ValuationMethod valuationMethod;
  final double safetyMargin; // percentual (ex: 20.0 para 20%)
  final double desiredRate; // para método Bazin (default 6%)

  BacktestConfig({
    required this.stockTicker,
    required this.fiiTicker,
    required this.startDate,
    required this.endDate,
    required this.monthlyInvestment,
    required this.valuationMethod,
    required this.safetyMargin,
    this.desiredRate = 6.0,
  });

  @override
  String toString() => '''
  BacktestConfig(
    stock: $stockTicker,
    fii: $fiiTicker,
    period: $startDate - $endDate,
    monthly: R\$ $monthlyInvestment,
    valuation: ${valuationMethod.label},
    safety margin: $safetyMargin%
  )''';
}

/// Posição em portfólio em um determinado momento
class PortfolioPosition {
  final int stockShares;
  final int fiiShares;
  final double cash;
  final DateTime date;
  final double stockPrice;
  final double fiiPrice;

  PortfolioPosition({
    required this.stockShares,
    required this.fiiShares,
    required this.cash,
    required this.date,
    required this.stockPrice,
    required this.fiiPrice,
  });

  /// Calcula o valor total do portfólio
  double getTotalValue() {
    return (stockShares * stockPrice) + (fiiShares * fiiPrice) + cash;
  }

  /// Calcula a composição percentual
  Map<String, double> getComposition() {
    final total = getTotalValue();
    if (total == 0) return {'stocks': 0, 'fiis': 0, 'cash': 0};

    return {
      'stocks': (stockShares * stockPrice) / total * 100,
      'fiis': (fiiShares * fiiPrice) / total * 100,
      'cash': cash / total * 100,
    };
  }

  @override
  String toString() => '''PortfolioPosition(
  date: $date,
  stocks: $stockShares × R\$ $stockPrice = R\$ ${stockShares * stockPrice},
  fiis: $fiiShares × R\$ $fiiPrice = R\$ ${fiiShares * fiiPrice},
  cash: R\$ $cash,
  total: R\$ ${getTotalValue()}
)''';
}

/// Operação executada em um mês específico
class MonthlyOperation {
  final DateTime operationDate;
  final double monthlyInvestment;
  final String? assetBought; // 'STOCK' ou 'FII'
  final int quantityBought;
  final double priceBought;
  final double stockDividends;
  final double fiiDividends;
  final double fairValue;
  final double stockPrice;
  final bool wasValuationMet; // true se preço <= justo com margem

  MonthlyOperation({
    required this.operationDate,
    required this.monthlyInvestment,
    this.assetBought,
    required this.quantityBought,
    required this.priceBought,
    required this.stockDividends,
    required this.fiiDividends,
    required this.fairValue,
    required this.stockPrice,
    required this.wasValuationMet,
  });

  /// Retorna o total investido nesta operação
  double getAmountInvested() => quantityBought * priceBought;

  /// Retorna o total de dividendos recebidos
  double getTotalDividends() => stockDividends + fiiDividends;

  @override
  String toString() => '''MonthlyOperation(
  date: $operationDate,
  investment: R\$ $monthlyInvestment,
  bought: $assetBought ($quantityBought @ R\$ $priceBought),
  fair value: R\$ $fairValue,
  current price: R\$ $stockPrice,
  dividends: R\$ ${getTotalDividends()}
)''';
}

/// Resultado de um cenário específico
class BacktestScenarioResult {
  final String scenarioName;
  final double finalValue;
  final int finalStockShares;
  final int finalFiiShares;
  final double finalCash;
  final double totalDividends;
  final double totalInvested;
  final double cagr;
  final double totalReturn; // em percentual
  final List<MonthlyOperation> operations;
  final List<PortfolioPosition> monthlyPositions;

  BacktestScenarioResult({
    required this.scenarioName,
    required this.finalValue,
    required this.finalStockShares,
    required this.finalFiiShares,
    required this.finalCash,
    required this.totalDividends,
    required this.totalInvested,
    required this.cagr,
    required this.totalReturn,
    required this.operations,
    required this.monthlyPositions,
  });

  /// Calcula o ganho absoluto em reais
  double getAbsoluteGain() => finalValue - totalInvested;

  @override
  String toString() => '''BacktestScenarioResult(
  scenario: $scenarioName,
  final value: R\$ $finalValue,
  total return: $totalReturn%,
  CAGR: $cagr%,
  dividends: R\$ $totalDividends,
  shares: $finalStockShares + $finalFiiShares
)''';
}

/// Resultado completo do backtest comparando dois cenários
class BacktestResult {
  final BacktestConfig config;
  final BacktestScenarioResult scenario1; // Buy and Hold
  final BacktestScenarioResult scenario2; // Valuation Inteligente
  final DateTime executionDate;

  BacktestResult({
    required this.config,
    required this.scenario1,
    required this.scenario2,
    required this.executionDate,
  });

  /// Retorna qual cenário foi melhor
  BacktestScenarioResult getWinner() {
    return scenario1.finalValue > scenario2.finalValue ? scenario1 : scenario2;
  }

  /// Retorna qual cenário foi pior
  BacktestScenarioResult getLoser() {
    return scenario1.finalValue < scenario2.finalValue ? scenario1 : scenario2;
  }

  /// Calcula a diferença absoluta entre os cenários
  double getAbsoluteDifference() =>
      (scenario1.finalValue - scenario2.finalValue).abs();

  /// Calcula a diferença percentual entre os cenários
  double getPercentageDifference() {
    final loser = getLoser();
    if (loser.finalValue == 0) return 0;
    return ((getWinner().finalValue - loser.finalValue) / loser.finalValue * 100);
  }

  /// Total patrimonial investido (igual para os dois cenários)
  double getTotalInvested() => scenario1.totalInvested;

  /// Retorna estatísticas de risco/retorno
  Map<String, double> getComparisonStats() {
    final winner = getWinner();
    final loser = getLoser();

    return {
      'winnerReturn': winner.totalReturn,
      'loserReturn': loser.totalReturn,
      'returnDifference': winner.totalReturn - loser.totalReturn,
      'cagrDifference': winner.cagr - loser.cagr,
      'absoluteDifference': getAbsoluteDifference(),
      'percentageDifference': getPercentageDifference(),
    };
  }

  @override
  String toString() => '''BacktestResult(
  ${config.toString()}
  
  === SCENARIO 1 (Buy & Hold) ===
  ${scenario1.toString()}
  
  === SCENARIO 2 (Valuation) ===
  ${scenario2.toString()}
  
  === COMPARISON ===
  Winner: ${getWinner().scenarioName}
  Difference: ${getAbsoluteDifference().toStringAsFixed(2)} (${getPercentageDifference().toStringAsFixed(2)}%)
)''';
}

/// Valuation de um ativo em uma data específica
class ValuationSnapshot {
  final DateTime date;
  final double fairValue;
  final ValuationMethod method;
  final Map<String, dynamic> details; // Detalhes do cálculo

  ValuationSnapshot({
    required this.date,
    required this.fairValue,
    required this.method,
    required this.details,
  });

  @override
  String toString() =>
      'ValuationSnapshot(date: $date, fairValue: R\$ $fairValue, method: ${method.label})';
}