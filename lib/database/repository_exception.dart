class RepositoryException implements Exception {
  /// A message describing the error.
  final String? message;

  RepositoryException([this.message]);

  @override
  String toString() {
    return '[RepositoryException] $message';
  }
}

class RepositoryConnectionException implements Exception {
  /// A message describing the error.
  final String? message;

  RepositoryConnectionException([this.message]);

  @override
  String toString() {
    return '[RepositoryConnectionException] $message';
  }
}

class MultipleResultsRepositoryException implements Exception {
  /// A message describing the error.
  final String? message;

  MultipleResultsRepositoryException([this.message]);

  @override
  String toString() {
    return '[MultipleResultsRepositoryException] $message';
  }
}
