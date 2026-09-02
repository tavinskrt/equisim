/// Falhas de domínio, modeladas como tipos selados.
///
/// `sealed` permite ao compilador exigir tratamento exaustivo em `switch`,
/// o que impede o padrão clássico de esquecer um caso de erro.
sealed class Failure {
  /// **Diagnóstico técnico**, não texto de tela.
  ///
  /// Diz o que falhou com a precisão que a auditoria e o log precisam — quais
  /// tickers ficaram sem cotação, qual pesos somaram, quantos pregões
  /// sobraram. É a única forma de a falha carregar essa especificidade, e por
  /// isso segue em português e legível.
  ///
  /// **Quem compõe a frase da interface é a camada de apresentação**, a partir
  /// do tipo selado e dos campos estruturados de cada variante — ver
  /// `FailureCopy`, em `lib/presentation/shared/`. O núcleo não decide
  /// hierarquia de texto, tom nem formatação de número: isso é decisão de
  /// tela, e mantê-la aqui prendia a UI a uma frase pronta que ela não podia
  /// fragmentar.
  final String message;

  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Dados insuficientes ou ausentes para executar o cálculo.
final class InsufficientData extends Failure {
  /// O que ficou sem dado — normalmente o ticker, para a interface agrupar as
  /// falhas por ativo em vez de listar mensagens soltas.
  final String? subject;

  const InsufficientData(super.message, {this.subject});
}

/// Entrada do usuário viola uma invariante do domínio.
final class InvalidInput extends Failure {
  /// Campo do formulário a destacar, quando a falha é atribuível a um.
  final String? field;

  const InvalidInput(super.message, {this.field});
}

/// O modelo não converge ou a equação não tem solução no domínio aceitável.
///
/// Distingue-se de [InsufficientData] por não ser corrigível com mais dados: os
/// dados existem, e é o modelo que não se aplica a eles.
final class ComputationFailure extends Failure {
  const ComputationFailure(super.message);
}

/// Os dados existem mas não passam no controle de qualidade
/// (ex.: DY calculado divergente do publicado pela fonte).
final class DataQualityFailure extends Failure {
  /// Desvio medido em fração (`0.12` para 12%), quando o portão de qualidade
  /// consegue quantificá-lo. Permite à interface dizer *quanto* divergiu em
  /// vez de apenas *que* divergiu.
  final double? observedDeviation;

  const DataQualityFailure(super.message, {this.observedDeviation});
}
