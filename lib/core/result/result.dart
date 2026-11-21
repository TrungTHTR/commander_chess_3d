import 'app_failure.dart';

/// Discriminated union representing either a success value [Ok] or an [Err].
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final data) => data,
        Err<T>() => null,
      };

  AppFailure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  R when<R>({
    required R Function(T data) ok,
    required R Function(AppFailure failure) err,
  });
}

final class Ok<T> extends Result<T> {
  const Ok(this.data);

  final T data;

  @override
  R when<R>({
    required R Function(T data) ok,
    required R Function(AppFailure failure) err,
  }) =>
      ok(data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T> && other.data == data);

  @override
  int get hashCode => Object.hash(Ok, data);

  @override
  String toString() => 'Ok($data)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final AppFailure failure;

  @override
  R when<R>({
    required R Function(T data) ok,
    required R Function(AppFailure failure) err,
  }) =>
      err(failure);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T> && other.failure == failure);

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
