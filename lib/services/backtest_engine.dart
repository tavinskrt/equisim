import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/backtest.dart';
import '../models/stock.dart';
import '../models/fii.dart';
import '../models/dividend.dart';
import '../models/corporate_event.dart';
import 'stock_service.dart';

/// Mecanismo responsável por executar a simulação histórica de backtest.
class BacktestEngine {
  final StockService _stockService = StockService();

  /// Executa o backtest histórico utilizando as configurações fornecidas.
  Future<BacktestResult> runBacktest(BacktestConfig config) async {
    // Calcula a diferença de anos e adiciona uma margem de segurança de 2 anos
    final int yearsDifference = ((config.endDate.difference(config.startDate).inDays) / 365.25).ceil();
    final int limitYears = yearsDifference + 2;

    // Busca dados de mercado concorrentemente para maximizar desempenho de rede
    final Future<List<StockPrice>> stockPricesFuture = _stockService.fetchStocksPrice(config.stockTicker);
    final Future<List<StockPrice>> fiiPricesFuture = _stockService.fetchStocksPrice(config.fiiTicker);
    final Future<StockFundamentals> stockFundamentalsFuture = _stockService.fetchStockFundamentals(config.stockTicker);
    final Future<FiiFundamentals> fiiFundamentalsFuture = _stockService.fetchFiiFundamentals(config.fiiTicker);
    final Future<DividendHistory> stockDividendsFuture = _stockService.fetchDividends(config.stockTicker, limit: limitYears);
    final Future<DividendHistory> fiiDividendsFuture = _stockService.fetchDividends(config.fiiTicker, limit: limitYears);
    final Future<List<CorporateEvent>> stockEventsFuture = _stockService.fetchCorporateEvents(config.stockTicker);
    final Future<List<CorporateEvent>> fiiEventsFuture = _stockService.fetchCorporateEvents(config.fiiTicker);

    final results = await Future.wait([
      stockPricesFuture,
      fiiPricesFuture,
      stockFundamentalsFuture,
      fiiFundamentalsFuture,
      stockDividendsFuture,
      fiiDividendsFuture,
      stockEventsFuture,
      fiiEventsFuture,
    ]);

    final List<StockPrice> stockPrices = results[0] as List<StockPrice>;
    final List<StockPrice> fiiPrices = results[1] as List<StockPrice>;
    final StockFundamentals stockFundamentals = results[2] as StockFundamentals;
    final DividendHistory stockDividends = results[4] as DividendHistory;
    final DividendHistory fiiDividends = results[5] as DividendHistory;
    final List<CorporateEvent> stockEvents = results[6] as List<CorporateEvent>;
    final List<CorporateEvent> fiiEvents = results[7] as List<CorporateEvent>;

    debugPrint('📊 [INÍCIO DO BACKTEST] Período: ${config.startDate} até ${config.endDate}');
    debugPrint('📊 [DADOS CARREGADOS] Preços: Ação=${stockPrices.length}, FII=${fiiPrices.length} | Dividendos: Ação=${stockDividends.dividends.length}, FII=${fiiDividends.dividends.length}');
    
    if (fiiDividends.dividends.isNotEmpty) {
      final dates = fiiDividends.dividends.map((d) => d.paymentDate).toList();
      dates.sort();
      debugPrint('📊 [INTERVALO DE DIVIDENDOS FII] Mais antigo: ${dates.first} | Mais recente: ${dates.last}');
    }

    // Ordena os históricos cronologicamente para consistência
    stockPrices.sort((a, b) => a.date.compareTo(b.date));
    fiiPrices.sort((a, b) => a.date.compareTo(b.date));
    stockEvents.sort((a, b) => a.date.compareTo(b.date));
    fiiEvents.sort((a, b) => a.date.compareTo(b.date));

    // Define os dias úteis com base no histórico de preços da Ação
    final List<StockPrice> filteredStockPrices = stockPrices.where((p) {
      final date = DateTime.tryParse(p.date);
      if (date == null) return false;
      return !date.isBefore(config.startDate) && !date.isAfter(config.endDate);
    }).toList();

    if (filteredStockPrices.isEmpty) {
      throw Exception('Nenhum dado de cotação encontrado para o período selecionado.');
    }

    // Histórico de cotas mensais para processamento de dividendos com base na data ex
    final Map<String, double> c1SharesHistory = {};
    final Map<String, double> c2StockSharesHistory = {};
    final Map<String, double> c2FiiSharesHistory = {};

    // Acumuladores temporários de dividendos entre cada aporte mensal
    double c1AccumulatedStockDiv = 0.0;
    double c2AccumulatedStockDiv = 0.0;
    double c2AccumulatedFiiDiv = 0.0;

    // Estado do Cenário 1: Compras regulares da Ação (Estratégia Buy & Hold clássica)
    double c1StockShares = 0.0;
    double c1Cash = 0.0;
    double c1TotalInvested = 0.0;
    double c1TotalDividends = 0.0;
    final List<MonthlyOperation> c1Operations = [];
    final List<PortfolioPosition> c1Positions = [];

    // Estado do Cenário 2: Alocação tática por Valuation (Ações + FIIs)
    double c2StockShares = 0.0;
    double c2FiiShares = 0.0;
    double c2Cash = 0.0;
    double c2TotalInvested = 0.0;
    double c2TotalDividends = 0.0;
    final List<MonthlyOperation> c2Operations = [];
    final List<PortfolioPosition> c2Positions = [];

    int c1LastPurchaseYear = 0;
    int c1LastPurchaseMonth = 0;

    int c2LastPurchaseYear = 0;
    int c2LastPurchaseMonth = 0;

    // Determina se a margem mínima de segurança foi alcançada alguma vez na simulação
    bool grahamMarginEverMet = false;

    // Filtra proventos não liquidados a partir do início da simulação
    final List<Dividend> unpaidStockDividends = stockDividends.dividends.where((d) {
      final payDate = DateTime.tryParse(d.paymentDate);
      return payDate != null && !payDate.isBefore(config.startDate);
    }).toList();

    final List<Dividend> unpaidFiiDividends = fiiDividends.dividends.where((d) {
      final payDate = DateTime.tryParse(d.paymentDate);
      return payDate != null && !payDate.isBefore(config.startDate);
    }).toList();

    // Projeta proventos futuros caso a API possua gaps nos meses mais recentes
    DateTime? latestFiiDivDate;
    double lastKnownFiiDivValue = 0.0;
    if (fiiDividends.dividends.isNotEmpty) {
      DateTime? maxDate;
      for (final d in fiiDividends.dividends) {
        final date = DateTime.tryParse(d.paymentDate);
        if (date != null && (maxDate == null || date.isAfter(maxDate))) {
          maxDate = date;
          lastKnownFiiDivValue = d.value;
        }
      }
      latestFiiDivDate = maxDate;
    }

    if (latestFiiDivDate != null && latestFiiDivDate.isBefore(config.endDate)) {
      int monthsToAdd = 1;
      while (true) {
        final nextDivDate = DateTime(
          latestFiiDivDate.year,
          latestFiiDivDate.month + monthsToAdd,
          latestFiiDivDate.day,
        );
        if (nextDivDate.isAfter(config.endDate)) {
          break;
        }
        final String formattedDate = "${nextDivDate.year}-${nextDivDate.month.toString().padLeft(2, '0')}-${nextDivDate.day.toString().padLeft(2, '0')}";
        unpaidFiiDividends.add(Dividend(
          exDate: formattedDate,
          paymentDate: formattedDate,
          value: lastKnownFiiDivValue,
          type: 'COM',
        ));
        monthsToAdd++;
      }
    }

    // Projeta proventos passados para cobrir lacunas históricas (lacunas anteriores a 2021)
    DateTime? oldestFiiDivDate;
    double oldestKnownFiiDivValue = 0.0;
    if (fiiDividends.dividends.isNotEmpty) {
      DateTime? minDate;
      for (final d in fiiDividends.dividends) {
        final date = DateTime.tryParse(d.paymentDate);
        if (date != null && (minDate == null || date.isBefore(minDate))) {
          minDate = date;
          oldestKnownFiiDivValue = d.value;
        }
      }
      oldestFiiDivDate = minDate;
    }

    if (oldestFiiDivDate != null && oldestFiiDivDate.isAfter(config.startDate)) {
      int monthsToSub = 1;
      while (true) {
        final prevDivDate = DateTime(
          oldestFiiDivDate.year,
          oldestFiiDivDate.month - monthsToSub,
          oldestFiiDivDate.day,
        );
        if (prevDivDate.isBefore(config.startDate)) {
          break;
        }
        final String formattedDate = "${prevDivDate.year}-${prevDivDate.month.toString().padLeft(2, '0')}-${prevDivDate.day.toString().padLeft(2, '0')}";
        unpaidFiiDividends.add(Dividend(
          exDate: formattedDate,
          paymentDate: formattedDate,
          value: oldestKnownFiiDivValue,
          type: 'COM',
        ));
        monthsToSub++;
      }
    }

    double? prevStockPrice;
    double? prevFiiPrice;

    // Ponteiros cronológicos otimizados para evitar buscas lineares O(N) diárias
    int fiiPointer = 0;

    // Executa a simulação diária histórica
    for (final currentStock in filteredStockPrices) {
      final DateTime currentDate = DateTime.parse(currentStock.date);
      final int year = currentDate.year;
      final int month = currentDate.month;
      final int day = currentDate.day;

      final double stockPrice = currentStock.close;

      // Otimização: Avança o ponteiro cronológico dos FIIs de forma linear O(N+M)
      while (fiiPointer + 1 < fiiPrices.length) {
        final nextDate = DateTime.tryParse(fiiPrices[fiiPointer + 1].date);
        if (nextDate == null || nextDate.isAfter(currentDate)) {
          break;
        }
        fiiPointer++;
      }

      final StockPrice? currentFii = fiiPrices.isNotEmpty ? fiiPrices[fiiPointer] : null;
      if (currentFii == null) continue;
      final double fiiPrice = currentFii.close;

      bool hasStockEventToday = false;
      bool hasFiiEventToday = false;

      // Processa desdobramentos e agrupamentos cadastrados para as Ações
      for (final event in stockEvents) {
        if (event.date.year == year && event.date.month == month && event.date.day == day) {
          final double multiplier = (event.ratioFrom > 0)
              ? (event.ratioTo / event.ratioFrom)
              : (event.factor > 0 ? 1.0 / event.factor : 1.0);

          if (multiplier != 1.0) {
            final double rawC1Shares = c1StockShares * multiplier;
            final double flooredC1Shares = rawC1Shares.floorToDouble();
            final double residueC1 = rawC1Shares - flooredC1Shares;
            c1StockShares = flooredC1Shares;
            c1Cash += residueC1 * stockPrice;

            final double rawC2Shares = c2StockShares * multiplier;
            final double flooredC2Shares = rawC2Shares.floorToDouble();
            final double residueC2 = rawC2Shares - flooredC2Shares;
            c2StockShares = flooredC2Shares;
            c2Cash += residueC2 * stockPrice;

            for (final key in c1SharesHistory.keys) {
              c1SharesHistory[key] = ((c1SharesHistory[key] ?? 0.0) * multiplier).floorToDouble();
            }
            for (final key in c2StockSharesHistory.keys) {
              c2StockSharesHistory[key] = ((c2StockSharesHistory[key] ?? 0.0) * multiplier).floorToDouble();
            }

            hasStockEventToday = true;
          }
        }
      }

      // Processa desdobramentos e agrupamentos cadastrados para os FIIs
      for (final event in fiiEvents) {
        if (event.date.year == year && event.date.month == month && event.date.day == day) {
          final double multiplier = (event.ratioFrom > 0)
              ? (event.ratioTo / event.ratioFrom)
              : (event.factor > 0 ? 1.0 / event.factor : 1.0);

          if (multiplier != 1.0) {
            final double rawC2FiiShares = c2FiiShares * multiplier;
            final double flooredC2FiiShares = rawC2FiiShares.floorToDouble();
            final double residueC2Fii = rawC2FiiShares - flooredC2FiiShares;
            c2FiiShares = flooredC2FiiShares;
            c2Cash += residueC2Fii * fiiPrice;

            for (final key in c2FiiSharesHistory.keys) {
              c2FiiSharesHistory[key] = ((c2FiiSharesHistory[key] ?? 0.0) * multiplier).floorToDouble();
            }

            hasFiiEventToday = true;
          }
        }
      }

      // Mecanismo automático de proteção para splits não listados nas APIs (Ações)
      if (!hasStockEventToday && prevStockPrice != null && prevStockPrice > 0) {
        final double multiplier = _detectSplitMultiplier(prevStockPrice, stockPrice);
        if (multiplier != 1.0) {
          final double rawC1Shares = c1StockShares * multiplier;
          final double flooredC1Shares = rawC1Shares.floorToDouble();
          final double residueC1 = rawC1Shares - flooredC1Shares;
          c1StockShares = flooredC1Shares;
          c1Cash += residueC1 * stockPrice;

          final double rawC2Shares = c2StockShares * multiplier;
          final double flooredC2Shares = rawC2Shares.floorToDouble();
          final double residueC2 = rawC2Shares - flooredC2Shares;
          c2StockShares = flooredC2Shares;
          c2Cash += residueC2 * stockPrice;

          for (final key in c1SharesHistory.keys) {
            c1SharesHistory[key] = ((c1SharesHistory[key] ?? 0.0) * multiplier).floorToDouble();
          }
          for (final key in c2StockSharesHistory.keys) {
            c2StockSharesHistory[key] = ((c2StockSharesHistory[key] ?? 0.0) * multiplier).floorToDouble();
          }
        }
      }

      // Mecanismo automático de proteção para splits não listados nas APIs (FIIs)
      if (!hasFiiEventToday && prevFiiPrice != null && prevFiiPrice > 0) {
        final double multiplier = _detectSplitMultiplier(prevFiiPrice, fiiPrice);
        if (multiplier != 1.0) {
          final double rawC2FiiShares = c2FiiShares * multiplier;
          final double flooredC2FiiShares = rawC2FiiShares.floorToDouble();
          final double residueC2Fii = rawC2FiiShares - flooredC2FiiShares;
          c2FiiShares = flooredC2FiiShares;
          c2Cash += residueC2Fii * fiiPrice;

          for (final key in c2FiiSharesHistory.keys) {
            c2FiiSharesHistory[key] = ((c2FiiSharesHistory[key] ?? 0.0) * multiplier).floorToDouble();
          }
        }
      }

      // Registra a quantidade de ativos que iniciaram este mês para cômputo dos proventos
      final String currentKey = '$year-$month';
      c1SharesHistory[currentKey] = c1StockShares;
      c2StockSharesHistory[currentKey] = c2StockShares;
      c2FiiSharesHistory[currentKey] = c2FiiShares;

      double c1StockDiv = 0.0;
      double c2StockDiv = 0.0;
      double c2FiiDiv = 0.0;

      // Identifica e distribui proventos devidos das Ações no dia corrente
      final List<Dividend> dayStockPayments = [];
      unpaidStockDividends.removeWhere((d) {
        final payDate = DateTime.tryParse(d.paymentDate);
        if (payDate == null) return true;
        if (!payDate.isAfter(currentDate)) {
          dayStockPayments.add(d);
          return true;
        }
        return false;
      });

      for (final d in dayStockPayments) {
        final String exDateStr = d.exDate.isNotEmpty ? d.exDate : d.paymentDate;
        final exDate = DateTime.tryParse(exDateStr);
        if (exDate != null) {
          final String exKey = '${exDate.year}-${exDate.month}';
          final c1Shares = c1SharesHistory[exKey] ?? 0.0;
          final c2Shares = c2StockSharesHistory[exKey] ?? 0.0;
          c1StockDiv += c1Shares * d.value;
          c2StockDiv += c2Shares * d.value;
        }
      }
      c1TotalDividends += c1StockDiv;

      // Identifica e distribui proventos devidos dos FIIs no dia corrente
      final List<Dividend> dayFiiPayments = [];
      unpaidFiiDividends.removeWhere((d) {
        final payDate = DateTime.tryParse(d.paymentDate);
        if (payDate == null) return true;
        if (!payDate.isAfter(currentDate)) {
          dayFiiPayments.add(d);
          return true;
        }
        return false;
      });

      for (final d in dayFiiPayments) {
        final String exDateStr = d.exDate.isNotEmpty ? d.exDate : d.paymentDate;
        final exDate = DateTime.tryParse(exDateStr);
        if (exDate != null) {
          final String exKey = '${exDate.year}-${exDate.month}';
          final c2Shares = c2FiiSharesHistory[exKey] ?? 0.0;
          c2FiiDiv += c2Shares * d.value;
        }
      }
      final double c2MonthDiv = c2StockDiv + c2FiiDiv;
      c2TotalDividends += c2MonthDiv;

      // Adiciona rendimentos recebidos ao saldo de caixa se reinvestimento estiver ativo
      if (config.considerarReinvestimento) {
        c1Cash += c1StockDiv;
        c2Cash += c2MonthDiv;
      }

      c1AccumulatedStockDiv += c1StockDiv;
      c2AccumulatedStockDiv += c2StockDiv;
      c2AccumulatedFiiDiv += c2FiiDiv;

      // Executa o aporte regular para o Cenário 1 (Buy & Hold clássico)
      final bool c1IsNewMonth = year != c1LastPurchaseYear || month != c1LastPurchaseMonth;
      final bool c1IsAfterPurchaseDay = day >= config.diaCompra;
      if (c1IsNewMonth && c1IsAfterPurchaseDay) {
        c1LastPurchaseYear = year;
        c1LastPurchaseMonth = month;
        
        c1Cash += config.monthlyInvestment;
        c1TotalInvested += config.monthlyInvestment;

        final double c1Bought = (c1Cash / stockPrice).floorToDouble();
        if (c1Bought > 0) {
          c1StockShares += c1Bought;
          c1SharesHistory[currentKey] = c1StockShares;
          c1Cash -= c1Bought * stockPrice;
        }

        c1Operations.add(MonthlyOperation(
          operationDate: currentDate,
          monthlyInvestment: config.monthlyInvestment,
          assetBought: c1Bought > 0 ? 'STOCK' : null,
          quantityBought: c1Bought,
          priceBought: c1Bought > 0 ? stockPrice : 0.0,
          stockDividends: c1AccumulatedStockDiv,
          fiiDividends: 0.0,
          fairValue: 0.0,
          stockPrice: stockPrice,
          wasValuationMet: true,
          purchaseReason: c1Bought > 0 
              ? 'Aporte mensal regular: compra passiva da ação ${config.stockTicker} pelo método Buy & Hold.'
              : 'Aporte mensal regular recebido, mas saldo insuficiente para comprar cotas de ${config.stockTicker}.',
          valuationFormulaValue: 0.0,
        ));
        c1AccumulatedStockDiv = 0.0;
      }

      // Executa o aporte tático para o Cenário 2 (Alocação Dinâmica por Valuation)
      final bool c2IsNewMonth = year != c2LastPurchaseYear || month != c2LastPurchaseMonth;
      final bool c2IsAfterPurchaseDay = day >= config.diaCompra;
      if (c2IsNewMonth && c2IsAfterPurchaseDay) {
        c2LastPurchaseYear = year;
        c2LastPurchaseMonth = month;

        c2Cash += config.monthlyInvestment;
        c2TotalInvested += config.monthlyInvestment;

        double fairValue = 0.0;
        bool isStockCheap = false;
        String purchaseReason = '';
        double valuationFormulaValue = 0.0;

        // Executa a estratégia tática selecionada
        if (config.valuationMethod == ValuationMethod.graham) {
          final double currentLpa = stockFundamentals.lpa > 0 ? stockFundamentals.lpa : 1.0;
          final double currentVpa = stockFundamentals.vpa > 0 ? stockFundamentals.vpa : 1.0;
          final double yearsFromEnd = (currentDate.difference(config.endDate).inDays) / 365.25;
          
          final double baselineVpa = currentVpa * pow(1.06, yearsFromEnd);
          final double baselineLpa = currentLpa * pow(1.06, yearsFromEnd);

          final double historicalTtmDiv = _getTtmDividendsDaily(stockDividends.dividends, currentDate);
          final double currentTtmDiv = _getTtmDividendsDaily(stockDividends.dividends, config.endDate);
          double payoutRatio = currentTtmDiv > 0 && currentLpa > 0 ? (currentTtmDiv / currentLpa) : 0.5;
          payoutRatio = payoutRatio.clamp(0.2, 0.85);

          double dynamicLpa = baselineLpa;
          if (historicalTtmDiv > 0) {
            dynamicLpa = historicalTtmDiv / payoutRatio;
          }

          double roe = stockFundamentals.roe > 0 ? stockFundamentals.roe : 12.0;
          roe = roe.clamp(5.0, 35.0);
          double dynamicVpa = dynamicLpa / (roe / 100.0);
          
          dynamicLpa = dynamicLpa.clamp(baselineLpa * 0.4, baselineLpa * 2.5);
          dynamicVpa = dynamicVpa.clamp(baselineVpa * 0.4, baselineVpa * 2.5);

          final double calculatedLpa = max(0.1, dynamicLpa);
          final double calculatedVpa = max(0.1, dynamicVpa);
          
          fairValue = sqrt(max(0.0, 22.5 * calculatedLpa * calculatedVpa));
          final double safePrice = max(0.0, fairValue * (1.0 - (config.safetyMargin / 100.0)));
          isStockCheap = stockPrice <= safePrice;
          if (isStockCheap) {
            grahamMarginEverMet = true;
          }
          valuationFormulaValue = fairValue;
          
          if (isStockCheap) {
            purchaseReason = 'Comprado ${config.stockTicker}: preço atual (R\$ ${stockPrice.toStringAsFixed(2)}) é menor/igual ao Preço Teto de Graham dinâmico com margem de segurança de ${config.safetyMargin.toStringAsFixed(0)}% (R\$ ${safePrice.toStringAsFixed(2)}). Preço Justo: R\$ ${fairValue.toStringAsFixed(2)} (LPA: R\$ ${calculatedLpa.toStringAsFixed(2)}, VPA: R\$ ${calculatedVpa.toStringAsFixed(2)}).';
          } else {
            purchaseReason = 'Comprado ${config.fiiTicker}: preço da ação (R\$ ${stockPrice.toStringAsFixed(2)}) está acima do Preço Teto de Graham dinâmico com margem (R\$ ${safePrice.toStringAsFixed(2)}). Preço Justo: R\$ ${fairValue.toStringAsFixed(2)} (LPA: R\$ ${calculatedLpa.toStringAsFixed(2)}, VPA: R\$ ${calculatedVpa.toStringAsFixed(2)}).';
          }
        } else if (config.valuationMethod == ValuationMethod.bazin) {
          final double ttmDiv = _getTtmDividendsDaily(stockDividends.dividends, currentDate);
          final double finalTtmDiv = max(0.0, ttmDiv > 0 ? ttmDiv : (stockPrice * (stockFundamentals.dyield > 0 ? stockFundamentals.dyield / 100.0 : 0.05)));
          final double desiredRate = max(0.1, config.desiredRate);
          fairValue = finalTtmDiv / (desiredRate / 100.0);
          isStockCheap = stockPrice <= fairValue;
          valuationFormulaValue = fairValue;
          
          if (isStockCheap) {
            purchaseReason = 'Comprado ${config.stockTicker}: preço atual (R\$ ${stockPrice.toStringAsFixed(2)}) é menor/igual ao Preço Teto de Bazin (R\$ ${fairValue.toStringAsFixed(2)}), baseado em dividendos acumulados de R\$ ${finalTtmDiv.toStringAsFixed(2)} e taxa de retorno desejada de ${desiredRate.toStringAsFixed(1)}%.';
          } else {
            purchaseReason = 'Comprado ${config.fiiTicker}: preço da ação (R\$ ${stockPrice.toStringAsFixed(2)}) está acima do Preço Teto de Bazin (R\$ ${fairValue.toStringAsFixed(2)}). Comprado FII como porto seguro.';
          }
        } else if (config.valuationMethod == ValuationMethod.peterLynch) {
          final double ttmDiv = _getTtmDividendsDaily(stockDividends.dividends, currentDate);
          final double dy = stockPrice > 0 ? max(0.0, (ttmDiv / stockPrice) * 100.0) : 0.0;
          final double roe = stockFundamentals.roe > 0 ? stockFundamentals.roe : 12.0;
          final double lpa = stockFundamentals.lpa > 0 ? stockFundamentals.lpa : 1.0;
          final double pe = max(1.0, stockPrice / lpa);
          final double lynchRate = (roe + dy) / pe;
          fairValue = 1.5;
          isStockCheap = lynchRate > 1.5;
          valuationFormulaValue = lynchRate;
          
          if (isStockCheap) {
            purchaseReason = 'Comprado ${config.stockTicker}: indicador de Peter Lynch (${lynchRate.toStringAsFixed(2)}) é superior a 1.5 (empresa subavaliada com boa taxa de ROE de ${roe.toStringAsFixed(1)}% e DY de ${dy.toStringAsFixed(2)}% em relação ao P/L).';
          } else {
            purchaseReason = 'Comprado ${config.fiiTicker}: indicador de Peter Lynch (${lynchRate.toStringAsFixed(2)}) é inferior/igual a 1.5 (ação cara/sobreavaliada). ROE: ${roe.toStringAsFixed(1)}%, DY: ${dy.toStringAsFixed(2)}%. Comprado FII.';
          }
        } else if (config.valuationMethod == ValuationMethod.dcf) {
          // 1. Obter LPA base no ponto do tempo (usando a mesma normalização histórica de Graham)
          final double currentLpa = stockFundamentals.lpa > 0 ? stockFundamentals.lpa : 1.0;
          final double yearsFromEnd = (currentDate.difference(config.endDate).inDays) / 365.25;
          final double baselineLpa = currentLpa * pow(1.06, yearsFromEnd);
          
          final double historicalTtmDiv = _getTtmDividendsDaily(stockDividends.dividends, currentDate);
          final double currentTtmDiv = _getTtmDividendsDaily(stockDividends.dividends, config.endDate);
          double payoutRatio = currentTtmDiv > 0 && currentLpa > 0 ? (currentTtmDiv / currentLpa) : 0.5;
          payoutRatio = payoutRatio.clamp(0.2, 0.85);

          double dynamicLpa = baselineLpa;
          if (historicalTtmDiv > 0) {
            dynamicLpa = historicalTtmDiv / payoutRatio;
          }
          dynamicLpa = dynamicLpa.clamp(baselineLpa * 0.4, baselineLpa * 2.5);
          final double lpa0 = max(0.1, dynamicLpa);

          // 2. Extrair parâmetros informados pelo usuário
          final double r = config.dcfDiscountRate / 100.0;
          final double g = config.dcfGrowthRate / 100.0;
          final double gp = config.dcfPerpetualGrowth / 100.0;
          final int N = config.dcfProjectionYears;

          // 3. Projetar e descontar os fluxos futuros de LPA
          double sumDiscountedLpa = 0.0;
          double lpaT = lpa0;
          for (int t = 1; t <= N; t++) {
            lpaT = lpaT * (1 + g);
            sumDiscountedLpa += lpaT / pow(1 + r, t);
          }

          // 4. Calcular e descontar o Valor Terminal
          // Salvaguarda: Evitar divisão por zero caso r <= gp
          final double denominator = (r - gp) > 0 ? (r - gp) : 0.01;
          final double terminalValue = (lpaT * (1 + gp)) / denominator;
          final double discountedTerminalValue = terminalValue / pow(1 + r, N);

          // 5. Preço Justo e Margem de Segurança
          fairValue = sumDiscountedLpa + discountedTerminalValue;
          final double safePrice = max(0.0, fairValue * (1.0 - (config.safetyMargin / 100.0)));
          isStockCheap = stockPrice <= safePrice;
          valuationFormulaValue = fairValue;

          if (isStockCheap) {
            purchaseReason = 'Comprado ${config.stockTicker}: preço (R\$ ${stockPrice.toStringAsFixed(2)}) é menor/igual ao Preço Justo do DCF com margem de segurança de ${config.safetyMargin.toStringAsFixed(0)}% (R\$ ${safePrice.toStringAsFixed(2)}). Preço Justo: R\$ ${fairValue.toStringAsFixed(2)} (LPA Inicial: R\$ ${lpa0.toStringAsFixed(2)}, Crescimento: ${(g*100).toStringAsFixed(1)}%, Desconto: ${(r*100).toStringAsFixed(1)}%).';
          } else {
            purchaseReason = 'Comprado ${config.fiiTicker}: preço da ação (R\$ ${stockPrice.toStringAsFixed(2)}) está acima do Preço Justo do DCF com margem (R\$ ${safePrice.toStringAsFixed(2)}). Preço Justo: R\$ ${fairValue.toStringAsFixed(2)}. FII comprado como porto seguro.';
          }
        }

        final double targetPrice = isStockCheap ? stockPrice : fiiPrice;
        final double quantityBought = (c2Cash / targetPrice).floorToDouble();

        if (quantityBought > 0) {
          if (isStockCheap) {
            c2StockShares += quantityBought;
            c2StockSharesHistory[currentKey] = c2StockShares;
            c2Cash -= quantityBought * stockPrice;
          } else {
            c2FiiShares += quantityBought;
            c2FiiSharesHistory[currentKey] = c2FiiShares;
            c2Cash -= quantityBought * fiiPrice;
          }
        } else {
          purchaseReason = 'Aporte recebido de R\$ ${config.monthlyInvestment.toStringAsFixed(2)}, mas saldo em caixa insuficiente para comprar cotas de ${isStockCheap ? config.stockTicker : config.fiiTicker}.';
        }

        c2Operations.add(MonthlyOperation(
          operationDate: currentDate,
          monthlyInvestment: config.monthlyInvestment,
          assetBought: quantityBought > 0 ? (isStockCheap ? 'STOCK' : 'FII') : null,
          quantityBought: quantityBought,
          priceBought: quantityBought > 0 ? targetPrice : 0.0,
          stockDividends: c2AccumulatedStockDiv,
          fiiDividends: c2AccumulatedFiiDiv,
          fairValue: fairValue,
          stockPrice: stockPrice,
          wasValuationMet: isStockCheap,
          purchaseReason: purchaseReason,
          valuationFormulaValue: valuationFormulaValue,
        ));
        c2AccumulatedStockDiv = 0.0;
        c2AccumulatedFiiDiv = 0.0;
      }

      // Adiciona as posições diárias da carteira
      c1Positions.add(PortfolioPosition(
        stockShares: c1StockShares,
        fiiShares: 0.0,
        cash: c1Cash,
        date: currentDate,
        stockPrice: stockPrice,
        fiiPrice: fiiPrice,
      ));

      c2Positions.add(PortfolioPosition(
        stockShares: c2StockShares,
        fiiShares: c2FiiShares,
        cash: c2Cash,
        date: currentDate,
        stockPrice: stockPrice,
        fiiPrice: fiiPrice,
      ));

      prevStockPrice = stockPrice;
      prevFiiPrice = fiiPrice;
    }

    // Consolida proventos residuais acumulados no final da simulação
    if (c1Operations.isNotEmpty) {
      final lastOp = c1Operations.last;
      c1Operations[c1Operations.length - 1] = MonthlyOperation(
        operationDate: lastOp.operationDate,
        monthlyInvestment: lastOp.monthlyInvestment,
        assetBought: lastOp.assetBought,
        quantityBought: lastOp.quantityBought,
        priceBought: lastOp.priceBought,
        stockDividends: lastOp.stockDividends + c1AccumulatedStockDiv,
        fiiDividends: 0.0,
        fairValue: lastOp.fairValue,
        stockPrice: lastOp.stockPrice,
        wasValuationMet: lastOp.wasValuationMet,
        purchaseReason: lastOp.purchaseReason,
        valuationFormulaValue: lastOp.valuationFormulaValue,
      );
    }
    if (c2Operations.isNotEmpty) {
      final lastOp = c2Operations.last;
      c2Operations[c2Operations.length - 1] = MonthlyOperation(
        operationDate: lastOp.operationDate,
        monthlyInvestment: lastOp.monthlyInvestment,
        assetBought: lastOp.assetBought,
        quantityBought: lastOp.quantityBought,
        priceBought: lastOp.priceBought,
        stockDividends: lastOp.stockDividends + c2AccumulatedStockDiv,
        fiiDividends: lastOp.fiiDividends + c2AccumulatedFiiDiv,
        fairValue: lastOp.fairValue,
        stockPrice: lastOp.stockPrice,
        wasValuationMet: lastOp.wasValuationMet,
        purchaseReason: lastOp.purchaseReason,
        valuationFormulaValue: lastOp.valuationFormulaValue,
      );
    }

    // Processamento do caso especial de Graham: se a margem nunca foi atingida, reconstrói o portfólio composto apenas de FIIs
    if (config.valuationMethod == ValuationMethod.graham && !grahamMarginEverMet && c2Positions.isNotEmpty) {
      c2StockShares = 0.0;
      c2FiiShares = 0.0;
      c2Cash = 0.0;
      c2TotalDividends = 0.0;
      c2TotalInvested = 0.0;
      c2Operations.clear();
      c2Positions.clear();

      int c2LastPurchaseYearGraham = 0;
      int c2LastPurchaseMonthGraham = 0;
      final Map<String, double> c2FiiSharesHistoryGraham = {};
      double c2AccumulatedFiiDivGraham = 0.0;
      final List<Dividend> unpaidFiiDividendsGraham = fiiDividends.dividends.where((d) {
        final payDate = DateTime.tryParse(d.paymentDate);
        return payDate != null && !payDate.isBefore(config.startDate);
      }).toList();

      if (latestFiiDivDate != null && latestFiiDivDate.isBefore(config.endDate)) {
        int monthsToAdd = 1;
        while (true) {
          final nextDivDate = DateTime(
            latestFiiDivDate.year,
            latestFiiDivDate.month + monthsToAdd,
            latestFiiDivDate.day,
          );
          if (nextDivDate.isAfter(config.endDate)) {
            break;
          }
          final String formattedDate = "${nextDivDate.year}-${nextDivDate.month.toString().padLeft(2, '0')}-${nextDivDate.day.toString().padLeft(2, '0')}";
          unpaidFiiDividendsGraham.add(Dividend(
            exDate: formattedDate,
            paymentDate: formattedDate,
            value: lastKnownFiiDivValue,
            type: 'COM',
          ));
          monthsToAdd++;
        }
      }

      if (oldestFiiDivDate != null && oldestFiiDivDate.isAfter(config.startDate)) {
        int monthsToSub = 1;
        while (true) {
          final prevDivDate = DateTime(
            oldestFiiDivDate.year,
            oldestFiiDivDate.month - monthsToSub,
            oldestFiiDivDate.day,
          );
          if (prevDivDate.isBefore(config.startDate)) {
            break;
          }
          final String formattedDate = "${prevDivDate.year}-${prevDivDate.month.toString().padLeft(2, '0')}-${prevDivDate.day.toString().padLeft(2, '0')}";
          unpaidFiiDividendsGraham.add(Dividend(
            exDate: formattedDate,
            paymentDate: formattedDate,
            value: oldestKnownFiiDivValue,
            type: 'COM',
          ));
          monthsToSub++;
        }
      }

      double? prevFiiPriceGraham;

      // Ponteiro cronológico FII otimizado para o fallback de Graham O(N+M)
      int fiiPointerGraham = 0;

      for (final currentStock in filteredStockPrices) {
        final DateTime currentDate = DateTime.parse(currentStock.date);
        final int year = currentDate.year;
        final int month = currentDate.month;
        final int day = currentDate.day;

        final double stockPrice = currentStock.close;

        // Otimização: Avança o ponteiro cronológico dos FIIs de forma linear O(N+M) no fallback
        while (fiiPointerGraham + 1 < fiiPrices.length) {
          final nextDate = DateTime.tryParse(fiiPrices[fiiPointerGraham + 1].date);
          if (nextDate == null || nextDate.isAfter(currentDate)) {
            break;
          }
          fiiPointerGraham++;
        }

        final StockPrice? currentFii = fiiPrices.isNotEmpty ? fiiPrices[fiiPointerGraham] : null;
        if (currentFii == null) continue;
        final double fiiPrice = currentFii.close;

        bool hasFiiEventTodayGraham = false;

        // Processa desdobramentos de FII no fallback de Graham
        for (final event in fiiEvents) {
          if (event.date.year == year && event.date.month == month && event.date.day == day) {
            final double multiplier = (event.ratioFrom > 0)
                ? (event.ratioTo / event.ratioFrom)
                : (event.factor > 0 ? 1.0 / event.factor : 1.0);

            if (multiplier != 1.0) {
              final double rawC2FiiShares = c2FiiShares * multiplier;
              final double flooredC2FiiShares = rawC2FiiShares.floorToDouble();
              final double residueC2Fii = rawC2FiiShares - flooredC2FiiShares;
              c2FiiShares = flooredC2FiiShares;
              c2Cash += residueC2Fii * fiiPrice;

              for (final key in c2FiiSharesHistoryGraham.keys) {
                c2FiiSharesHistoryGraham[key] = ((c2FiiSharesHistoryGraham[key] ?? 0.0) * multiplier).floorToDouble();
              }

              hasFiiEventTodayGraham = true;
            }
          }
        }

        // Detector automático de desdobramentos de FII no fallback de Graham
        if (!hasFiiEventTodayGraham && prevFiiPriceGraham != null && prevFiiPriceGraham > 0) {
          final double multiplier = _detectSplitMultiplier(prevFiiPriceGraham, fiiPrice);
          if (multiplier != 1.0) {
            final double rawC2FiiShares = c2FiiShares * multiplier;
            final double flooredC2FiiShares = rawC2FiiShares.floorToDouble();
            final double residueC2Fii = rawC2FiiShares - flooredC2FiiShares;
            c2FiiShares = flooredC2FiiShares;
            c2Cash += residueC2Fii * fiiPrice;

            for (final key in c2FiiSharesHistoryGraham.keys) {
              c2FiiSharesHistoryGraham[key] = ((c2FiiSharesHistoryGraham[key] ?? 0.0) * multiplier).floorToDouble();
            }
          }
        }

        final String currentKey = '$year-$month';
        c2FiiSharesHistoryGraham[currentKey] = c2FiiShares;

        // Processa pagamentos de proventos de FII no fallback
        final List<Dividend> dayFiiPaymentsGraham = [];
        unpaidFiiDividendsGraham.removeWhere((d) {
          final payDate = DateTime.tryParse(d.paymentDate);
          if (payDate == null) return true;
          if (!payDate.isAfter(currentDate)) {
            dayFiiPaymentsGraham.add(d);
            return true;
          }
          return false;
        });

        double c2FiiDiv = 0.0;
        for (final d in dayFiiPaymentsGraham) {
          final String exDateStr = d.exDate.isNotEmpty ? d.exDate : d.paymentDate;
          final exDate = DateTime.tryParse(exDateStr);
          if (exDate != null) {
            final String exKey = '${exDate.year}-${exDate.month}';
            final c2Shares = c2FiiSharesHistoryGraham[exKey] ?? 0.0;
            c2FiiDiv += c2Shares * d.value;
          }
        }
        c2TotalDividends += c2FiiDiv;

        if (config.considerarReinvestimento) {
          c2Cash += c2FiiDiv;
        }

        c2AccumulatedFiiDivGraham += c2FiiDiv;

        // Processa aporte mensal de FII no fallback
        final bool c2IsNewMonth = year != c2LastPurchaseYearGraham || month != c2LastPurchaseMonthGraham;
        final bool c2IsAfterPurchaseDay = day >= config.diaCompra;
        if (c2IsNewMonth && c2IsAfterPurchaseDay) {
          c2LastPurchaseYearGraham = year;
          c2LastPurchaseMonthGraham = month;
          
          c2Cash += config.monthlyInvestment;
          c2TotalInvested += config.monthlyInvestment;

          final double quantityBought = (c2Cash / fiiPrice).floorToDouble();

          String purchaseReason = '';
          if (quantityBought > 0) {
            purchaseReason = 'Comprado ${config.fiiTicker}: Fallback de Graham. A margem de segurança de ${config.safetyMargin.toStringAsFixed(0)}% nunca foi atingida pela ação ${config.stockTicker} em toda a simulação.';
          } else {
            purchaseReason = 'Aporte recebido de R\$ ${config.monthlyInvestment.toStringAsFixed(2)}, mas saldo em caixa insuficiente para comprar cotas de ${config.fiiTicker} no fallback de Graham.';
          }

          if (quantityBought > 0) {
            c2FiiShares += quantityBought;
            c2FiiSharesHistoryGraham[currentKey] = c2FiiShares;
            c2Cash -= quantityBought * fiiPrice;
          }

          c2Operations.add(MonthlyOperation(
            operationDate: currentDate,
            monthlyInvestment: config.monthlyInvestment,
            assetBought: quantityBought > 0 ? 'FII' : null,
            quantityBought: quantityBought,
            priceBought: quantityBought > 0 ? fiiPrice : 0.0,
            stockDividends: 0.0,
            fiiDividends: c2AccumulatedFiiDivGraham,
            fairValue: 0.0,
            stockPrice: stockPrice,
            wasValuationMet: false,
            purchaseReason: purchaseReason,
            valuationFormulaValue: 0.0,
          ));
          c2AccumulatedFiiDivGraham = 0.0;
        }

        c2Positions.add(PortfolioPosition(
          stockShares: 0.0,
          fiiShares: c2FiiShares,
          cash: c2Cash,
          date: currentDate,
          stockPrice: stockPrice,
          fiiPrice: fiiPrice,
        ));

        prevFiiPriceGraham = fiiPrice;
      }

      if (c2Operations.isNotEmpty) {
        final lastOp = c2Operations.last;
        c2Operations[c2Operations.length - 1] = MonthlyOperation(
          operationDate: lastOp.operationDate,
          monthlyInvestment: lastOp.monthlyInvestment,
          assetBought: lastOp.assetBought,
          quantityBought: lastOp.quantityBought,
          priceBought: lastOp.priceBought,
          stockDividends: 0.0,
          fiiDividends: lastOp.fiiDividends + c2AccumulatedFiiDivGraham,
          fairValue: 0.0,
          stockPrice: lastOp.stockPrice,
          wasValuationMet: false,
          purchaseReason: lastOp.purchaseReason,
          valuationFormulaValue: lastOp.valuationFormulaValue,
        );
      }
    }

    // Calcula as métricas de performance finais da simulação
    final double c1FinalValue = c1Positions.last.getTotalValue();
    final double c2FinalValue = c2Positions.last.getTotalValue();

    final double yearsDiff = max(0.1, (config.endDate.difference(config.startDate).inDays) / 365.25);
    final double c1Cagr = c1TotalInvested > 0 ? (pow(c1FinalValue / c1TotalInvested, 1 / yearsDiff) - 1) * 100.0 : 0.0;
    final double c2Cagr = c2TotalInvested > 0 ? (pow(c2FinalValue / c2TotalInvested, 1 / yearsDiff) - 1) * 100.0 : 0.0;

    final double c1Return = c1TotalInvested > 0 ? ((c1FinalValue - c1TotalInvested) / c1TotalInvested) * 100.0 : 0.0;
    final double c2Return = c2TotalInvested > 0 ? ((c2FinalValue - c2TotalInvested) / c2TotalInvested) * 100.0 : 0.0;

    final scenario1Result = BacktestScenarioResult(
      scenarioName: 'Apenas Ações (Buy & Hold)',
      finalValue: c1FinalValue,
      finalStockShares: c1StockShares,
      finalFiiShares: 0.0,
      finalCash: c1Cash,
      totalDividends: c1TotalDividends,
      totalInvested: c1TotalInvested,
      cagr: c1Cagr,
      totalReturn: c1Return,
      operations: c1Operations,
      monthlyPositions: c1Positions,
    );

    final scenario2Result = BacktestScenarioResult(
      scenarioName: 'Carteira Diversificada (Valuation Inteligente)',
      finalValue: c2FinalValue,
      finalStockShares: c2StockShares,
      finalFiiShares: c2FiiShares,
      finalCash: c2Cash,
      totalDividends: c2TotalDividends,
      totalInvested: c2TotalInvested,
      cagr: c2Cagr,
      totalReturn: c2Return,
      operations: c2Operations,
      monthlyPositions: c2Positions,
    );

    return BacktestResult(
      config: config,
      scenario1: scenario1Result,
      scenario2: scenario2Result,
      executionDate: DateTime.now(),
    );
  }

