/// The discover lists for browsing what to watch next: TMDB's `/discover` sorted by popularity
/// ([popular]) or by vote average with a minimum vote count ([topRated]), and
/// `/trending/{movie|tv}/week` ([trending]).
///
/// Lives in `common/model` because both the service layer and the UI dispatch on it, and
/// services must not import anything from `ui/`. The name is persisted inside the discover
/// filter JSON, so renaming a value needs a migration.
enum DiscoverMode {
  popular,
  topRated,
  trending;

  String prettyString() {
    return switch (this) {
      DiscoverMode.popular => 'Popular',
      DiscoverMode.topRated => 'Top rated',
      DiscoverMode.trending => 'Trending',
    };
  }
}
