import 'package:equisim/presentation/shared/domain_copy.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// O rótulo de tela saiu dos enums do núcleo (item B21, decisão 125).
///
/// O `switch` exaustivo garante que todo valor **tem** rótulo; isto garante que
/// o rótulo é texto de gente — não vazio, não o `name` cru, e sem dois valores
/// do mesmo enum lidos igual na tela.
void main() {
  void confere<T extends Enum>(List<T> valores, String Function(T) rotulo) {
    final lidos = [for (final v in valores) rotulo(v)];
    for (var i = 0; i < valores.length; i++) {
      expect(lidos[i].trim(), isNotEmpty, reason: '${valores[i]}');
      expect(lidos[i], isNot(valores[i].name), reason: '${valores[i]}');
    }
    expect(lidos.toSet().length, valores.length,
        reason: 'dois valores de ${T.toString()} com o mesmo rótulo');
  }

  test('todo valor tem rótulo próprio', () {
    confere(ValuationModel.values, (v) => v.rotulo);
    confere(ScenarioBand.values, (v) => v.rotulo);
    confere(ValuationCaveat.values, (v) => v.rotulo);
    confere(TransversalOrdering.values, (v) => v.rotulo);
    confere(MultipleKind.values, (v) => v.rotulo);
    confere(MultipleRefusal.values, (v) => v.rotulo);
    confere(PortfolioKind.values, (v) => v.rotulo);
  });

  test('a tela lê o que lia antes da mudança', () {
    // O texto não mudou de lugar para mudar de redação: quem decide a
    // redação agora é a tela, e esta é a de 22/09/2026.
    expect(ValuationModel.dcfFcff.rotulo, 'DCF por fluxo da firma');
    expect(ScenarioBand.bear.rotulo, 'Pessimista');
    expect(MultipleKind.firmaEbitda.rotulo, 'EV/EBITDA');
    expect(PortfolioKind.reserva.rotulo, 'Reserva');
  });
}
