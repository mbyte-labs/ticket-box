class InternalException implements Exception {
  /// A message describing the error.
  final String? message;

  InternalException([this.message]);

  @override
  String toString() {
    return '[InternalException] $message';
  }
}
