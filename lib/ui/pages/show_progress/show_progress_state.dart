import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/show_progress_order_by.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_details.dart';

part 'show_progress_state.freezed.dart';
part 'show_progress_state.g.dart';

@freezed
abstract class ShowProgressState with _$ShowProgressState {
  const factory ShowProgressState({
    required bool initialLoading,
    required ShowProgressFilterPageState filters,
    required List<ShowProgressRowDetails> rows,

    /// The shows whose "View more details" section is open.
    required Set<int> expandedShowIds,

    /// The seasons whose episode chips are visible, keyed `'$showId-$season'`.
    required Set<String> expandedSeasonKeys,

    /// The shows whose season data is being loaded right now (spinner under the row).
    required Set<int> loadingSeasonDataIds,

    /// Season/episode details per show, filled lazily on first expansion.
    required Map<int, List<SeasonProgressDetails>> seasonData,

    /// If something goes wrong
    required bool hasError,
    required String message,
  }) = _ShowProgressState;

  factory ShowProgressState.initial() {
    return ShowProgressState(
      initialLoading: true,
      filters: ShowProgressFilterPageState.initial(),
      rows: [],
      expandedShowIds: {},
      expandedSeasonKeys: {},
      loadingSeasonDataIds: {},
      seasonData: {},
      hasError: false,
      message: 'Loading your show progress',
    );
  }
}

@freezed
abstract class ShowProgressFilterPageState with _$ShowProgressFilterPageState {
  const factory ShowProgressFilterPageState({
    required bool containerExpanded,
    required bool filtersApplied,
    @JsonSerializable(explicitToJson: true) required ShowProgressFilterOptions filters,
  }) = _ShowProgressFilterPageState;

  factory ShowProgressFilterPageState.initial() {
    return ShowProgressFilterPageState(containerExpanded: false, filtersApplied: true, filters: ShowProgressFilterOptions.initial());
  }

  factory ShowProgressFilterPageState.fromJson(Map<String, dynamic> json) => _$ShowProgressFilterPageStateFromJson(json);
}

/// Class used to hold all the available filters that are used by the show progress page
@freezed
abstract class ShowProgressFilterOptions with _$ShowProgressFilterOptions {
  const factory ShowProgressFilterOptions({
    required ShowProgressOrderBy orderBy,
    required OrderType orderType,
    required bool hideCompleted,
  }) = _ShowProgressFilterOptions;

  factory ShowProgressFilterOptions.initial() {
    return const ShowProgressFilterOptions(orderBy: ShowProgressOrderBy.lastWatched, orderType: OrderType.descending, hideCompleted: false);
  }

  factory ShowProgressFilterOptions.fromJson(Map<String, dynamic> json) => _$ShowProgressFilterOptionsFromJson(json);
}
