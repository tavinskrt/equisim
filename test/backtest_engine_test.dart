import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:equisim/models/backtest.dart';
import 'package:equisim/services/backtest_engine.dart';

void main() {
  setUpAll(() {
    // Configura o dotenv para testes locais com valores fictícios
    dotenv.testLoad(fileInput: '''
BOLSAI_API_KEY=mock_api_key
BOLSAI_BASE_URL=https://api.usebolsai.com/api/v1
''');
  });

  group('BacktestEngine & Valuation Safeguards Tests', () {
    test('Should liquidate fractional shares to cash after a split', () async {
      // 1. Criar respostas Mock para a simulação de split
      // Simularemos 5 dias úteis. No dia 3, o preço cai de 30.0 para 15.0 (split limpo de 1:2)
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        
        if (path.contains('/stocks/PETR4/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 30.0, 'high': 30.5, 'low': 29.5, 'close': 30.0, 'volume': 1000},
              {'date': '2026-05-02', 'open': 30.0, 'high': 30.2, 'low': 29.8, 'close': 30.0, 'volume': 1000},
              // Dia 3: Desdobramento detectado de 2.0x. Preço cai de 30.0 para 15.0
              {'date': '2026-05-03', 'open': 15.0, 'high': 15.2, 'low': 14.8, 'close': 15.0, 'volume': 2000},
              {'date': '2026-05-04', 'open': 15.0, 'high': 15.1, 'low': 14.9, 'close': 15.0, 'volume': 2000},
              {'date': '2026-05-05', 'open': 15.0, 'high': 15.1, 'low': 14.9, 'close': 15.0, 'volume': 2000},
            ]
          }), 200);
        }
        
        if (path.contains('/stocks/MXRF11/history')) {
          // FII está estável em 10.0
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-02', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-03', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-04', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-05', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
            ]
          }), 200);
        }

        if (path.contains('/fundamentals/PETR4')) {
          return http.Response(jsonEncode({
            'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
            'roe': 20.0, 'roic': 15.0, 'dividend_yield': 8.0, 'market_cap': 1000000.0,
            'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
          }), 200);
        }

        if (path.contains('/fiis/MXRF11')) {
          return http.Response(jsonEncode({
            'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
            'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
            'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
            'vacancy_pct': 0.0, 'delinquency_pct': 0.0
          }), 200);
        }

        if (path.contains('/dividends/')) {
          return http.Response(jsonEncode({'payments': []}), 200);
        }

        if (path.contains('/corporate-events')) {
          return http.Response(jsonEncode({'events': []}), 200);
        }

        return http.Response(jsonEncode({}), 404);
      });

      // 2. Rodar o motor de simulação mockado
      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 5),
          monthlyInvestment: 100.0, // Aporte único inicial
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 20.0,
          diaCompra: 1, // Compra no dia 1
          considerarReinvestimento: true,
        );

        final result = await engine.runBacktest(config);
        
        // --- VALIDAÇÕES ---
        final s1 = result.scenario1; // Buy & Hold
        
        // No dia 1, com aporte de R$ 100.00 e preço de R$ 30.00:
        // Ações compradas = floor(100.00 / 30.00) = 3 cotas.
        // Saldo em caixa = 100.00 - (3 * 30.00) = R$ 10.00.
        // No dia 3, o preço cai para R$ 15.00 (Split 2.0x detectado automaticamente):
        // Novas ações = 3 * 2.0 = 6.0 cotas.
        // O saldo de ações deve ser rigorosamente INTEIRO!
        expect(s1.finalStockShares, 6.0);
        expect(s1.finalStockShares, s1.finalStockShares.toInt().toDouble());
        
        // Como o desdobramento foi de 3 para 6 cotas, o resíduo fracionário é 0.0.
        // O caixa final deve continuar sendo R$ 10.00.
        expect(s1.finalCash, closeTo(10.0, 0.001));

      }, () => mockClient);
    });

    test('Should liquidate fractional share residues to cash after a custom/non-integer split', () async {
      // 1. Criar respostas Mock para a simulação de split
      // Simularemos 5 dias úteis. No dia 3, o preço cai de 30.0 para 20.0 (Split 1.5x)
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        
        if (path.contains('/stocks/PETR4/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 30.0, 'high': 30.5, 'low': 29.5, 'close': 30.0, 'volume': 1000},
              {'date': '2026-05-02', 'open': 30.0, 'high': 30.2, 'low': 29.8, 'close': 30.0, 'volume': 1000},
              // Dia 3: Desdobramento detectado de 1.5x. Preço cai de 30.0 para 20.0
              {'date': '2026-05-03', 'open': 20.0, 'high': 20.2, 'low': 19.8, 'close': 20.0, 'volume': 2000},
              {'date': '2026-05-04', 'open': 20.0, 'high': 20.1, 'low': 19.9, 'close': 20.0, 'volume': 2000},
              {'date': '2026-05-05', 'open': 20.0, 'high': 20.1, 'low': 19.9, 'close': 20.0, 'volume': 2000},
            ]
          }), 200);
        }
        
        if (path.contains('/stocks/MXRF11/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-02', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-03', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-04', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
              {'date': '2026-05-05', 'open': 10.0, 'high': 10.1, 'low': 9.9, 'close': 10.0, 'volume': 1000},
            ]
          }), 200);
        }

        if (path.contains('/fundamentals/PETR4')) {
          return http.Response(jsonEncode({
            'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
            'roe': 20.0, 'roic': 15.0, 'dividend_yield': 8.0, 'market_cap': 1000000.0,
            'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
          }), 200);
        }

        if (path.contains('/fiis/MXRF11')) {
          return http.Response(jsonEncode({
            'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
            'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
            'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
            'vacancy_pct': 0.0, 'delinquency_pct': 0.0
          }), 200);
        }

        if (path.contains('/dividends/')) {
          return http.Response(jsonEncode({'payments': []}), 200);
        }

        if (path.contains('/corporate-events')) {
          return http.Response(jsonEncode({'events': []}), 200);
        }

        return http.Response(jsonEncode({}), 404);
      });

      // 2. Rodar a simulação
      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 5),
          monthlyInvestment: 100.0, // Aporte de R$ 100.00
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 20.0,
          diaCompra: 1,
          considerarReinvestimento: true,
        );

        final result = await engine.runBacktest(config);
        final s1 = result.scenario1;
        
        // Dia 1: Compra 3 ações a R$ 30.00. Caixa = R$ 10.00.
        // Dia 3: Split de 1.5x.
        // Novas ações brutas = 3 * 1.5 = 4.5 cotas.
        // Ações inteiras liquidadas = floor(4.5) = 4 cotas.
        // Resíduo fracionário = 0.5 cotas.
        // Valor do resíduo vendido a R$ 20.00 (preço do dia) = 0.5 * 20.00 = R$ 10.00.
        // Caixa final esperado = Caixa anterior (R$ 10.00) + Valor do resíduo (R$ 10.00) = R$ 20.00!
        
        expect(s1.finalStockShares, 4.0);
        expect(s1.finalStockShares, s1.finalStockShares.toInt().toDouble()); // Garantia de ser inteiro
        expect(s1.finalCash, closeTo(20.0, 0.001));

      }, () => mockClient);
    });

    test('Should mathematically validate Graham valuation method safeguards', () async {
      // Testaremos os limites matemáticos do cálculo de Graham
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/fundamentals/PETR4')) {
          // LPA negativo e VPA negativo (casos anômalos)
          return http.Response(jsonEncode({
            'eps': -1.5, 'lpa': -1.5, 'vpa': -5.0, 'pl': -3.0, 'pbv': -1.0, 
            'roe': -10.0, 'roic': -5.0, 'dividend_yield': 0.0, 'market_cap': 100000.0,
            'liabilities': 50000.0, 'equity': 50000.0, 'revenue': 100000.0, 'net_income': -15000.0
          }), 200);
        }
        if (path.contains('/stocks/PETR4/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100},
            ]
          }), 200);
        }
        if (path.contains('/stocks/MXRF11/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100},
            ]
          }), 200);
        }
        if (path.contains('/fiis/MXRF11')) {
          return http.Response(jsonEncode({
            'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
            'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
            'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
            'vacancy_pct': 0.0, 'delinquency_pct': 0.0
          }), 200);
        }
        if (path.contains('/dividends/')) return http.Response(jsonEncode({'payments': []}), 200);
        if (path.contains('/corporate-events')) return http.Response(jsonEncode({'events': []}), 200);
        return http.Response(jsonEncode({}), 404);
      });

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 1),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.graham,
          safetyMargin: 120.0, // Margem de segurança extrema (> 100%)
          diaCompra: 1,
          considerarReinvestimento: true,
        );

        // A execução deve concluir com sucesso e o safePrice deve ter sido protegido contra valores negativos
        final result = await engine.runBacktest(config);
        
        // Verifica se a simulação rodou perfeitamente
        expect(result.scenario2.operations.isNotEmpty, true);
        
        // Com margem de segurança de 120%, o safePrice deve ter sido limitado para 0.0
        // (Preço teto Graham dinâmico com margem de segurança de 120%: safePrice não-negativo)
        final op = result.scenario2.operations.first;
        expect(op.fairValue, isNonNegative);
      }, () => mockClient);
    });

    test('Should mathematically validate Bazin valuation method safeguards', () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/fundamentals/PETR4')) {
          return http.Response(jsonEncode({
            'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
            'roe': 20.0, 'roic': 15.0, 'dividend_yield': -5.0, // Dividend Yield negativo (anômalo)
            'market_cap': 1000000.0, 'liabilities': 500000.0, 'equity': 500000.0, 
            'revenue': 1000000.0, 'net_income': 100000.0
          }), 200);
        }
        if (path.contains('/stocks/PETR4/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100},
            ]
          }), 200);
        }
        if (path.contains('/stocks/MXRF11/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100},
            ]
          }), 200);
        }
        if (path.contains('/fiis/MXRF11')) {
          return http.Response(jsonEncode({
            'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
            'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
            'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
            'vacancy_pct': 0.0, 'delinquency_pct': 0.0
          }), 200);
        }
        if (path.contains('/dividends/')) return http.Response(jsonEncode({'payments': []}), 200);
        if (path.contains('/corporate-events')) return http.Response(jsonEncode({'events': []}), 200);
        return http.Response(jsonEncode({}), 404);
      });

      await http.runWithClient(() async {
        final engine = BacktestEngine();
        final config = BacktestConfig(
          stockTicker: 'PETR4',
          fiiTicker: 'MXRF11',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 1),
          monthlyInvestment: 100.0,
          valuationMethod: ValuationMethod.bazin,
          desiredRate: -2.0, // Taxa de retorno desejada negativa (anômala)
          diaCompra: 1,
          considerarReinvestimento: true,
          safetyMargin: 20.0,
        );

        // A execução deve concluir com sucesso sem divisão por zero ou erro de NaN
        final result = await engine.runBacktest(config);
        
        expect(result.scenario2.operations.isNotEmpty, true);
        final op = result.scenario2.operations.first;
        expect(op.fairValue.isFinite, true);
        expect(op.fairValue, isNonNegative);
      }, () => mockClient);
    });

    test('Should mathematically validate Peter Lynch valuation method safeguards', () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/fundamentals/PETR4')) {
          return http.Response(jsonEncode({
            // LPA zero/negativo (anômalo)
            'eps': -0.5, 'lpa': -0.5, 'vpa': 10.0, 'pl': -20.0, 'pbv': 1.0, 
            'roe': -5.0, 'roic': 5.0, 'dividend_yield': 0.0, 'market_cap': 1000000.0,
            'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': -25000.0
          }), 200);
        }
        if (path.contains('/stocks/PETR4/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100},
            ]
          }), 200);
        }
        if (path.contains('/stocks/MXRF11/history')) {
          return http.Response(jsonEncode({
            'prices': [
              {'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100},
            ]
          }), 200);
        }
        if (path.contains('/fiis/MXRF11')) {
          return http.Response(jsonEncode({
            'ticker': 'MXRF11', 'name': 'Maxi Renda', 'reference_date': '2026-05-01',
            'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 10.0,
            'net_asset_value': 500000.0, 'shares_outstanding': 50000.0, 'segment': 'Papel',
            'vacancy_pct': 0.0, 'delinquency_pct': 0.0
          }), 200);
        }
        if (path.contains('/dividends/')) return http.Response(jsonEncode({'payments': []}), 200);
        if (path.contains('/corporate-events')) return http.Response(jsonEncode({'events': []}), 200);
        return http.Response(jsonEncode({}), 404);
      });

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

        // A execução deve concluir e o cálculo de Peter Lynch deve ser seguro
        final result = await engine.runBacktest(config);
        
        expect(result.scenario2.operations.isNotEmpty, true);
        final op = result.scenario2.operations.first;
        expect(op.valuationFormulaValue!.isFinite, true);
      }, () => mockClient);
    });

    group('Valuation Mathematical Precision Tests (Theoretical Equations)', () {
      test('Graham Formula - should calculate exact value of sqrt(22.5 * LPA * VPA)', () async {
        final mockClient = MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/fundamentals/PETR4')) {
            return http.Response(jsonEncode({
              'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
              'roe': 20.0, 'roic': 15.0, 'dividend_yield': 0.0, 'market_cap': 1000000.0,
              'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
            }), 200);
          }
          if (path.contains('/stocks/PETR4/history') || path.contains('/stocks/MXRF11/history')) {
            return http.Response(jsonEncode({
              'prices': [{'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100}]
            }), 200);
          }
          if (path.contains('/fiis/MXRF11')) {
            return http.Response(jsonEncode({
              'ticker': 'MXRF11', 'name': 'MXRF11', 'reference_date': '2026-05-01',
              'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 0.0,
              'net_asset_value': 100000.0, 'shares_outstanding': 10000.0, 'segment': 'Papel', 'vacancy_pct': 0.0, 'delinquency_pct': 0.0
            }), 200);
          }
          return http.Response(jsonEncode({'payments': [], 'events': []}), 200);
        });

        await http.runWithClient(() async {
          final engine = BacktestEngine();
          final config = BacktestConfig(
            stockTicker: 'PETR4',
            fiiTicker: 'MXRF11',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 5, 1), // Mesma data -> yearsFromEnd = 0
            monthlyInvestment: 100.0,
            valuationMethod: ValuationMethod.graham,
            safetyMargin: 0.0, // Sem margem de segurança para testar o valor cheio
            diaCompra: 1,
            considerarReinvestimento: false,
          );

          final result = await engine.runBacktest(config);
          final op = result.scenario2.operations.first;

          // Teoria de Graham: sqrt(22.5 * LPA * VPA) = sqrt(22.5 * 2.0 * 10.0) = sqrt(450.0) = 21.2132
          expect(op.fairValue, closeTo(21.2132, 0.001));
        }, () => mockClient);
      });

      test('Bazin Formula - should calculate exact value of Dividend / (desiredRate / 100)', () async {
        final mockClient = MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/fundamentals/PETR4')) {
            return http.Response(jsonEncode({
              'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
              'roe': 20.0, 'roic': 15.0, 
              'dividend_yield': 8.0, // dyield = 8% -> Dividend = 10.0 * 0.08 = 0.8
              'market_cap': 1000000.0, 'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
            }), 200);
          }
          if (path.contains('/stocks/PETR4/history') || path.contains('/stocks/MXRF11/history')) {
            return http.Response(jsonEncode({
              'prices': [{'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100}]
            }), 200);
          }
          if (path.contains('/fiis/MXRF11')) {
            return http.Response(jsonEncode({
              'ticker': 'MXRF11', 'name': 'MXRF11', 'reference_date': '2026-05-01',
              'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 0.0,
              'net_asset_value': 100000.0, 'shares_outstanding': 10000.0, 'segment': 'Papel', 'vacancy_pct': 0.0, 'delinquency_pct': 0.0
            }), 200);
          }
          return http.Response(jsonEncode({'payments': [], 'events': []}), 200);
        });

        await http.runWithClient(() async {
          final engine = BacktestEngine();
          final config = BacktestConfig(
            stockTicker: 'PETR4',
            fiiTicker: 'MXRF11',
            startDate: DateTime(2026, 5, 1),
            endDate: DateTime(2026, 5, 1),
            monthlyInvestment: 100.0,
            valuationMethod: ValuationMethod.bazin,
            desiredRate: 6.0, // Taxa desejada de 6%
            diaCompra: 1,
            considerarReinvestimento: false,
            safetyMargin: 0.0,
          );

          final result = await engine.runBacktest(config);
          final op = result.scenario2.operations.first;

          // Teoria de Bazin: Div / Taxa = 0.8 / 0.06 = 13.3333
          expect(op.fairValue, closeTo(13.3333, 0.001));
        }, () => mockClient);
      });

      test('Peter Lynch Formula - should calculate exact value of (ROE + DY) / PE', () async {
        final mockClient = MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/fundamentals/PETR4')) {
            return http.Response(jsonEncode({
              'eps': 2.0, 'lpa': 2.0, 'vpa': 10.0, 'pl': 5.0, 'pbv': 1.0, 
              'roe': 15.0, // ROE = 15%
              'roic': 15.0, 'dividend_yield': 0.0, 'market_cap': 1000000.0,
              'liabilities': 500000.0, 'equity': 500000.0, 'revenue': 1000000.0, 'net_income': 100000.0
            }), 200);
          }
          if (path.contains('/stocks/PETR4/history') || path.contains('/stocks/MXRF11/history')) {
            // Preço da ação = 10.0 -> PE = Price/LPA = 10.0/2.0 = 5.0
            return http.Response(jsonEncode({
              'prices': [{'date': '2026-05-01', 'open': 10.0, 'high': 10.0, 'low': 10.0, 'close': 10.0, 'volume': 100}]
            }), 200);
          }
          if (path.contains('/fiis/MXRF11')) {
            return http.Response(jsonEncode({
              'ticker': 'MXRF11', 'name': 'MXRF11', 'reference_date': '2026-05-01',
              'close_price': 10.0, 'book_value_per_share': 10.0, 'pvp': 1.0, 'dividend_yield_ttm': 0.0,
              'net_asset_value': 100000.0, 'shares_outstanding': 10000.0, 'segment': 'Papel', 'vacancy_pct': 0.0, 'delinquency_pct': 0.0
            }), 200);
          }
          return http.Response(jsonEncode({'payments': [], 'events': []}), 200);
        });

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

          // Teoria de Peter Lynch: (ROE + DY) / PE = (15.0 + 0.0) / 5.0 = 3.0
          expect(op.valuationFormulaValue, closeTo(3.0, 0.001));
        }, () => mockClient);
      });
    });
  });
}
