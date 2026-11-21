/// Sealed domain and infrastructure failure hierarchy for Commander Chess 3D.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() {
    final codePart = code == null ? '' : '[$code] ';
    return '$runtimeType($codePart$message)';
  }
}

final class NetworkAppFailure extends AppFailure {
  const NetworkAppFailure(
    super.message, {
    super.code,
    super.cause,
    this.mayHaveCommitted = false,
  });

  final bool mayHaveCommitted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkAppFailure &&
          other.message == message &&
          other.code == code &&
          other.cause == cause &&
          other.mayHaveCommitted == mayHaveCommitted);

  @override
  int get hashCode =>
      Object.hash(NetworkAppFailure, message, code, cause, mayHaveCommitted);
}

final class ValidationAppFailure extends AppFailure {
  const ValidationAppFailure(
    super.message, {
    super.code,
    super.cause,
    this.fieldErrors = const {},
  });

  final Map<String, String> fieldErrors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValidationAppFailure &&
          other.message == message &&
          other.code == code &&
          other.cause == cause &&
          _mapEquals(other.fieldErrors, fieldErrors));

  @override
  int get hashCode => Object.hash(
        ValidationAppFailure,
        message,
        code,
        cause,
        Object.hashAllUnordered(
          fieldErrors.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

final class AuthAppFailure extends AppFailure {
  const AuthAppFailure(super.message, {super.code, super.cause});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthAppFailure &&
          other.message == message &&
          other.code == code &&
          other.cause == cause);

  @override
  int get hashCode => Object.hash(AuthAppFailure, message, code, cause);
}

final class ServerAppFailure extends AppFailure {
  const ServerAppFailure(
    super.message, {
    super.code,
    super.cause,
    this.statusCode,
  });

  final int? statusCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerAppFailure &&
          other.message == message &&
          other.code == code &&
          other.cause == cause &&
          other.statusCode == statusCode);

  @override
  int get hashCode =>
      Object.hash(ServerAppFailure, message, code, cause, statusCode);
}

final class RulesViolationFailure extends AppFailure {
  const RulesViolationFailure(super.message, {super.code, super.cause});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RulesViolationFailure &&
          other.message == message &&
          other.code == code &&
          other.cause == cause);

  @override
  int get hashCode =>
      Object.hash(RulesViolationFailure, message, code, cause);
}
