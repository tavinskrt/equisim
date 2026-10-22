// Rótulos de tela dos enums do núcleo (item B21, decisão 125).
//
// **Por que moram aqui.** Até 22/09/2026 cada enum do núcleo carregava o texto
// que a tela exibia — `ValuationModel.dcfFcff.label` era «DCF por fluxo da
// firma». O núcleo decidia palavra de interface, e a tela que quisesse outra
// redação teria de brigar com o domínio. É a mesma separação que a decisão 122
// fez para o `Failure`: o núcleo diz **o que** é; a apresentação diz **como se
// lê**.
//
// **O `switch` é exaustivo de propósito.** Um valor novo num desses enums
// quebra a compilação aqui, e não sai na tela como `name` cru.
//
// Não importa Flutter: as ferramentas de `tool/` que escrevem relatório usam
// os mesmos rótulos, e continuam rodando com `dart run`.
import 'package:equisim_core/equisim_core.dart';

/// O modelo que produziu o preço justo.
extension ValuationModelLabel on ValuationModel {
  String get label => switch (this) {
    ValuationModel.dcfFcff => 'DCF por fluxo da firma',
    ValuationModel.dcfEarnings => 'DCF sobre lucro distribuível',
  };
}

/// O nome da faixa de cenário, **pelas premissas, e não pelo resultado**
/// (decisão 148).
///
/// Era «Pessimista», «Base» e «Otimista», e o nome prometia um mundo ruim e um
/// bom. A faixa é sensibilidade (decisão 92): crescimento e taxa deslocados
/// juntos. E o «Otimista» podia valer menos que o «Pessimista» — com a empresa
/// rendendo abaixo do custo de capital, crescer destrói valor (item B38).
/// Nomear pelas premissas diz o que foi mexido, e o valor diz o que deu.
extension ScenarioBandLabel on ScenarioBand {
  String get label => switch (this) {
    ScenarioBand.bear => 'Premissas mais duras',
    ScenarioBand.base => 'Premissas do motor',
    ScenarioBand.bull => 'Premissas mais brandas',
  };
}

/// A ressalva, como oração que completa «o número é frágil porque…».
extension ValuationCaveatLabel on ValuationCaveat {
  String get label => switch (this) {
    ValuationCaveat.heavyTerminal => 'o valor terminal domina o preço justo',
    ValuationCaveat.unidentifiedGrowth =>
      'o crescimento não é identificável no histórico',
    ValuationCaveat.uncertainScale => 'a base societária publicada é ambígua',
    ValuationCaveat.strongNormalizedBase =>
      'a base depende de forte correção de um só exercício',
    ValuationCaveat.migratedLane => 'a via de avaliação mudou no meio do cálculo',
    ValuationCaveat.fragileBridge =>
      'o preço por papel é resíduo de uma subtração frágil',
    ValuationCaveat.mergedLanes => 'o preço justo combina as duas vias',
    ValuationCaveat.rebuiltBase =>
      'o fluxo-base vem do ciclo, e não do exercício observado',
    ValuationCaveat.fixedTerm =>
      'o negócio opera sob contrato de prazo determinado',
    ValuationCaveat.stateControl =>
      'o controle é estatal, e o risco do controlador público não está na taxa',
  };
}

/// A ordenação transversal, como objeto de «o prêmio sai de…».
extension TransversalOrderingLabel on TransversalOrdering {
  String get label => switch (this) {
    TransversalOrdering.composite =>
      'o composto de potencial, valor patrimonial e lucro sobre o preço',
    TransversalOrdering.bookToMarket => 'o valor patrimonial sobre o preço',
    TransversalOrdering.potential => 'o potencial do valuation',
  };
}

/// A sigla do múltiplo.
extension MultipleKindLabel on MultipleKind {
  String get label => switch (this) {
    MultipleKind.priceToEarnings => 'P/L',
    MultipleKind.priceToBook => 'P/VP',
    MultipleKind.evToEbitda => 'EV/EBITDA',
  };
}

/// Por que a leitura por múltiplo não se aplica.
extension MultipleRefusalLabel on MultipleRefusal {
  String get label => switch (this) {
    MultipleRefusal.insufficientPeers => 'pares insuficientes no setor',
    MultipleRefusal.nonPositiveBase => 'a grandeza de baixo não é positiva',
    MultipleRefusal.missingBase => 'a grandeza de baixo não está publicada',
    MultipleRefusal.financialInstitution =>
      'EBITDA não descreve instituição financeira',
    MultipleRefusal.nonPositiveBridge =>
      'a ponte deixa o acionista em valor não positivo',
  };
}

/// O grupo de premissas, como degrau de «onde você discorda do motor».
extension ManualGroupLabel on ManualGroup {
  String get label => switch (this) {
    ManualGroup.profit => 'Lucro de partida',
    ManualGroup.growth => 'Crescimento',
    ManualGroup.reinvestment => 'Reinvestimento',
    ManualGroup.rate => 'Taxa de desconto',
    ManualGroup.perpetuity => 'Crescimento na perpetuidade',
    ManualGroup.newCapital => 'Retorno do capital novo',
  };
}

/// Como a perpetuidade do cálculo do usuário foi formada, como fórmula lida.
extension ManualTerminalLabel on ManualTerminal {
  String get label => switch (this) {
    ManualTerminal.neutral => 'lucro do ano 11 ÷ taxa',
    ManualTerminal.advantage => 'Gordon com o retorno do capital novo',
    ManualTerminal.fixedFraction => 'Gordon com a parcela fixa',
    ManualTerminal.contract => 'capital devolvido no fim do contrato',
  };
}
