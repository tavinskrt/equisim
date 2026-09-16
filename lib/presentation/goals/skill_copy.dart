import 'package:equisim_core/equisim_core.dart';

import '../shared/ui_kit.dart';

/// O que a tela de metas diz sobre o prêmio do retorno esperado (itens B1.0 e
/// B1).
///
/// O retorno esperado da carteira é o `Ke` de cada ativo mais um prêmio pela
/// ordenação. A §0 do plano do motor de referência mediu que o potencial não
/// ordena melhor que o valor patrimonial sobre o preço, e o B1 passou a tirar o
/// prêmio **da ordenação que a validação comprovou** — ou de nenhuma, quando
/// nenhuma passa (decisão 103). **A frase sai da medição empacotada**, e não de
/// texto fixo: ela cita o número, e muda quando a medição mudar.
abstract final class SkillCopy {
  /// A frase do prêmio, ou `null` quando não há o que ressalvar: o prêmio sai
  /// do potencial e o potencial está comprovado.
  ///
  /// - [leitura]: a do pacote; `null` quando ele falta ou está malformado.
  static String? caveat(SkillReading? leitura) {
    if (leitura == null) {
      return 'A habilidade de ordenar ações não veio medida neste aplicativo, e '
          'o retorno esperado ficou sem prêmio: é o Ke de cada ativo.';
    }
    String n(double v) => Fmt.ratio(v, decimals: 2);
    final premio = leitura.premiumOrdering;
    if (premio == TransversalOrdering.potential && leitura.demonstrated) {
      return null;
    }

    final potencial = _sobreOPotencial(leitura, n);
    if (premio == null) {
      return 'Nenhuma ordenação comprovou habilidade nas coortes de validação, '
          'em ${leitura.months} meses — nem o potencial do valuation, nem o valor '
          'patrimonial sobre o preço, nem o composto dos dois com o lucro sobre o '
          'preço. O retorno esperado não leva prêmio: é o Ke de cada ativo. '
          '$potencial';
    }
    final r = leitura.orderings[premio]!;
    return 'O prêmio sobre o Ke sai de ${premio.label}, que ordenou as ações nas '
        'coortes de validação em ${leitura.months} meses: correlação de postos '
        'de ${n(r.ic)}, t corrigido de ${n(r.overlapT)} contra '
        '${n(r.overlapCritical)} exigido. $potencial';
  }

  /// O que a validação mediu do potencial dado o valor patrimonial — a
  /// ressalva do B1.0, que continua valendo enquanto o C1 não aprovar.
  static String _sobreOPotencial(SkillReading l, String Function(double) n) {
    if (l.demonstrated) {
      return 'O potencial do valuation acrescenta ao valor patrimonial sobre o '
          'preço: t corrigido de ${n(l.overlapT)} contra ${n(l.overlapCritical)}.';
    }
    final teste = l.overlapT > l.overlapCritical
        ? 'o que ele acrescenta ao valor patrimonial sobre o preço não passou no '
            'Newey-West: t de ${n(l.neweyWestT)}, contra '
            '${n(SkillReading.neweyWestFloor)} exigido'
        : 'não acrescentou ao valor patrimonial sobre o preço: t corrigido de '
            '${n(l.overlapT)}, contra ${n(l.overlapCritical)} exigido';
    final icP = l.potentialIc, icB = l.bookToMarketIc;
    final pior = icP != null && icB != null && icP < icB
        ? ' ordenou pior que ele — correlação de postos de ${n(icP)} contra '
            '${n(icB)} — e'
        : '';
    return 'O potencial do valuation sozinho não comprovou saber ordenar ações:'
        '$pior $teste.';
  }
}
