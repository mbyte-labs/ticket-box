import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_filter.dart';

part 'favorites_state.freezed.dart';

@freezed
abstract class FavoritesState with _$FavoritesState {
  const factory FavoritesState({
    required bool initialLoading,

    /// Which item types the grid shows - the applied filter. Applying a new one reloads the grid.
    @Default(FavoritesFilter.everything) FavoritesFilter filter,

    /// The choice staged in the Filters panel, waiting for Apply Filters. Apply is enabled while it
    /// differs from [filter].
    @Default(FavoritesFilter.everything) FavoritesFilter selectedFilter,

    /// Whether the Filters panel is open.
    @Default(false) bool filterPanelExpanded,

    /// The tiles of the favorites passing [filter], the most recently added first, marked. Never
    /// holds two tiles of one key: the grid keys its tiles by the model's id.
    required List<PosterModel> models,

    /// If something goes wrong
    required bool hasError,
    required String message,
  }) = _FavoritesState;

  factory FavoritesState.initial() {
    return const FavoritesState(initialLoading: true, models: [], hasError: false, message: 'Loading your favorites');
  }
}
