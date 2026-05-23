import 'package:flutter_test/flutter_test.dart';
import 'package:equisim/controllers/home_controller.dart';

void main() {
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
  });
}
