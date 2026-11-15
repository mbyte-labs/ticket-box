/// The three pieces of user data that can be kept in step with the user's TMDB account.
///
/// The favorites list is mirrored as TMDB **favorites**; the name is TMDB's.
enum TmdbDataSet {
  ratings('Ratings'),
  watchlist('Watchlist'),
  favorites('Favorites');

  /// How the Settings page names the data set.
  final String label;

  const TmdbDataSet(this.label);
}
