import 'package:equisim_core/equisim_core.dart';

import '../shared/ui_kit.dart';

/// A ressalva da tela de metas sobre o prêmio tirado do potencial (item B1.0).
///
/// O retorno esperado da carteira é o `Ke` de cada ativo mais um prêmio pelo
/// desconto relativo, e esse prêmio sai do potencial. A §0 do plano do motor
/// de referência mediu que o potencial não ordena melhor que o valor
/// patrimonial sobre o preço, e chamou de defeito em produção a tela que o usa
/// sem dizer isso. **A frase sai da medição empacotada**, e não de texto fixo:
/// quando o C1 aprovar, ela some sozinha, e enquanto isso ela cita o número.
abstract final class SkillCopy {
  /// A ressalva, ou `null` quando a habilidade está comprovada pelo critério
  /// da decisão 96.
  ///
  /// - [leitura]: a do pacote; `null` quando ele falta ou está malformado, e
  ///   aí a ressalva diz que a habilidade não foi medida.
  static String? caveat(SkillReading? leitura) {
    const origem = 'O prêmio pelo desconto relativo sai do potencial do '
        'valuation';
    const consequencia = 'A parte do retorno esperado acima do Ke não está '
        'comprovada.';
    if (leitura == null) {
      return '$origem, e a habilidade dele de ordenar ações não veio medida '
          'neste aplicativo. $consequencia';
    }
    if (leitura.demonstrated) return null;

    String n(double v) => Fmt.ratio(v, decimals: 2);
    final pior = leitura.potentialIc < leitura.bookToMarketIc
        ? ' ele ordenou as ações pior que o valor patrimonial sobre o preço '
            '— correlação de postos de ${n(leitura.potentialIc)} contra '
            '${n(leitura.bookToMarketIc)} — e'
        : '';
    // O critério tem duas pernas, e a frase cita a que falhou.
    final teste = leitura.overlapT > leitura.overlapCritical
        ? 'o que ele acrescenta ao valor patrimonial sobre o preço não passou '
            'no Newey-West: t de ${n(leitura.neweyWestT)}, contra '
            '${n(SkillReading.neweyWestFloor)} exigido'
        : 'não acrescentou ao valor patrimonial sobre o preço: t corrigido de '
            '${n(leitura.overlapT)}, contra ${n(leitura.overlapCritical)} '
            'exigido';
    return '$origem, que não comprovou saber ordenar ações. Nas coortes de '
        'validação, em ${leitura.months} meses,$pior $teste. $consequencia';
  }
}
