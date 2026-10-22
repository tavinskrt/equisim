import 'package:equisim/presentation/shared/domain_copy.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// O rótulo de tela saiu dos enums do núcleo (item B21, decisão 125).
///
/// O `switch` exaustivo garante que todo valor **tem** rótulo; isto garante que
/// o rótulo é texto de gente — não vazio, não o `name` cru, e sem dois valores
/// do mesmo enum lidos igual na tela.
void main() {
  void check<T extends Enum>(List<T> values, String Function(T) label) {
    final readLabels = [for (final v in values) label(v)];
    for (var i = 0; i < values.length; i++) {
      expect(readLabels[i].trim(), isNotEmpty, reason: '${values[i]}');
      expect(readLabels[i], isNot(values[i].name), reason: '${values[i]}');
    }
    expect(readLabels.toSet().length, values.length,
        reason: 'dois valores de ${T.toString()} com o mesmo rótulo');
  }

  test('todo valor tem rótulo próprio', () {
    check(ValuationModel.values, (v) => v.label);
    check(ScenarioBand.values, (v) => v.label);
    check(ValuationCaveat.values, (v) => v.label);
    check(TransversalOrdering.values, (v) => v.label);
    check(MultipleKind.values, (v) => v.label);
    check(MultipleRefusal.values, (v) => v.label);
    check(ManualGroup.values, (v) => v.label);
    check(ManualTerminal.values, (v) => v.label);
  });

  test('a tela lê o que lia antes da mudança', () {
    // O texto não mudou de lugar para mudar de redação: quem decide a
    // redação agora é a tela, e esta é a de 22/09/2026.
    expect(ValuationModel.dcfFcff.label, 'DCF por fluxo da firma');
    // Pelas premissas, e não pelo resultado (decisão 148, item B38).
    expect(ScenarioBand.bear.label, 'Premissas mais duras');
    expect(ScenarioBand.bull.label, 'Premissas mais brandas');
    expect(MultipleKind.evToEbitda.label, 'EV/EBITDA');
  });
}
