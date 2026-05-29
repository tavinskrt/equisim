/// Define os métodos de valuation disponíveis na plataforma.
enum ValuationMethod {
  graham('Graham'),
  bazin('Bazin'),
  peterLynch('Peter Lynch'),
  dcf('DCF Simplificado');

  final String label;
  const ValuationMethod(this.label);
}

/// Configurações iniciais fornecidas pelo usuário para a execução do backtest.
class BacktestConfig {
  final String stockTicker;
  final String fiiTicker;
  final DateTime startDate;
  final DateTime endDate;
  final double monthlyInvestment;
  final ValuationMethod valuationMethod;
  final double safetyMargin; // Percentual selecionado (ex: 20.0 para 20%)
  final double desiredRate; // Taxa de retorno desejada para o método Bazin (padrão 6%)
  final int diaCompra;
  final bool considerarReinvestimento;

  BacktestConfig({
    required this.stockTicker,
    required this.fiiTicker,
    required this.startDate,
    required this.endDate,
    required this.monthlyInvestment,
    required this.valuationMethod,
    required this.safetyMargin,
    this.desiredRate = 6.0,
    required this.diaCompra,
    required this.considerarReinvestimento,
  });

  @override
  String toString() => '''
  BacktestConfig(
    stock: $stockTicker,
    fii: $fiiTicker,
    period: $startDate - $endDate,
    monthly: R\$ $monthlyInvestment,
    valuation: ${valuationMethod.label},
    safety margin: $safetyMargin%,
    diaCompra: $diaCompra,
    considerarReinvestimento: $considerarReinvestimento
  )''';
}

/// Posição financeira consolidada do portfólio em um determinado dia útil de simulação.
class PortfolioPosition {
  final double stockShares;
  final double fiiShares;
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

  /// Calcula o valor patrimonial total da carteira.
  double getTotalValue() {
    return (stockShares * stockPrice) + (fiiShares * fiiPrice) + cash;
  }

  /// Calcula o valor total alocado em ativos de risco (ações e fundos imobiliários).
  double getAssetValue() {
    return (stockShares * stockPrice) + (fiiShares * fiiPrice);
  }

  /// Calcula a alocação percentual corrente de cada classe de ativo na carteira.
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

/// Detalhes de uma operação financeira tática/mensal executada no simulador.
class MonthlyOperation {
  final DateTime operationDate;
  final double monthlyInvestment;
  final String? assetBought; // 'STOCK' ou 'FII'
  final double quantityBought;
  final double priceBought;
  final double stockDividends;
  final double fiiDividends;
  final double fairValue;
  final double stockPrice;
  final bool wasValuationMet; // Define se o critério tático de valuation foi atendido
  final String? purchaseReason; // Justificativa da decisão tomada pelo algoritmo
  final double? valuationFormulaValue; // Valor exato de preço teto retornado pelo modelo

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
    this.purchaseReason,
    this.valuationFormulaValue,
  });

  /// Retorna o valor financeiro investido nesta operação específica.
  double getAmountInvested() => quantityBought * priceBought;

  /// Retorna o montante total de proventos arrecadados nesta data.
  double getTotalDividends() => stockDividends + fiiDividends;

  @override
  String toString() => '''MonthlyOperation(
  date: $operationDate,
  investment: R\$ $monthlyInvestment,
  bought: $assetBought ($quantityBought @ R\$ $priceBought),
  fair value: R\$ $fairValue,
  current price: R\$ $stockPrice,
  dividends: R\$ ${getTotalDividends()},
  formula value: $valuationFormulaValue,
  reason: $purchaseReason
)''';
}

/// Resultados consolidados de performance de um cenário específico de simulação.
class BacktestScenarioResult {
  final String scenarioName;
  final double finalValue;
  final double finalStockShares;
  final double finalFiiShares;
  final double finalCash;
  final double totalDividends;
  final double totalInvested;
  final double cagr;
  final double totalReturn; // Rentabilidade total em base percentual
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

  /// Calcula o ganho real de capital em reais (Valor final deduzido dos investimentos aportados).
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

/// Resultado comparativo consolidado abrangendo ambos os cenários de simulação de backtest.
class BacktestResult {
  final BacktestConfig config;
  final BacktestScenarioResult scenario1; // Buy and Hold passivo (Apenas Ações)
  final BacktestScenarioResult scenario2; // Valuation Dinâmico (Ações + FIIs)
  final DateTime executionDate;

  BacktestResult({
    required this.config,
    required this.scenario1,
    required this.scenario2,
    required this.executionDate,
  });

  /// Retorna o cenário de maior retorno patrimonial nominal.
  BacktestScenarioResult getWinner() {
    return scenario1.finalValue > scenario2.finalValue ? scenario1 : scenario2;
  }

  /// Retorna o cenário de menor retorno patrimonial nominal.
  BacktestScenarioResult getLoser() {
    return scenario1.finalValue < scenario2.finalValue ? scenario1 : scenario2;
  }

  /// Retorna a diferença patrimonial nominal absoluta entre os cenários.
  double getAbsoluteDifference() =>
      (scenario1.finalValue - scenario2.finalValue).abs();

  /// Retorna a diferença percentual de ganho em relação ao cenário de menor desempenho.
  double getPercentageDifference() {
    final loser = getLoser();
    if (loser.finalValue == 0) return 0;
    return ((getWinner().finalValue - loser.finalValue) / loser.finalValue * 100);
  }

  /// Retorna o montante consolidado total de capital aportado nas carteiras.
  double getTotalInvested() => scenario1.totalInvested;

  /// Retorna as estatísticas consolidadas e organizadas de análise de performance.
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

/// Registro pontual de valuation calculado para um ativo em determinada data histórica.
class ValuationSnapshot {
  final DateTime date;
  final double fairValue;
  final ValuationMethod method;
  final Map<String, dynamic> details; // Parâmetros matemáticos adicionais de suporte à fórmula

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