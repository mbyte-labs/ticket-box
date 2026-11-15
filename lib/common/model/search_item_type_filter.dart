/// The three way item type choice of the search page.
///
/// Deliberately not persisted anywhere - it lives only in the search page's state and resets to
/// [both] on every app start, so it carries no `@JsonValue` annotations and no key in
/// `PreferenceVersionGuard`. Modelled as a single enum rather than a `List<ItemType>` for the
/// same reason as `WatchHistoryItemTypeFilter`: the invalid states an unconstrained list allows
/// (empty, or holding types search never returns) cannot be represented.
///
/// `SearchService` dispatches on it directly (`/search/multi`, `/search/movie`, `/search/tv`), so
/// there is no wire-value accessor here.
enum SearchItemTypeFilter {
  both,
  movies,
  shows;

  String prettyString() => switch (this) {
    SearchItemTypeFilter.both => 'Everything',
    SearchItemTypeFilter.movies => 'Movies',
    SearchItemTypeFilter.shows => 'Shows',
  };
}
