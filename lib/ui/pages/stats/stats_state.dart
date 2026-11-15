import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';

part 'stats_state.freezed.dart';

@freezed
abstract class StatsState with _$StatsState {
  const factory StatsState({
    required bool initialLoading,

    /// The window the page is computed over; the page opens on all time.
    @Default(StatsPeriod.allTime()) StatsPeriod period,

    /// The period picked in the filter panel but not applied yet. Equal to [period] once
    /// applied, which is what disables the Apply button.
    @Default(StatsPeriod.allTime()) StatsPeriod pendingPeriod,

    /// Whether the filter panel is open.
    @Default(false) bool filterExpanded,

    /// The years the selector offers, newest first. Empty (and the selector hidden) until the
    /// first computation finished, or while there is no history and no rating at all.
    @Default([]) List<int> availableYears,

    /// Everything the page renders, null until the first computation finished. Its
    /// `period` can lag behind [period] while a switch is being computed.
    StatsOverview? overview,

    /// Poster and backdrop of the movies and shows the page names, by key. Loaded after the
    /// overview; a title without an entry yet shows placeholders.
    @Default({}) Map<MediaKey, TitleArtwork> artwork,

    /// The highest rated titles as poster tiles, best first, built from their catalogue rows and
    /// stamped with the user's marks. Loaded after the overview; empty until then.
    @Default([]) List<PosterModel> topRated,

    /// If something goes wrong
    required bool hasError,
    required String message,
  }) = _StatsState;

  factory StatsState.initial() {
    return const StatsState(initialLoading: true, hasError: false, message: 'Crunching your numbers');
  }
}
