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
  /// ler a frase inteira. O desvio de [DataQualityFailure] entra formatado
  /// pela mesma `Fmt` das outras telas.
  static String of(Failure failure) {
    final detail = switch (failure) {
      DataQualityFailure(:final observedDeviation)
          when observedDeviation != null =>
        '${failure.message} Desvio medido: '
            '${Fmt.percent(observedDeviation, decimals: 1)}.',
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
