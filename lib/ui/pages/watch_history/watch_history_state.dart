import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/watch_history_item_type_filter.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_entry.dart';

part 'watch_history_state.freezed.dart';
part 'watch_history_state.g.dart';

@freezed
abstract class WatchHistoryState with _$WatchHistoryState {
  const factory WatchHistoryState({
    required bool initialLoading,
    required WatchHistoryFilterPageState filters,

    /// The plays of every page loaded so far, newest first, their posters marked. A rewatched
    /// item appears once per play, but never holds two entries of one `historyId`: the grid keys
    /// its tiles by it, and duplicate sibling keys are a hard error.
    required List<WatchHistoryEntry> entries,

    /// The highest 1 based page appended so far, 0 while nothing has been loaded.
    required int loadedPage,

    /// The total number of pages the last query reported, -1 until the first one completes.
    required int totalPages,

    /// True while a further page is being appended - drives the paging footer's spinner.
    required bool isLoadingMore,

    /// True once the last page has been appended, after which no further page is requested.
    required bool hasReachedEnd,

    /// If something goes wrong
    required bool hasError,
    required String message,
  }) = _WatchHistoryState;

  factory WatchHistoryState.initial() {
    return WatchHistoryState(
      initialLoading: true,
      filters: WatchHistoryFilterPageState.initial(),
      entries: [],
      loadedPage: 0,
      totalPages: -1,
      isLoadingMore: false,
      hasReachedEnd: false,
      hasError: false,
      message: 'Loading your watch history',
    );
  }
}

@freezed
abstract class WatchHistoryFilterPageState with _$WatchHistoryFilterPageState {
  const factory WatchHistoryFilterPageState({
    required bool containerExpanded,
    required bool filtersApplied,
    @JsonSerializable(explicitToJson: true) required WatchHistoryFilterOptions filters,
  }) = _WatchHistoryFilterPageState;

  factory WatchHistoryFilterPageState.initial() {
    return WatchHistoryFilterPageState(containerExpanded: false, filtersApplied: true, filters: WatchHistoryFilterOptions.initial());
  }

  factory WatchHistoryFilterPageState.fromJson(Map<String, dynamic> json) => _$WatchHistoryFilterPageStateFromJson(json);
}

/// The two filters the watch history page exposes.
///
/// There is deliberately no order by or order type: the page is always "most recently watched
/// first", one tile per play, so an ordering choice would only ever be a way to make the list less useful.
@freezed
abstract class WatchHistoryFilterOptions with _$WatchHistoryFilterOptions {
  const factory WatchHistoryFilterOptions({
    required WatchHistoryItemTypeFilter itemTypes,

    /// Never empty - the apply button stays disabled while it is, because an empty `IN ()` is
    /// invalid SQL.
    required List<HistoryAction> actions,
  }) = _WatchHistoryFilterOptions;

  factory WatchHistoryFilterOptions.initial() {
    return const WatchHistoryFilterOptions(
      itemTypes: WatchHistoryItemTypeFilter.both,
      actions: [HistoryAction.scrobble, HistoryAction.checkin, HistoryAction.watch],
    );
  }

  factory WatchHistoryFilterOptions.fromJson(Map<String, dynamic> json) => _$WatchHistoryFilterOptionsFromJson(json);
}
