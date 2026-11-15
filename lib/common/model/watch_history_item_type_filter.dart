import 'package:json_annotation/json_annotation.dart';
import 'package:ticketbox/common/model/item_type.dart';

/// The three way item type choice of the watch history page.
///
/// Modelled as a single enum rather than a `List<ItemType>` so that the invalid states an
/// unconstrained list allows cannot be represented: empty (which would render as `IN ()`, a
/// SQLite syntax error) or holding `show`/`season`, which history rows never use.
enum WatchHistoryItemTypeFilter {
  @JsonValue('both')
  both,
  @JsonValue('episodes')
  episodes,
  @JsonValue('movies')
  movies;

  /// The item types to query the history table for.
  List<ItemType> get types => switch (this) {
    WatchHistoryItemTypeFilter.both => const [ItemType.episode, ItemType.movie],
    WatchHistoryItemTypeFilter.episodes => const [ItemType.episode],
    WatchHistoryItemTypeFilter.movies => const [ItemType.movie],
  };

  String prettyString() => switch (this) {
    WatchHistoryItemTypeFilter.both => 'Everything',
    WatchHistoryItemTypeFilter.episodes => 'Episodes',
    WatchHistoryItemTypeFilter.movies => 'Movies',
  };
}
