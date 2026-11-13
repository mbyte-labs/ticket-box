import 'package:ticketbox/common/model/item_type.dart';

/// The Favorites page's type filter. Applied from the page's Filters panel, never persisted: the
/// list is small and the page always opens on everything.
enum FavoritesFilter {
  everything,
  movies,
  shows;

  /// The item types the filter lets through — the `type IN (...)` of the repository query.
  List<ItemType> get types => switch (this) {
    everything => const [ItemType.movie, ItemType.show],
    movies => const [ItemType.movie],
    shows => const [ItemType.show],
  };

  String get label => switch (this) {
    everything => 'Everything',
    movies => 'Movies',
    shows => 'Shows',
  };
}
