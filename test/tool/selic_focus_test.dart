// A trajetória do Focus que `tool/selic_focus.dart` mede contra a curva
// (item B33): a Selic média de cada ano, e a curva que a reproduz.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/selic_focus.dart';

void main() {
  final hoje = DateTime(2026, 9, 14);

  test('Focus plano na taxa corrente dá a mesma taxa em todo ano', () {
    final fw = forwardsDoFocus(
        hoje, 0.12, {2026: 0.12, 2027: 0.12, 2028: 0.12}, 10);
    expect(fw, hasLength(10));
    for (final f in fw) {
      expect(f, closeTo(0.12, 1e-9));
    }
  });

  test('a taxa do ano fica entre a corrente e a do fim do ano, e depois do '
      'último ano segue a última expectativa', () {
    final fw = forwardsDoFocus(hoje, 0.14,
        {2026: 0.1375, 2027: 0.12, 2028: 0.105, 2029: 0.10, 2030: 0.10}, 10);
    // O primeiro ano atravessa a queda de 13,75% a 12%.
    expect(fw.first, lessThan(0.14));
    expect(fw.first, greaterThan(0.12));
    // A trajetória só cai, e termina plana em 10%.
    for (var k = 1; k < fw.length; k++) {
      expect(fw[k], lessThanOrEqualTo(fw[k - 1] + 1e-12));
    }
    expect(fw.last, closeTo(0.10, 1e-9));
  });

  test('a curva devolve os forwards de que foi montada, e a perpetuidade é o '
      'último', () {
    final fw = [0.13, 0.12, 0.11, 0.105, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10];
    final curva = curvaDosForwards(hoje, fw);
    final lidos = curva.annualForwards(10);
    for (var k = 0; k < 10; k++) {
      expect(lidos[k], closeTo(fw[k], 1e-9), reason: 'ano ${k + 1}');
    }
    expect(curva.terminalRate(10), closeTo(0.10, 1e-9));
  });
}
