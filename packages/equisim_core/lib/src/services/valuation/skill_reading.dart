import '../portfolio/transversal_ordering.dart';

/// Uma ordenação medida nas coortes: o IC médio e o critério da decisão 96.
class OrderingReading {
  /// Correlação de postos média entre a ordenação e o retorno.
  final double ic;

  /// `t` do IC corrigido pela sobreposição das janelas.
  final double overlapT;

  /// Crítico do `t` corrigido, simulado sob a mesma sobreposição.
  final double overlapCritical;

  /// `t` de Newey-West do IC.
  final double neweyWestT;

  /// Declara a leitura.
  const OrderingReading({
    required this.ic,
    required this.overlapT,
    required this.overlapCritical,
    required this.neweyWestT,
  });

  /// O critério da decisão 96: o `t` corrigido acima do crítico dele e o de
  /// Newey-West acima de [SkillReading.neweyWestFloor].
  bool get demonstrated =>
      overlapT > overlapCritical && neweyWestT > SkillReading.neweyWestFloor;
}

/// A habilidade de ordenar medida nas coortes da validação (itens B1.0 e B1).
///
/// Duas perguntas, empacotadas com o aplicativo:
///
/// - **O potencial acrescenta ao book-to-market?** O coeficiente dele
///   condicionado ao B/M, com o `t` corrigido pela sobreposição e o crítico dela
///   ([decisão 96](../../../../../docs/decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)).
///   É o critério do R3, e é o que a ressalva da tela de metas cita.
/// - **Qual ordenação tem habilidade?** O IC do composto, do book-to-market e do
///   potencial, sobre as mesmas observações, e a regra fixada antes de medir que
///   escolhe de qual sai o prêmio do retorno esperado — [premiumOrdering]
///   (decisão 103).
///
/// **É a leitura do motor do dia da medição, e não o veredito do C1**, que é
/// medido com as fases completas.
class SkillReading {
  /// Horizonte do retorno, em meses.
  final int months;

  /// Coortes da regressão.
  final int cohorts;

  /// Coeficiente médio do potencial condicionado ao book-to-market, em posto
  /// normalizado.
  final double conditionalCoefficient;

  /// `t` do coeficiente condicionado, corrigido pela sobreposição.
  final double overlapT;

  /// Crítico do `t` corrigido.
  final double overlapCritical;

  /// `t` de Newey-West do coeficiente condicionado.
  final double neweyWestT;

  /// As ordenações medidas lado a lado.
  final Map<TransversalOrdering, OrderingReading> orderings;

  /// Declara a leitura.
  const SkillReading({
    required this.months,
    required this.cohorts,
    required this.conditionalCoefficient,
    required this.overlapT,
    required this.overlapCritical,
    required this.neweyWestT,
    required this.orderings,
  });

  /// O `t` de Newey-West que a decisão 96 exige junto do corrigido.
  static const double neweyWestFloor = 2;

  /// A ordem em que a regra do B1 procura a ordenação do prêmio: o modelo
  /// transversal declarado, o fator de uma linha e o potencial.
  static const List<TransversalOrdering> premiumPreference = [
    TransversalOrdering.composite,
    TransversalOrdering.bookToMarket,
    TransversalOrdering.potential,
  ];

  /// O critério do R3 pela decisão 96, sobre o potencial dado o B/M.
  bool get demonstrated =>
      overlapT > overlapCritical && neweyWestT > neweyWestFloor;

  /// IC médio do potencial, ou `null` sem a leitura.
  double? get potentialIc => orderings[TransversalOrdering.potential]?.ic;

  /// IC médio do book-to-market, ou `null` sem a leitura.
  double? get bookToMarketIc => orderings[TransversalOrdering.bookToMarket]?.ic;

  /// **A ordenação de que sai o prêmio do retorno esperado**, ou `null` para
  /// nenhuma: a primeira de [premiumPreference] que passa no critério da
  /// decisão 96. Sem nenhuma que passe, não há prêmio — afirmar desconto
  /// relativo como retorno seria afirmar habilidade que a validação não mediu.
  TransversalOrdering? get premiumOrdering {
    for (final o in premiumPreference) {
      if (orderings[o]?.demonstrated ?? false) return o;
    }
    return null;
  }
}

/// Formato do pacote da habilidade, gravado por
/// `tool/regressao_condicional.dart --trimestral` e lido pelo aplicativo.
abstract final class SkillReadingCodec {
  /// Versão do formato: a 2 traz as ordenações lado a lado (item B1).
  static const int versao = 2;

  /// A chave de cada ordenação no pacote.
  static String chave(TransversalOrdering o) => switch (o) {
        TransversalOrdering.composite => 'composto',
        TransversalOrdering.bookToMarket => 'bookToMarket',
        TransversalOrdering.potential => 'potencial',
      };

  /// Lê o pacote, ou `null` se ele estiver malformado — leitura inventada
  /// esconderia a ressalva.
  static SkillReading? decode(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return null;
    final meses = pacote['horizonteMeses'];
    final coortes = pacote['coortes'];
    final dado = pacote['potencialDadoBookToMarket'];
    final ordenacoes = pacote['ordenacoes'];
    if (meses is! int || coortes is! int || dado is! Map || ordenacoes is! Map) {
      return null;
    }
    final coeficiente = dado['coeficiente'];
    final t = dado['tCorrigido'];
    final critico = dado['critico'];
    final nw = dado['tNeweyWest'];
    if (coeficiente is! num || t is! num || critico is! num || nw is! num) {
      return null;
    }
    if (![coeficiente, t, critico, nw].every((v) => v.isFinite)) return null;

    final lidas = <TransversalOrdering, OrderingReading>{};
    for (final o in TransversalOrdering.values) {
      final m = ordenacoes[chave(o)];
      if (m is! Map) return null;
      final ic = m['ic'];
      final tc = m['tCorrigido'];
      final cr = m['critico'];
      final tn = m['tNeweyWest'];
      if (ic is! num || tc is! num || cr is! num || tn is! num) return null;
      if (![ic, tc, cr, tn].every((v) => v.isFinite)) return null;
      lidas[o] = OrderingReading(
        ic: ic.toDouble(),
        overlapT: tc.toDouble(),
        overlapCritical: cr.toDouble(),
        neweyWestT: tn.toDouble(),
      );
    }
    return SkillReading(
      months: meses,
      cohorts: coortes,
      conditionalCoefficient: coeficiente.toDouble(),
      overlapT: t.toDouble(),
      overlapCritical: critico.toDouble(),
      neweyWestT: nw.toDouble(),
      orderings: Map.unmodifiable(lidas),
    );
  }
}
