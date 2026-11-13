/// Lifecycle of a background job tracked in the `jobStates` table.
enum JobState {
  /// Never run on this device
  idle,
  running,
  failed,
  finished,
}
