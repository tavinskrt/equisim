import 'package:equisim_core/equisim_core.dart';

import '../shared/failure_copy.dart';
import '../shared/ui_kit.dart';

/// O texto da tela de edição do valuation (decisão 147).
///
/// **O núcleo diz o que aconteceu; a tela diz como se lê** — a separação das
/// decisões 122 e 125. Os avisos chegam do núcleo como [ManualNoticeKind] com
/// os anos, e as recusas como [InvalidInput] com o campo, o medido e o limite;
/// a frase é montada aqui.
abstract final class ManualCopy {
  /// O nome do campo, na via da avaliação.
  static String label(ManualField field, ValuationLane lane) => switch (field) {
        ManualField.baseProfit => lane == ValuationLane.firm
            ? 'Lucro operacional de partida'
            : 'Lucro líquido de partida',
        ManualField.growth => 'Crescimento nos primeiros anos',
        ManualField.discountRate => 'Taxa de desconto',
        ManualField.perpetualGrowth => 'Crescimento na perpetuidade',
        ManualField.returnOnCapital => lane == ValuationLane.firm
            ? 'Retorno sobre o capital investido'
            : 'Retorno sobre o patrimônio',
        ManualField.retention => 'Parcela do lucro reinvestida',
        ManualField.terminalReturn => 'Retorno do capital novo',
      };

  /// O que o campo é, em uma ou duas frases para quem não sabe finanças.
  static String explanation(ManualField field, ValuationLane lane) =>
      switch (field) {
        ManualField.baseProfit => lane == ValuationLane.firm
            ? 'O lucro da operação depois do imposto e antes dos juros (NOPAT). '
                'A dívida entra depois, no que sobra ao acionista.'
            : 'O lucro do ano de onde a projeção parte.',
        ManualField.growth =>
          'Quanto o lucro cresce no ano 1. Daí em diante, o caminho escolhido '
              'abaixo decide.',
        ManualField.discountRate =>
          'Quanto o acionista exige por ano para ficar com a ação — o custo do '
              'capital próprio. Traz cada fluxo futuro a valor de hoje.',
        ManualField.perpetualGrowth =>
          'Quanto o lucro cresce depois do ano 10, para sempre.',
        ManualField.returnOnCapital => lane == ValuationLane.firm
            ? 'Quanto cada real investido na operação rende por ano. É dele que '
                'sai quanto do lucro precisa ser reinvestido para crescer; até o '
                'ano 10 ele converge ao custo médio do capital do motor.'
            : 'Quanto cada real do patrimônio rende por ano. É dele que sai '
                'quanto do lucro precisa ser reinvestido para crescer; até o ano '
                '10 ele converge à taxa de desconto.',
        ManualField.retention =>
          'A mesma parcela em todos os anos e na perpetuidade. O resto vai ao '
              'acionista.',
        ManualField.terminalReturn =>
          'Quanto rende o dinheiro que a empresa reinveste depois do ano 10. '
              'Igual à taxa, crescer não cria valor — é o que o motor supõe sem '
              'vantagem competitiva comprovada.',
      };

  /// Uma lista de anos como se diz: «3», «3 e 4», «3, 5 e 8», «2 a 10».
  static String years(List<int> years) {
    if (years.isEmpty) return '';
    if (years.length == 1) return 'no ano ${years.first}';
    final consecutive = years.last - years.first == years.length - 1;
    if (consecutive && years.length > 2) {
      return 'do ano ${years.first} ao ${years.last}';
    }
    final all = years.map((a) => '$a').toList();
    return 'nos anos ${all.sublist(0, all.length - 1).join(', ')} e '
        '${all.last}';
  }

  /// O aviso, como frase.
  static String warning(ManualNotice n) => switch (n.kind) {
        ManualNoticeKind.confinedGrowth =>
          '${_capitalize(years(n.years))}, o crescimento ficou abaixo do que você '
              'pediu: com o retorno sobre o capital desses anos, crescer mais '
              'exigiria reinvestir mais de 95% do lucro, e o motor não deixa. '
              'Suba o retorno ou escolha reinvestir uma parcela fixa.',
        ManualNoticeKind.negativeFlow =>
          '${_capitalize(years(n.years))}, o fluxo do acionista é negativo: a '
              'empresa reinveste, ou paga de dívida, mais do que lucra, e '
              'precisaria de dinheiro de fora.',
        ManualNoticeKind.perpetualConcession =>
          'Esta empresa é concessão: no motor, o excedente sobre o capital acaba '
              'no fim do contrato. Com a perpetuidade que você escolheu, ele '
              'passa a durar para sempre.',
        ManualNoticeKind.neutralPerpetuity =>
          'Com o capital novo rendendo a própria taxa, o crescimento na '
              'perpetuidade quase não muda o valor da perpetuidade — ele só guia '
              'o crescimento dos dez anos. Para ele pesar, dê ao capital novo um '
              'retorno diferente da taxa.',
      };

  /// A recusa da conta, como frase. A grandeza vem do núcleo, e o formato é
  /// daqui.
  static String refusal(Failure f) {
    if (f is! InvalidInput) return FailureCopy.of(f);
    final field = ManualField.values.asNameMap()[f.field];
    return switch (field) {
      ManualField.baseProfit =>
        'O lucro de partida precisa ser positivo: o fluxo descontado parte dele.',
      ManualField.retention =>
        'A parcela reinvestida precisa ficar entre 0% e 100%: reinvestir tudo '
            'para sempre não deixa nada ao acionista.',
      ManualField.terminalReturn =>
        'O retorno do capital novo precisa ser positivo.',
      ManualField.growth || ManualField.perpetualGrowth
          when f.limit == -1 =>
        'Um crescimento de −100% ou menos zera o lucro.',
      ManualField.perpetualGrowth => 'A taxa de desconto da perpetuidade '
          'precisa superar o crescimento perpétuo em pelo menos '
          '${Fmt.ratio((f.limit ?? DcfCalculator.minimumSpread) * 100, decimals: 1)} '
          'ponto percentual — a margem está em '
          '${Fmt.ratio((f.actual ?? 0) * 100, decimals: 2)}. Com elas próximas '
          'ou invertidas, a perpetuidade não tem valor finito.',
      ManualField.discountRate =>
        'A taxa de desconto precisa ser positiva em todos os anos.',
      ManualField.growth || ManualField.returnOnCapital || null =>
        FailureCopy.of(f),
    };
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
