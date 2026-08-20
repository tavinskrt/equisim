/// Falhas de domínio, modeladas como tipos selados.
///
/// `sealed` permite ao compilador exigir tratamento exaustivo em `switch`,
/// o que impede o padrão clássico de esquecer um caso de erro.
sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Dados insuficientes ou ausentes para executar o cálculo.
final class InsufficientData extends Failure {
  final String? subject;
  const InsufficientData(super.message, {this.subject});
}

/// Entrada do usuário viola uma invariante do domínio.
final class InvalidInput extends Failure {
  final String? field;
  const InvalidInput(super.message, {this.field});
}

/// O modelo não converge ou a equação não tem solução no domínio aceitável.
final class ComputationFailure extends Failure {
  const ComputationFailure(super.message);
}

/// Os dados existem mas não passam no controle de qualidade
/// (ex.: DY calculado divergente do publicado pela fonte).
final class DataQualityFailure extends Failure {
  final double? observedDeviation;
  const DataQualityFailure(super.message, {this.observedDeviation});
}