  // --- MÉTODOS AUXILIARES ---

  /// Calcula dividendos TTM (últimos 12 meses) a partir de uma data específica
  double _getTtmDividendsDaily(List<Dividend> dividends, DateTime currentDate) {
    final twelveMonthsAgo = currentDate.subtract(const Duration(days: 365));
    final ttmPayments = dividends.where((d) {
      final date = DateTime.tryParse(d.paymentDate);
      if (date == null) return false;
      return date.isAfter(twelveMonthsAgo) && !date.isAfter(currentDate);
    });
    return ttmPayments.fold(0.0, (sum, d) => sum + d.value);
  }

  /// Detecta se houve desdobramento/grupamento com base na variação brusca diária de preços.
  /// Serve como proteção caso eventos corporativos não estejam cadastrados na API.
  double _detectSplitMultiplier(double yesterdayPrice, double todayPrice) {
    if (yesterdayPrice <= 0 || todayPrice <= 0) return 1.0;
    final double ratio = yesterdayPrice / todayPrice;
    
    if (ratio >= 1.35 || ratio <= 0.65) {
      if (ratio >= 1.35) {
        final double rounded = ratio.roundToDouble();
        if ((ratio - rounded).abs() < 0.1) {
          return rounded;
        }
        for (double fraction in [1.5, 1.25, 1.05, 1.2, 1.1]) {
          if ((ratio - fraction).abs() < 0.02) {
            return fraction;
          }
        }
        return 1.0;
      } else {
        final double invRatio = 1.0 / ratio;
        final double roundedInv = invRatio.roundToDouble();
        if ((invRatio - roundedInv).abs() < 0.1) {
          return 1.0 / roundedInv;
        }
        for (double fraction in [1.5, 1.25, 1.2, 1.1]) {
          if ((invRatio - fraction).abs() < 0.02) {
            return 1.0 / fraction;
          }
        }
        return 1.0;
      }
    }
    return 1.0;
  }
}