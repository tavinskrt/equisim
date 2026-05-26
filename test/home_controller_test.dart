import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:equisim/controllers/home_controller.dart';
import 'package:equisim/services/stock_service.dart';

void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('HomeController Date & Validation Tests', () {
    test('isValid should return false when tickers or dates are empty', () {
      final controller = HomeController();
      expect(controller.isValid, false);
      expect(controller.getValidationError(), contains('Ação'));
    });

    test('isValid should return true for valid parameters within 10 years', () {
      final controller = HomeController();
      controller.setStockTicker('PETR4');
      controller.setFiiTicker('MXRF11');
      controller.setAporte('100000'); // setAporte strips non-digits and formats
      
      final now = DateTime.now();
      final startDate = DateTime(now.year - 5, now.month, now.day);
      final endDate = DateTime(now.year, now.month, now.day);
      
      controller.setStartDate(startDate);
      controller.setEndDate(endDate);
      
      expect(controller.isValid, true);
      expect(controller.getValidationError(), isNull);
    });

    test('validation should fail if startDate is more than 10 years ago', () {
      final controller = HomeController();
      controller.setStockTicker('PETR4');
      controller.setFiiTicker('MXRF11');
      controller.setAporte('100000');
      
      final now = DateTime.now();
      // More than 10 years ago by exactly 1 day
      final startDate = DateTime(now.year - 10, now.month, now.day - 1);
      final endDate = DateTime(now.year, now.month, now.day);
      
      controller.setStartDate(startDate);
      controller.setEndDate(endDate);
      
      expect(controller.isValid, false);
      expect(controller.getValidationError(), contains('superior a 10 anos'));
    });

    test('StockService should correctly filter BDRs and ETFs and keep whitelisted Units', () async {
      final service = StockService();
      final stocks = await service.fetchAllStockTickers();
      final fiis = await service.fetchAllFiiTickers();

      // Ensure lists are loaded
      expect(stocks, isNotEmpty);
      expect(fiis, isNotEmpty);

      // ETFs and BDRs should be filtered out
      expect(stocks.contains('BOVA11'), false); // ETF
      expect(stocks.contains('SMAL11'), false); // ETF
      expect(stocks.contains('IVVB11'), false); // ETF
      expect(stocks.contains('AAPL34'), false); // BDR
      expect(stocks.contains('MSFT34'), false); // BDR

      // Whitelisted Units should be kept
      expect(stocks.contains('TAEE11'), true);
      expect(stocks.contains('KLBN11'), true);

      // Normal stocks should be kept
      expect(stocks.contains('PETR4'), true);
      expect(stocks.contains('VALE3'), true);

      // FIIs should be in fiis list and end with 11
      expect(fiis.contains('MXRF11'), true);
      expect(fiis.contains('HGLG11'), true);
      expect(fiis.every((t) => t.endsWith('11')), true);
    });

    test('HomeController should automatically rename VIIA3 to BHIA3 using ticker history API', () async {
      final controller = HomeController();
      
      // VIIA3 is the old ticker for BHIA3
      controller.setStockTicker('VIIA3');
      controller.setFiiTicker('MXRF11');

      // Wait for async checkAndUpdateDates to finish
      int limit = 0;
      while (controller.isFetchingDates && limit < 100) {
        await Future.delayed(const Duration(milliseconds: 100));
        limit++;
      }

      expect(controller.stockTicker, 'BHIA3');
      expect(controller.renamedMessage, contains('renomeado para \'BHIA3\''));
      expect(controller.stockError, isNull);
    });

    test('HomeController should set error message for invalid tickers', () async {
      final controller = HomeController();
      
      controller.setStockTicker('AAAA3'); // Invalid stock
      controller.setFiiTicker('MXRF11');

      // Wait for async checkAndUpdateDates to finish
      int limit = 0;
      while (controller.isFetchingDates && limit < 100) {
        await Future.delayed(const Duration(milliseconds: 100));
        limit++;
      }

      expect(controller.stockError, contains('não encontrada'));
    });
  });
}
