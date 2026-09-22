import 'package:equisim_core/equisim_core.dart';

import 'ui_kit.dart';

/// Compõe, para a tela, o texto de uma [Failure] do domínio.
///
/// **Por que existe.** `Failure.message` é diagnóstico técnico — diz quais
/// tickers ficaram sem cotação, quantos pregões sobraram, quanto os pesos
/// somaram. Jogá-lo direto num banner fazia o núcleo decidir o texto da
/// interface: tom, ordem e formatação de número vinham de um pacote que não
/// conhece tela nenhuma.
///
/// Aqui a apresentação decide o **rótulo** a partir do tipo selado e dos
/// campos estruturados, e usa o diagnóstico como detalhe. Nada se perde: o
/// leitor continua vendo qual ativo falhou, agora sob um rótulo que a
/// interface escolheu.
abstract final class FailureCopy {
  /// «Informado: X. Limite: Y.» na unidade que o domínio declarou.
  ///
  /// **A unidade vem do núcleo, e o formato é daqui.** Deduzir o formato pelo
  /// nome do campo seria acoplamento por convenção de string, e quebraria
  /// calado no dia em que alguém renomeasse o campo.
  static String _grandeza(double actual, double? limit, QuantityUnit unit) {
    String escrever(double v) => switch (unit) {
          QuantityUnit.fraction => Fmt.percent(v, decimals: 1),
          // Contagem é grandeza inteira: escrevê-la com casa decimal seria
          // sugerir meio ativo.
          QuantityUnit.count => v.round().toString(),
          QuantityUnit.currency => Fmt.money(v),
        };
    final informado = 'Informado: ${escrever(actual)}.';
    return limit == null ? informado : '$informado Limite: ${escrever(limit)}.';
  }

  /// Rótulo curto da natureza da falha, para cabeçalho de banner.
  ///
  /// `switch` exaustivo sobre o tipo selado: acrescentar uma variante de
  /// [Failure] quebra a compilação aqui, e não passa despercebido.
  static String titleOf(Failure failure) => switch (failure) {
        InsufficientData() => 'Dados insuficientes',
        InvalidInput() => 'Entrada inválida',
        ComputationFailure() => 'Cálculo não concluído',
        DataQualityFailure() => 'Dado sob ressalva',
      };

  /// Frase completa: rótulo, o assunto quando ele existe, e o diagnóstico.
  ///
  /// - [failure]: falha vinda do domínio.
  ///
  /// O assunto de [InsufficientData] entra no rótulo — "Dados insuficientes ·
  /// PETR4" — porque é o que permite ao leitor agrupar falhas por ativo sem
  /// ler a frase inteira. O desvio de [DataQualityFailure] e a grandeza de
  /// [InvalidInput] entram formatados pela mesma `Fmt` das outras telas.
  static String of(Failure failure) {
    final detail = switch (failure) {
      DataQualityFailure(:final observedDeviation)
          when observedDeviation != null =>
        '${failure.message} Desvio medido: '
            '${Fmt.percent(observedDeviation, decimals: 1)}.',
      // **A grandeza vem do domínio, e a frase é montada aqui** (item B21,
      // decisão 122). O núcleo diz quanto e contra quanto; quem escolhe casas
      // decimais, ordem e palavras é a tela.
      InvalidInput(:final actual, :final limit, :final unit)
          when actual != null && unit != null =>
        '${failure.message} ${_grandeza(actual, limit, unit)}',
      _ => failure.message,
    };

    final subject = switch (failure) {
      InsufficientData(:final subject) => subject,
      _ => null,
    };

    final head = subject == null
        ? titleOf(failure)
        : '${titleOf(failure)} · $subject';
    return '$head — $detail';
  }
}
