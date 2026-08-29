import 'failure.dart';

/// Resultado de uma operação que pode falhar, sem usar exceções para
/// fluxo de controle esperado.
///
/// `sealed` porque o compilador então exige tratamento exaustivo em `switch`:
/// acrescentar um terceiro estado quebraria a compilação de todo consumidor,
/// em vez de escapar silenciosamente por um `default`.
///
/// A convenção do pacote é que **falta de dado e violação de invariante são
/// [Failure], não exceção**. Exceção fica reservada para defeito de
/// programação — divisão por zero em [Money], índice fora de faixa, cast
/// inválido. Quem chama um `Result` decide o que fazer; quem provoca uma
/// exceção tem um bug a corrigir.
sealed class Result<T> {
  const Result();

  /// Sucesso carregando [value].
  const factory Result.ok(T value) = Ok<T>;

  /// Falha carregando [failure].
  const factory Result.err(Failure failure) = Err<T>;

  /// `true` quando é [Ok].
  bool get isOk => this is Ok<T>;

  /// `true` quando é [Err].
  bool get isErr => this is Err<T>;

  /// Valor, ou `null` se for falha.
  ///
  /// **Ambíguo para `T` anulável**: com `Result<double?>`, um `Ok(null)` e um
  /// `Err` devolvem o mesmo `null`. Use [isOk] ou [fold] quando o valor puder
  /// ser nulo legitimamente.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// Falha, ou `null` se for sucesso.
  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  /// Valor, ou lança [StateError]. Use apenas em testes ou após checar [isOk].
  ///
  /// Lança [StateError] quando chamado sobre um [Err], com a falha na mensagem.
  T unwrap() => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw StateError('unwrap() em Err: $failure'),
      };

  /// Valor, ou [fallback] se for falha.
  ///
  /// **Descarta a falha em silêncio.** É a escolha certa quando a ausência do
  /// dado tem um padrão defensável e o motivo não interessa ao usuário — a
  /// lista vazia de proventos de um ativo que nunca pagou, por exemplo. Quando
  /// o motivo importa, use [fold] e reporte.
  T getOrElse(T fallback) => valueOrNull ?? fallback;

  /// Transforma o valor de sucesso, preservando a falha.
  ///
  /// Use quando [transform] **não pode falhar**. Se ela devolve outro [Result],
  /// o resultado seria `Result<Result<R>>` aninhado — nesse caso use [flatMap].
  ///
  /// - [transform]: função aplicada ao valor de um [Ok]. Não é chamada em
  ///   caso de [Err].
  Result<R> map<R>(R Function(T) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final failure) => Err<R>(failure),
      };

  /// Encadeia outra operação que também pode falhar, sem aninhar.
  ///
  /// É [map] para quando [transform] devolve `Result`: a falha de qualquer
  /// etapa da cadeia interrompe as seguintes e chega intacta ao final.
  ///
  /// - [transform]: próxima etapa. Não é chamada em caso de [Err].
  Result<R> flatMap<R>(Result<R> Function(T) transform) => switch (this) {
        Ok<T>(:final value) => transform(value),
        Err<T>(:final failure) => Err<R>(failure),
      };

  /// Colapsa os dois lados num único valor, tratando ambos explicitamente.
  ///
  /// É a forma que **obriga** a lidar com a falha, e por isso a preferida na
  /// fronteira com a interface. Exatamente uma das duas funções é chamada.
  ///
  /// - [onOk]: aplicada ao valor de um [Ok].
  /// - [onErr]: aplicada à falha de um [Err].
  R fold<R>(R Function(T) onOk, R Function(Failure) onErr) => switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };
}

/// Ramo de sucesso de um [Result].
final class Ok<T> extends Result<T> {
  /// O valor produzido pela operação.
  final T value;

  /// Constrói um sucesso carregando [value].
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

/// Ramo de falha de um [Result].
final class Err<T> extends Result<T> {
  /// O motivo da falha, já tipado.
  final Failure failure;

  /// Constrói uma falha carregando [failure].
  ///
  /// O parâmetro de tipo [T] é livre: um `Err<double>` converte para
  /// `Err<String>` por reconstrução em [map] e [flatMap], preservando a falha.
  const Err(this.failure);

  @override
  String toString() => 'Err($failure)';
}
