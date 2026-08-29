/// Falhas de domínio, modeladas como tipos selados.
///
/// `sealed` permite ao compilador exigir tratamento exaustivo em `switch`,
/// o que impede o padrão clássico de esquecer um caso de erro.
sealed class Failure {
  /// Mensagem já formulada **para o usuário final**, em português.
  ///
  /// Não é log técnico: chega à interface como está. Deve dizer o que faltou e,
  /// quando possível, o que fazer a respeito.
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
