import 'package:flutter_test/flutter_test.dart';
import 'package:equisim/models/corporate_event.dart';

// Definindo a função local para testar a matemática da detecção antes de rodá-la no engine
double testDetectSplitMultiplier(double yesterdayPrice, double todayPrice) {
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
      return 1.0; // Evita assumir razões estranhas de ruído ou volatilidade (ex: 1.44)
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
      return 1.0; // Evita assumir razões estranhas de ruído ou volatilidade
    }
  }
  return 1.0;
}

void main() {
  group('CorporateEvent Tests', () {
    test('Should parse SPLIT event correctly', () {
      final json = {
        'date': '2025-12-09',
        'type': 'SPLIT',
        'ratio_from': 20,
        'ratio_to': 21,
        'description': '20:21',
        'factor': 0.952381
      };

      final event = CorporateEvent.fromJson(json);

      expect(event.type, 'SPLIT');
      expect(event.ratioFrom, 20);
      expect(event.ratioTo, 21);
      expect(event.description, '20:21');
      expect(event.factor, 0.952381);
      
      final multiplier = event.ratioTo / event.ratioFrom;
      expect(multiplier, closeTo(1.05, 0.001));
    });

    test('Should parse INPLIT event correctly', () {
      final json = {
        'date': '2024-05-27',
        'type': 'INPLIT',
        'ratio_from': 10,
        'ratio_to': 1,
        'description': '10:1',
        'factor': 10.0
      };

      final event = CorporateEvent.fromJson(json);

      expect(event.type, 'INPLIT');
      expect(event.ratioFrom, 10);
      expect(event.ratioTo, 1);
      expect(event.description, '10:1');
      expect(event.factor, 10.0);
      
      final multiplier = event.ratioTo / event.ratioFrom;
      expect(multiplier, 0.1);
    });
  });

  group('Auto-Detect Split/Inplit Safeguard Tests', () {
    test('Should detect FII split 1:10 (HGLG11 scenario: 1397.5 to 139.5)', () {
      final multiplier = testDetectSplitMultiplier(1397.5, 139.5);
      expect(multiplier, 10.0); // 1 share becomes 10 shares
    });

    test('Should detect Stock split 1:2 (price halves: 30.0 to 15.0)', () {
      final multiplier = testDetectSplitMultiplier(30.0, 15.0);
      expect(multiplier, 2.0); // 1 share becomes 2 shares
    });

    test('Should detect Stock inplit 10:1 (price 10x: 1.5 to 15.0)', () {
      final multiplier = testDetectSplitMultiplier(1.5, 15.0);
      expect(multiplier, 0.1); // 10 shares become 1 share
    });

    test('Should ignore normal daily fluctuations (price 100.0 to 95.0)', () {
      final multiplier = testDetectSplitMultiplier(100.0, 95.0);
      expect(multiplier, 1.0); // No adjustment
    });

    test('Should ignore normal positive fluctuations (price 100.0 to 105.0)', () {
      final multiplier = testDetectSplitMultiplier(100.0, 105.0);
      expect(multiplier, 1.0); // No adjustment
    });

    test('Should ignore high daily volatility/crash without clean split ratio (price 14.4 to 10.0)', () {
      final multiplier = testDetectSplitMultiplier(14.4, 10.0);
      expect(multiplier, 1.0); // No adjustment (ratio is 1.44, not a clean split)
    });

    test('Should ignore high daily rise without clean inplit ratio (price 10.0 to 14.4)', () {
      final multiplier = testDetectSplitMultiplier(10.0, 14.4);
      expect(multiplier, 1.0); // No adjustment (invRatio is 1.44, not a clean inplit)
    });
  });
}
