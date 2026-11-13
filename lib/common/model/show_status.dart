/// A show's airing status as TMDB reports it (`status` on `/tv/{id}`).
///
/// Persisted by [name] in `ShowSummaries.status`; anything TMDB adds later degrades to [unknown].
enum ShowStatus {
  returningSeries('Returning Series'),
  inProduction('In Production'),
  planned('Planned'),
  pilot('Pilot'),
  canceled('Canceled'),
  ended('Ended'),
  unknown('Unknown');

  const ShowStatus(this.label);

  /// Human readable label; coincides with TMDB's wire value.
  final String label;

  /// Parses TMDB's `status` string. Case-insensitive, null/unknown → [unknown].
  static ShowStatus fromTmdb(String? value) {
    if (value == null) {
      return ShowStatus.unknown;
    }
    final normalized = value.trim().toLowerCase();
    return ShowStatus.values.firstWhere((status) => status.label.toLowerCase() == normalized, orElse: () => ShowStatus.unknown);
  }

  /// Parses the enum name stored in the database.
  static ShowStatus fromName(String? name) {
    if (name == null) {
      return ShowStatus.unknown;
    }
    return ShowStatus.values.firstWhere((status) => status.name == name, orElse: () => ShowStatus.unknown);
  }

  /// Whether no further episodes are expected — the show has ended or was canceled.
  bool get isConcluded => this == ShowStatus.ended || this == ShowStatus.canceled;
}
