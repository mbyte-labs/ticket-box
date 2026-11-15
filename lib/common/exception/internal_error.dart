class InternalError extends Error {
  final String message;

  InternalError([this.message = 'Something went wrong']);

  @override
  String toString() {
    return 'Internal Error: ${Error.safeToString(message)}';
  }
}
