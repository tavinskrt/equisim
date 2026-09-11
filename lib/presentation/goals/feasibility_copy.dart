import 'package:equisim_core/equisim_core.dart';

import '../shared/ui_kit.dart';

/// Compõe, para a tela, a frase que explica o veredito de viabilidade.
///
/// **Por que aqui e não no núcleo.** `GoalFeasibility.assess` montava esta
/// prosa inteira — com `toStringAsFixed(2)` embutido —, o que prendia um
/// pacote sem interface à formatação da tela: quem lesse o veredito recebia
/// uma frase pronta e não podia fragmentá-la, reordená-la nem traduzi-la. O
/// núcleo passou a devolver [FeasibilityReason] mais os números, e a decisão
/// de texto voltou para onde ela é revisada junto do resto da interface.
///
/// O formato dos percentuais é o de [Fmt], o mesmo que os cartões vizinhos
/// usam — antes esta frase escrevia `12.34%` enquanto o cartão logo acima
/// escrevia `12,34%`.
abstract final class FeasibilityCopy {
  /// Frase de apoio do cartão de viabilidade.
  ///
  /// - [verdict]: veredito já apurado pelo domínio.
  ///
  /// Cobre os casos de [FeasibilityReason] exaustivamente: acrescentar um caso
  /// lá quebra a compilação aqui, que é o efeito desejado.
  static String of(FeasibilityVerdict verdict) {
    // A taxa só falta no caso `unsolvable`, cuja frase não a cita; o travessão
    // existe para que o `switch` continue exaustivo sem ramo condicional.
    final taxa = verdict.requiredAnnualRate;
    final required = taxa == null ? '—' : Fmt.percent(taxa, decimals: 2);
    final cdi = Fmt.percent(verdict.anchors.riskFreeCagr, decimals: 2);
    final market = Fmt.percent(verdict.anchors.marketCagr, decimals: 2);
    final years = verdict.anchors.observedYears;

    return switch (verdict.reason) {
      FeasibilityReason.unsolvable =>
        'O plano informado não tem solução: revise prazo, aportes e valor '
            'desejado.',
      FeasibilityReason.contributionsAlreadySuffice =>
        'Os aportes sozinhos já superam a meta: não é necessária '
            'rentabilidade alguma.',
      FeasibilityReason.belowRiskFree =>
        'A meta exige $required a.a., abaixo do CDI ($cdi a.a. nos últimos '
            '$years anos). Ela é atingível em renda fixa, sem correr risco de '
            'mercado.',
      FeasibilityReason.withinMarket =>
        'A meta exige $required a.a., dentro do retorno histórico do Ibovespa '
            '($market a.a.).',
      FeasibilityReason.aboveMarket =>
        'A meta exige $required a.a., acima do retorno histórico do Ibovespa '
            '($market a.a.). Depende de superar o mercado de forma '
            'consistente, o que é historicamente pouco frequente.',
      FeasibilityReason.farAboveMarket =>
        'A meta exige $required a.a., mais que o dobro do retorno histórico '
            'do Ibovespa ($market a.a.). Revise prazo, aporte ou valor '
            'desejado.',
      FeasibilityReason.beyondAnyReference => _beyond(
          required: required,
          market: market,
          multiple: verdict.marketMultiple,
        ),
    };
  }

  /// O caso extremo cita o múltiplo — "3,2 vezes" informa mais que "muito
  /// acima". Sem múltiplo apurado (âncora de mercado não positiva), a frase
  /// cai para a forma sem número em vez de escrever `null`.
  static String _beyond({
    required String required,
    required String market,
    required double? multiple,
  }) {
    final vezes = multiple == null
        ? ''
        : ' — ${Fmt.ratio(multiple)} vezes o retorno histórico do Ibovespa '
            '($market a.a.)';
    return 'A meta exige $required a.a.$vezes. Nenhuma carteira diversificada '
        'sustentou esse patamar na janela observada. Ajuste prazo, aporte '
        'mensal ou valor desejado.';
  }
}
