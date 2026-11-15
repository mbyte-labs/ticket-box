/// A movie's release status as TMDB reports it (`status` on `/movie/{id}`).
///
/// Persisted by [name] in `MovieSummaries.status`; anything TMDB adds later degrades to [unknown].
enum MovieStatus {
  rumored('Rumored'),
  planned('Planned'),
  inProduction('In Production'),
  postProduction('Post Production'),
  released('Released'),
  canceled('Canceled'),
  unknown('Unknown');

  const MovieStatus(this.label);

  /// Human readable label; coincides with TMDB's wire value.
  final String label;

  static MovieStatus fromTmdb(String? value) {
    if (value == null) {
      return MovieStatus.unknown;
    }
    final normalized = value.trim().toLowerCase();
    return MovieStatus.values.firstWhere((status) => status.label.toLowerCase() == normalized, orElse: () => MovieStatus.unknown);
  }

  static MovieStatus fromName(String? name) {
    if (name == null) {
      return MovieStatus.unknown;
    }
    return MovieStatus.values.firstWhere((status) => status.name == name, orElse: () => MovieStatus.unknown);
  }
}
