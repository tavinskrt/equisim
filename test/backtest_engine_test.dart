import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:equisim/models/backtest.dart';
import 'package:equisim/services/backtest_engine.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: '''
BOLSAI_API_KEY=mock_api_key
BOLSAI_BASE_URL=https://api.usebolsai.com/api/v1
BRAPI_TOKEN=mock_token
BRAPI_BASE_URL=https://brapi.dev/api
''');
  });

  http.Response createMockResponse(http.Request request, {
    List<Map<String, dynamic>>? customPetrPrices,
    List<Map<String, dynamic>>? customMxrfPrices,
    Map<String, dynamic>? customPetrFundamentals,
    Map<String, dynamic>? customMxrfFundamentals,
    List<Map<String, dynamic>>? customDividends,
  }) {
    final path = request.url.path;
    final query = request.url.query;

    final defaultPetrPrices = [
      {'date': '2026-05-01', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-02', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-03', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-04', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-05', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
    ];

    final defaultMxrfPrices = [
      {'date': '2026-05-01', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-02', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-03', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-04', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
      {'date': '2026-05-05', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
    ];

    if (path.contains('/historical') || path.contains('/history')) {
      if (query.contains('MXRF11') || path.contains('MXRF11')) {
        return http.Response(jsonEncode({
          'results': [
            {
              'symbol': 'MXRF11',
              'historicalDataPrice': customMxrfPrices ?? defaultMxrfPrices,
            }
          ],
          'prices': customMxrfPrices ?? defaultMxrfPrices,
        }), 200);
      }
      return http.Response(jsonEncode({
        'results': [
          {
            'symbol': 'PETR4',
            'historicalDataPrice': customPetrPrices ?? defaultPetrPrices,
          }
        ],
        'prices': customPetrPrices ?? defaultPetrPrices,
      }), 200);
    }

    if (path.contains('/statistics') || path.contains('/financial-data') || path.contains('/fundamentals')) {
      final defaultFundamentals = {
        'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
        'roe': 20.0, 'roic': 15.0, 'dividend_yield': 8.0, 'market_cap': 1000000.0,
        'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
      };
      final dataObj = customPetrFundamentals ?? defaultFundamentals;
      return http.Response(jsonEncode({
        'results': [
          {
            'symbol': 'PETR4',
            ...dataObj,
          }
        ],
        ...dataObj,
      }), 200);
    }

    if (path.contains('/quote')) {
      final isMxrf = query.contains('MXRF11');
      return http.Response(jsonEncode({
        'results': [
          {
            'symbol': isMxrf ? 'MXRF11' : 'PETR4',
            'regularMarketPrice': 10.0,
            'close': 10.0,
          }
        ]
      }), 200);
    }

    if (path.contains('/indicators') || path.contains('/fiis')) {
      return http.Response(jsonEncode({
        'results': [
          {
            'symbol': 'MXRF11',
            'regularMarketPrice': 10.0,
            ...?customMxrfFundamentals,
            'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
            'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
            'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
            'vacancy_pct': 0.0, 'delinquency_pct': 0.0
          }
        ],
        'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
        'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
        'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
        'vacancy_pct': 0.0, 'delinquency_pct': 0.0
      }), 200);
    }

    if (path.contains('/dividends')) {
      return http.Response(jsonEncode({
        'results': [
          {
            'symbol': query.contains('MXRF11') ? 'MXRF11' : 'PETR4',
            'cashDividends': customDividends ?? [],
          }
        ],
        'cashDividends': customDividends ?? [],
        'payments': customDividends ?? [],
      }), 200);
    }

    if (path.contains('/corporate-events') || path.contains('/events')) {
      return http.Response(jsonEncode({'events': [], 'stockDividends': []}), 200);
    }

    return http.Response(jsonEncode({}), 404);
  }

  group('BacktestEngine & Valuation Safeguards Tests', () {
    test('Should liquidate fractional shares to cash after a split', () async {
      final customPetrPrices = [
        {'date': '2026-05-01', 'open': 30.0, 'high': 30.5, 'low': 29.5, 'close': 30.0, 'volume': 1000},
        {'date': '2026-05-02', 'open': 30.0, 'high': 30.2, 'low': 29.8, 'close': 30.0, 'volume': 1000},
        {'date': '2026-05-03', 'open': 15.0, 'high': 15.2, 'low': 14.8, 'close': 15.0, 'volume': 2000},
        {'date': '2026-05-04', 'open': 15.0, 'high': 15.1, 'low': 14.9, 'close': 15.0, 'volume': 2000},
        {'date': '2026-05-05', 'open': 15.0, 'high': 15.1, 'low': 14.9, 'close': 15.0, 'volume': 2000},
      ];

      final mockClient = MockClient((req) async => createMockResponse(req, customPetrPrices: customPetrPrices));

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 5),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 20.0,
          diaCompra: 1,
          considerarReinvestimento: true,
        );

        final result = await engine.runBacktest(config);
        final s1 = result.scenario1;
        
        expect(s1.finalStockShares, 6.0);
        expect(s1.finalStockShares, s1.finalStockShares.toInt().toDouble());
        expect(s1.finalCash, closeTo(10.0, 0.001));
      }, () => mockClient);
    });

    test('Should liquidate fractional share residues to cash after a custom/non-integer split', () async {
      final customPetrPrices = [
        {'date': '2026-05-01', 'open': 30.0, 'high': 30.5, 'low': 29.5, 'close': 30.0, 'volume': 1000},
        {'date': '2026-05-02', 'open': 30.0, 'high': 30.2, 'low': 29.8, 'close': 30.0, 'volume': 1000},
        {'date': '2026-05-03', 'open': 20.0, 'high': 20.2, 'low': 19.8, 'close': 20.0, 'volume': 2000},
        {'date': '2026-05-04', 'open': 20.0, 'high': 20.1, 'low': 19.9, 'close': 20.0, 'volume': 2000},
        {'date': '2026-05-05', 'open': 20.0, 'high': 20.1, 'low': 19.9, 'close': 20.0, 'volume': 2000},
      ];

      final mockClient = MockClient((req) async => createMockResponse(req, customPetrPrices: customPetrPrices));

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 5),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 20.0,
          diaCompra: 1,
          considerarReinvestimento: true,
        );

        final result = await engine.runBacktest(config);
        final s1 = result.scenario1;
        
        expect(s1.finalStockShares, 4.0);
        expect(s1.finalStockShares, s1.finalStockShares.toInt().toDouble());
        expect(s1.finalCash, closeTo(20.0, 0.001));
      }, () => mockClient);
    });

    test('Should calculate and accumulate FII dividends correctly in Scenario 2 when FII is bought', () async {
      final customPetrPrices = [
        {'date': '2026-05-01', 'open': 100.0, 'high': 100.0, 'low': 100.0, 'close': 100.0, 'volume': 1000},
        {'date': '2026-05-02', 'open': 100.0, 'high': 100.0, 'low': 100.0, 'close': 100.0, 'volume': 1000},
        {'date': '2026-05-03', 'open': 100.0, 'high': 100.0, 'low': 100.0, 'close': 100.0, 'volume': 1000},
      ];

      final customDividends = [
        {
          'rate': 0.50,
          'paymentDate': '2026-05-02',
          'lastDatePrior': '2026-05-01',
          'type': 'RENDIMENTO'
        }
      ];

      final mockClient = MockClient((req) async => createMockResponse(
        req,
        customPetrPrices: customPetrPrices,
        customDividends: req.url.query.contains('MXRF11') ? customDividends : [],
      ));

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 3),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 20.0,
          diaCompra: 1,
          considerarReinvestimento: true,
        );

        final result = await engine.runBacktest(config);
        final s2 = result.scenario2;
        
        expect(s2.finalFiiShares, 10.0);
        final fiiDivTotal = s2.operations.fold(0.0, (sum, op) => sum + op.fiiDividends);
        expect(fiiDivTotal, closeTo(5.0, 0.001));
      }, () => mockClient);
    });

    test('Should mathematically validate Graham valuation method safeguards', () async {
      final customPetrFundamentals = {
        'eps': -1.5, 'lpa': -1.5, 'vpa': -5.0, 'pl': -3.0, 'pbv': -1.0, 
        'roe': -10.0, 'roic': -5.0, 'dividend_yield': 0.0, 'market_cap': 100000.0,
        'liabilities': 50000.0, 'equity': 50000.0, 'revenue': 100000.0, 'net_income': -15000.0
      };

      final mockClient = MockClient((req) async => createMockResponse(req, customPetrFundamentals: customPetrFundamentals));

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 1),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 120.0,
          diaCompra: 1,
          considerarReinvestimento: true,
        );

        final result = await engine.runBacktest(config);
        expect(result.scenario2.operations.isNotEmpty, true);
        final op = result.scenario2.operations.first;
        expect(op.fairValue, isNonNegative);
      }, () => mockClient);
    });

    test('Should mathematically validate Bazin valuation method safeguards', () async {
      final customPetrFundamentals = {
        'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
        'roe': 20.0, 'roic': 15.0, 'dividend_yield': -5.0,
        'market_cap': 1000000.0, 'liabilities': 500000.0, 'equity': 500000.0, 
        'revenue': 1000000.0, 'net_income': 100000.0
      };

      final mockClient = MockClient((req) async => createMockResponse(req, customPetrFundamentals: customPetrFundamentals));

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 1),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.bazin,
          desiredRate: -2.0,
          diaCompra: 1,
          considerarReinvestimento: true,
          safetyMargin: 20.0,
        );

        final result = await engine.runBacktest(config);
        expect(result.scenario2.operations.isNotEmpty, true);
        final op = result.scenario2.operations.first;
        expect(op.fairValue.isFinite, true);
        expect(op.fairValue, isNonNegative);
      }, () => mockClient);
    });

    test('Should mathematically validate Peter Lynch valuation method safeguards', () async {
      final customPetrFundamentals = {
        'eps': -0.5, 'lpa': -0.5, 'vpa': 10.0, 'pl': -20.0, 'pbv': 1.0, 
        'roe': -5.0, 'roic': 5.0, 'dividend_yield': 0.0, 'market_cap': 1000000.0,
        'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': -25000.0
      };

      final mockClient = MockClient((req) async => createMockResponse(req, customPetrFundamentals: customPetrFundamentals));

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 1),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.peterLynch,
          diaCompra: 1,
          considerarReinvestimento: true,
          safetyMargin: 20.0,
        );

        final result = await engine.runBacktest(config);
        expect(result.scenario2.operations.isNotEmpty, true);
        final op = result.scenario2.operations.first;
        expect(op.valuationFormulaValue!.isFinite, true);
      }, () => mockClient);
    });

    group('Valuation Mathematical Precision Tests (Theoretical Equations)', () {
      test('Graham Formula - should calculate exact value of sqrt(22.5 * LPA * VPA)', () async {
        final mockClient = MockClient((req) async => createMockResponse(req));

        await http.runWithClient(() async {
          final engine = BacktestEngine();
          final config = BacktestConfig(
            stockTicker: 'PETR4',
            fiiTicker: 'MXRF11',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 5, 1),
            monthlyInvestment: 100.0,
            valuationMethod: ValuationMethod.graham,
            safetyMargin: 0.0,
            diaCompra: 1,
            considerarReinvestimento: false,
          );

          final result = await engine.runBacktest(config);
          final op = result.scenario2.operations.first;

          expect(op.fairValue, closeTo(21.2132, 0.001));
        }, () => mockClient);
      });

      test('Bazin Formula - should calculate exact value of Dividend / (desiredRate / 100)', () async {
        final customPetrFundamentals = {
          'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
          'roe': 20.0, 'roic': 15.0, 
          'dividend_yield': 8.0,
          'market_cap': 1000000.0, 'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
        };

        final mockClient = MockClient((req) async => createMockResponse(req, customPetrFundamentals: customPetrFundamentals));

        await http.runWithClient(() async {
          final engine = BacktestEngine();
          final config = BacktestConfig(
            stockTicker: 'PETR4',
            fiiTicker: 'MXRF11',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 5, 1),
            monthlyInvestment: 100.0,
            valuationMethod: ValuationMethod.bazin,
            desiredRate: 6.0,
            diaCompra: 1,
            considerarReinvestimento: false,
            safetyMargin: 0.0,
          );

          final result = await engine.runBacktest(config);
          final op = result.scenario2.operations.first;

          expect(op.fairValue, closeTo(13.3333, 0.001));
        }, () => mockClient);
      });

      test('Peter Lynch Formula - should calculate exact value of (ROE + DY) / PE', () async {
        final customPetrFundamentals = {
          'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
          'roe': 15.0, 
          'roic': 15.0, 'dividend_yield': 0.0, 'market_cap': 1000000.0,
          'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
        };

        final mockClient = MockClient((req) async => createMockResponse(req, customPetrFundamentals: customPetrFundamentals));

        await http.runWithClient(() async {
          final engine = BacktestEngine();
          final config = BacktestConfig(
            stockTicker: 'PETR4',
            fiiTicker: 'MXRF11',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 5, 1),
            monthlyInvestment: 100.0,
            valuationMethod: ValuationMethod.peterLynch,
            diaCompra: 1,
            considerarReinvestimento: false,
            safetyMargin: 0.0,
          );

          final result = await engine.runBacktest(config);
          final op = result.scenario2.operations.first;

          expect(op.valuationFormulaValue, closeTo(3.0, 0.001));
        }, () => mockClient);
      });
    });
  });
}
