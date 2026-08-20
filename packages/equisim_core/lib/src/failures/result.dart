import 'failure.dart';

/// Resultado de uma operação que pode falhar, sem usar exceções para
/// fluxo de controle esperado.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Valor, ou `null` se for falha.
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
  T unwrap() => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw StateError('unwrap() em Err: $failure'),
      };

  T getOrElse(T fallback) => valueOrNull ?? fallback;

  Result<R> map<R>(R Function(T) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final failure) => Err<R>(failure),
      };

  Result<R> flatMap<R>(Result<R> Function(T) transform) => switch (this) {
        Ok<T>(:final value) => transform(value),
        Err<T>(:final failure) => Err<R>(failure),
      };

  R fold<R>(R Function(T) onOk, R Function(Failure) onErr) => switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);

  @override
  String toString() => 'Err($failure)';
}
