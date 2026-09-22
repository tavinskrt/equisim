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
extension ValuationModelRotulo on ValuationModel {
  String get rotulo => switch (this) {
    ValuationModel.dcfFcff => 'DCF por fluxo da firma',
    ValuationModel.dcfEarnings => 'DCF sobre lucro distribuível',
  };
}

/// O nome da faixa de cenário.
extension ScenarioBandRotulo on ScenarioBand {
  String get rotulo => switch (this) {
    ScenarioBand.bear => 'Pessimista',
    ScenarioBand.base => 'Base',
    ScenarioBand.bull => 'Otimista',
  };
}

/// A ressalva, como oração que completa «o número é frágil porque…».
extension ValuationCaveatRotulo on ValuationCaveat {
  String get rotulo => switch (this) {
    ValuationCaveat.terminalPesado => 'o valor terminal domina o preço justo',
    ValuationCaveat.crescimentoNaoIdentificado =>
      'o crescimento não é identificável no histórico',
    ValuationCaveat.escalaIncerta => 'a base societária publicada é ambígua',
    ValuationCaveat.baseNormalizadaForte =>
      'a base depende de forte correção de um só exercício',
    ValuationCaveat.viaMigrada => 'a via de avaliação mudou no meio do cálculo',
    ValuationCaveat.ponteFragil =>
      'o preço por papel é resíduo de uma subtração frágil',
    ValuationCaveat.viasMescladas => 'o preço justo combina as duas vias',
    ValuationCaveat.baseReconstruida =>
      'o fluxo-base vem do ciclo, e não do exercício observado',
    ValuationCaveat.prazoDeterminado =>
      'o negócio opera sob contrato de prazo determinado',
  };
}

/// A ordenação transversal, como objeto de «o prêmio sai de…».
extension TransversalOrderingRotulo on TransversalOrdering {
  String get rotulo => switch (this) {
    TransversalOrdering.composite =>
      'o composto de potencial, valor patrimonial e lucro sobre o preço',
    TransversalOrdering.bookToMarket => 'o valor patrimonial sobre o preço',
    TransversalOrdering.potential => 'o potencial do valuation',
  };
}

/// A sigla do múltiplo.
extension MultipleKindRotulo on MultipleKind {
  String get rotulo => switch (this) {
    MultipleKind.precoLucro => 'P/L',
    MultipleKind.precoPatrimonio => 'P/VP',
    MultipleKind.firmaEbitda => 'EV/EBITDA',
  };
}

/// Por que a leitura por múltiplo não se aplica.
extension MultipleRefusalRotulo on MultipleRefusal {
  String get rotulo => switch (this) {
    MultipleRefusal.paresInsuficientes => 'pares insuficientes no setor',
    MultipleRefusal.baseNaoPositiva => 'a grandeza de baixo não é positiva',
    MultipleRefusal.baseAusente => 'a grandeza de baixo não está publicada',
    MultipleRefusal.instituicaoFinanceira =>
      'EBITDA não descreve instituição financeira',
    MultipleRefusal.ponteNaoPositiva =>
      'a ponte deixa o acionista em valor não positivo',
  };
}

/// O nome da carteira.
extension PortfolioKindRotulo on PortfolioKind {
  String get rotulo => switch (this) {
    PortfolioKind.principal => 'Principal',
    PortfolioKind.reserva => 'Reserva',
  };
}
