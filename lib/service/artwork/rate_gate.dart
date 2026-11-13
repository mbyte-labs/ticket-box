/// A token bucket that spaces requests to the image CDN: [permitsPerSecond] on average, with up to
/// [burst] of them at once after an idle spell.
///
/// Each [acquire] reserves the next free slot and waits for it, so concurrent callers queue in
/// order instead of all seeing "a token is free" at the same instant.
class RateGate {
  final int permitsPerSecond;
  final int burst;
  final bool _unlimited;

  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);

  RateGate({this.permitsPerSecond = 8, this.burst = 8}) : _unlimited = false, assert(permitsPerSecond > 0), assert(burst > 0);

  /// A gate that never waits, for tests.
  RateGate.unlimited() : permitsPerSecond = 0, burst = 0, _unlimited = true;

  Duration get _interval => Duration(microseconds: Duration.microsecondsPerSecond ~/ permitsPerSecond);

  Future<void> acquire() {
    if (_unlimited) {
      return Future.value();
    }
    final now = DateTime.now();
    final floor = now.subtract(_interval * burst);
    final slot = _nextSlot.isAfter(floor) ? _nextSlot : floor;
    _nextSlot = slot.add(_interval);
    final wait = slot.difference(now);
    return wait <= Duration.zero ? Future.value() : Future<void>.delayed(wait);
  }
}
