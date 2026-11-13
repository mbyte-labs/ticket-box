import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/watchlist_item_type_filter.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

part 'watchlist_state.freezed.dart';
part 'watchlist_state.g.dart';

@freezed
abstract class WatchlistState with _$WatchlistState {
  const factory WatchlistState({
    required bool initialLoading,
    required WatchlistFilterPageState filters,

    /// The tiles of every page loaded so far, in display order, marked. Never holds two tiles
    /// of one key: the grid keys its tiles by the model's id, and duplicate sibling keys are a
    /// hard error.
    required List<PosterModel> models,

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
  }) = _WatchlistState;

  factory WatchlistState.initial() {
    return WatchlistState(
      initialLoading: true,
      filters: WatchlistFilterPageState.initial(),
      models: [],
      loadedPage: 0,
      totalPages: -1,
      isLoadingMore: false,
      hasReachedEnd: false,
      hasError: false,
      message: 'Loading your watchlist',
    );
  }
}

@freezed
abstract class WatchlistFilterPageState with _$WatchlistFilterPageState {
  const factory WatchlistFilterPageState({
    required bool containerExpanded,
    required bool filtersApplied,
    @JsonSerializable(explicitToJson: true) required WatchlistFilterOptions filters,
  }) = _WatchlistFilterPageState;

  factory WatchlistFilterPageState.initial() {
    return WatchlistFilterPageState(containerExpanded: false, filtersApplied: true, filters: WatchlistFilterOptions.initial());
  }

  factory WatchlistFilterPageState.fromJson(Map<String, dynamic> json) => _$WatchlistFilterPageStateFromJson(json);
}

/// The two filters the watchlist page exposes.
///
/// There is deliberately no order by: the watchlist table only records when a row was listed, so
/// the date it was added is the only thing there is to sort on - [orderType] just flips it.
@freezed
abstract class WatchlistFilterOptions with _$WatchlistFilterOptions {
  const factory WatchlistFilterOptions({
    required WatchlistItemTypeFilter itemTypes,

    /// Which end of the "date added" ordering comes first.
    required OrderType orderType,
  }) = _WatchlistFilterOptions;

  factory WatchlistFilterOptions.initial() {
    return const WatchlistFilterOptions(itemTypes: WatchlistItemTypeFilter.both, orderType: OrderType.descending);
  }

  factory WatchlistFilterOptions.fromJson(Map<String, dynamic> json) => _$WatchlistFilterOptionsFromJson(json);
}
