import 'package:json_annotation/json_annotation.dart';
import 'package:ticketbox/common/model/item_type.dart';

/// The three way item type choice of the watchlist page.
///
/// Modelled as a single enum rather than a `List<ItemType>` so that the invalid empty selection an
/// unconstrained list allows - which would render as `IN ()`, a SQLite syntax error - cannot be
/// represented.
enum WatchlistItemTypeFilter {
  @JsonValue('both')
  both,
  @JsonValue('shows')
  shows,
  @JsonValue('movies')
  movies;

  /// The item types to query the watchlist table for.
  ///
  /// A season and an episode are show rows as far as this filter is concerned, so picking [shows]
  /// never hides a watchlisted season or episode - the two types that are easy to forget are on
  /// the list at all.
  List<ItemType> get types => switch (this) {
    WatchlistItemTypeFilter.both => const [ItemType.movie, ItemType.show, ItemType.season, ItemType.episode],
    WatchlistItemTypeFilter.shows => const [ItemType.show, ItemType.season, ItemType.episode],
    WatchlistItemTypeFilter.movies => const [ItemType.movie],
  };

  String prettyString() => switch (this) {
    WatchlistItemTypeFilter.both => 'Everything',
    WatchlistItemTypeFilter.shows => 'Shows',
    WatchlistItemTypeFilter.movies => 'Movies',
  };
}
