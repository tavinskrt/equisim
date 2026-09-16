/// A habilidade do potencial medida nas coortes da validação (item B1.0).
///
/// O retorno esperado da meta soma ao `Ke` de cada ativo um prêmio tirado do
/// potencial, e o potencial só vale como ordenador se acrescentar ao
/// book-to-market. Esta é a leitura dessa pergunta, empacotada com o
/// aplicativo: o coeficiente do potencial condicionado ao B/M na regressão
/// transversal de Fama-MacBeth, com o `t` corrigido pela sobreposição das
/// janelas e o crítico simulado dela
/// ([decisão 96](../../../../../docs/decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)).
///
/// **É a leitura do motor do dia da medição, e não o veredito do C1**, que é
/// medido com as fases completas. Enquanto ela não passar no critério, a tela
/// de metas diz que a parte do esperado acima do `Ke` não está comprovada.
class SkillReading {
  /// Horizonte do retorno, em meses.
  final int months;

  /// Coortes da regressão.
  final int cohorts;

  /// Coeficiente médio do potencial condicionado ao book-to-market, em posto
  /// normalizado.
  final double conditionalCoefficient;

  /// `t` do coeficiente corrigido pela sobreposição das janelas.
  final double overlapT;

  /// Crítico do `t` corrigido, simulado sob a mesma sobreposição.
  final double overlapCritical;

  /// `t` de Newey-West do coeficiente.
  final double neweyWestT;

  /// Correlação de postos média entre o potencial e o retorno.
  final double potentialIc;

  /// Correlação de postos média entre o book-to-market e o retorno.
  final double bookToMarketIc;

  /// Declara a leitura.
  const SkillReading({
    required this.months,
    required this.cohorts,
    required this.conditionalCoefficient,
    required this.overlapT,
    required this.overlapCritical,
    required this.neweyWestT,
    required this.potentialIc,
    required this.bookToMarketIc,
  });

  /// O `t` de Newey-West que a decisão 96 exige junto do corrigido.
  static const double neweyWestFloor = 2;

  /// O critério do R3 pela decisão 96: o `t` corrigido acima do crítico dele e
  /// o de Newey-West acima de 2.
  bool get demonstrated =>
      overlapT > overlapCritical && neweyWestT > neweyWestFloor;
}

/// Formato do pacote da habilidade, gravado por
/// `tool/regressao_condicional.dart --trimestral` e lido pelo aplicativo.
abstract final class SkillReadingCodec {
  /// Versão do formato.
  static const int versao = 1;

  /// Lê o pacote, ou `null` se ele estiver malformado — leitura inventada
  /// esconderia a ressalva.
  static SkillReading? decode(Map<String, dynamic> pacote) {
    if (pacote['versao'] != versao) return null;
    final meses = pacote['horizonteMeses'];
    final coortes = pacote['coortes'];
    final dado = pacote['potencialDadoBookToMarket'];
    final icPotencial = pacote['icPotencial'];
    final icBm = pacote['icBookToMarket'];
    if (meses is! int ||
        coortes is! int ||
        dado is! Map ||
        icPotencial is! num ||
        icBm is! num) {
      return null;
    }
    final coeficiente = dado['coeficiente'];
    final t = dado['tCorrigido'];
    final critico = dado['critico'];
    final nw = dado['tNeweyWest'];
    if (coeficiente is! num || t is! num || critico is! num || nw is! num) {
      return null;
    }
    final valores = [coeficiente, t, critico, nw, icPotencial, icBm];
    if (valores.any((v) => !v.isFinite)) return null;
    return SkillReading(
      months: meses,
      cohorts: coortes,
      conditionalCoefficient: coeficiente.toDouble(),
      overlapT: t.toDouble(),
      overlapCritical: critico.toDouble(),
      neweyWestT: nw.toDouble(),
      potentialIc: icPotencial.toDouble(),
      bookToMarketIc: icBm.toDouble(),
    );
  }
}
