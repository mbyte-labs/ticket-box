/// Where an artwork download stands. There is no persisted "running": the worker drains the queue
/// single in-flight, so a crash mid-download leaves the row [pending] and a `.part` file to sweep.
enum AssetJobStatus {
  pending,
  done,
  failed;

  static AssetJobStatus fromName(String name) => AssetJobStatus.values.firstWhere((s) => s.name == name);
}
