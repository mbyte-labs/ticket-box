import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';

part 'lists_state.freezed.dart';

/// What each built-in list card shows. A null count is still loading (or failed to load), and the
/// card then simply has no subtitle. The poster lists hold the artwork of the most recently added
/// items, newest first; items without a poster path are left out, so a list can be empty even
/// when the list itself is not.
@freezed
abstract class ListsState with _$ListsState {
  const factory ListsState({
    required int? watchlistCount,
    required int? droppedCount,
    required int? favoritesCount,
    @Default(<ArtworkRef>[]) List<ArtworkRef> watchlistPosters,
    @Default(<ArtworkRef>[]) List<ArtworkRef> droppedPosters,
    @Default(<ArtworkRef>[]) List<ArtworkRef> favoritesPosters,
  }) = _ListsState;

  factory ListsState.initial() => const ListsState(watchlistCount: null, droppedCount: null, favoritesCount: null);
}
