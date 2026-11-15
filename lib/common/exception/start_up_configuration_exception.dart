class StartUpConfigurationException implements Exception {
  /// A message describing the error.
  final String? message;

  StartUpConfigurationException([this.message]);

  @override
  String toString() {
    return '[StartUpConfigurationException] $message';
  }
}
