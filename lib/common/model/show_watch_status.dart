/// The one stored label of a show's watch state, system-maintained except for [dropped].
///
/// A `show_states` row exists iff the show has at least one episode play (then [watching] or
/// [watched], recomputed from the episode catalogue and the watch log after every write) or the
/// user dropped it. [dropped] is the only value the user sets, and it is sticky: the recompute
/// carries it through unchanged until the user un-drops the show.
enum ShowWatchStatus {
  watching,
  watched,
  dropped;

  static ShowWatchStatus fromName(String name) => ShowWatchStatus.values.firstWhere((s) => s.name == name);
}
