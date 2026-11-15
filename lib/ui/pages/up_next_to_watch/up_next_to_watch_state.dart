import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/up_next_to_watch_order_by.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

part 'up_next_to_watch_state.freezed.dart';
part 'up_next_to_watch_state.g.dart';

@freezed
abstract class UpNextToWatchState with _$UpNextToWatchState {
  const factory UpNextToWatchState({
    required bool initialLoading,
    required DashboardFilterPageState filters,
    required List<PosterModel> upNext,

    /// If something goes wrong
    required bool hasError,
    required String message,
    required String? namedRouteRedirect,
  }) = _UpNextToWatchState;

  factory UpNextToWatchState.initial() {
    return UpNextToWatchState(
      initialLoading: true,
      filters: DashboardFilterPageState.initial(),
      upNext: [],
      hasError: false,
      message: 'Starting application',
      namedRouteRedirect: null,
    );
  }
}

@freezed
abstract class DashboardFilterPageState with _$DashboardFilterPageState {
  const factory DashboardFilterPageState({
    required bool containerExpanded,
    required bool filtersApplied,
    @JsonSerializable(explicitToJson: true) required DashboardPageFilterOptions filters,
  }) = _DashboardFilterPageState;

  factory DashboardFilterPageState.initial() {
    return DashboardFilterPageState(containerExpanded: false, filtersApplied: true, filters: DashboardPageFilterOptions.initial());
  }

  factory DashboardFilterPageState.fromJson(Map<String, dynamic> json) => _$DashboardFilterPageStateFromJson(json);
}

/// Class used to hold all the available filters that are used by the shows page
@freezed
abstract class DashboardPageFilterOptions with _$DashboardPageFilterOptions {
  const factory DashboardPageFilterOptions({
    required UpNextToWatchOrderBy orderBy,
    required OrderType orderType,
    required bool onlyWithReleaseDate,
    required bool displayAiredOnly,
  }) = _DashboardPageFilterOptions;

  factory DashboardPageFilterOptions.initial() {
    return const DashboardPageFilterOptions(
      orderBy: UpNextToWatchOrderBy.lastWatched,
      orderType: OrderType.descending,
      onlyWithReleaseDate: false,
      displayAiredOnly: false,
    );
  }

  factory DashboardPageFilterOptions.fromJson(Map<String, dynamic> json) => _$DashboardPageFilterOptionsFromJson(json);
}
