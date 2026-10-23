/// Transport used by the generated `Http*Repository` classes: sends
/// `<repo>.<method>` with JSON-ready [args] and returns the decoded JSON
/// result. The app implements it over HTTP; tests can call handlers directly.
abstract class RpcClient {
  Future<Object?> call(String method, Map<String, Object?> args);
}

/// Error reported by the server for a failed call.
class RpcException implements Exception {
  RpcException(this.code, this.message);

  /// e.g. `unauthorized`, `forbidden`, `not_found`, `failed`.
  final String code;
  final String message;

  @override
  String toString() => 'RpcException($code): $message';
}
