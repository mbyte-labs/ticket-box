import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/filter/genres/genre.dart';
import 'package:ticketbox/common/model/filter/rating/rating_range.dart';
import 'package:ticketbox/common/model/filter/year/year_range.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/discover/discover_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

part 'discover_state.freezed.dart';
part 'discover_state.g.dart';

@freezed
abstract class DiscoverState with _$DiscoverState {
  const DiscoverState._();

  const factory DiscoverState({
    /// Which of the two lists the page is showing. Both keep their loaded pages, so switching
    /// back is instant and costs no refetch.
    required ItemType itemType,
    required DiscoverListState movies,
    required DiscoverListState shows,

    /// The filter panel. Applying its options resets both lists, so neither can keep pages that
    /// were fetched with the previous options.
    required DiscoverFilterPageState filters,
  }) = _DiscoverState;

  factory DiscoverState.initial(ItemType itemType) {
    return DiscoverState(
      itemType: itemType,
      movies: DiscoverListState.initial(),
      shows: DiscoverListState.initial(),
      filters: DiscoverFilterPageState.initial(),
    );
  }

  /// The list the current [itemType] points at.
  DiscoverListState get active => listFor(itemType);

  DiscoverListState listFor(ItemType type) => type == ItemType.movie ? movies : shows;

  /// `movies` / `shows`, for the page's copy.
  String get itemTypeLabel => itemType == ItemType.movie ? 'movies' : 'shows';
}

/// The paging state of one discover list, independent of the other one.
@freezed
abstract class DiscoverListState with _$DiscoverListState {
  const factory DiscoverListState({
    required bool initialLoading,

    /// The tiles of every page loaded so far, in display order, built from TMDB's list payload
    /// and stamped with the user's marks. Never holds a duplicate key: the grid keys its tiles
    /// by the model's id, and duplicate sibling keys are a hard error.
    required List<PosterModel> models,

    /// The highest 1 based page appended so far, 0 while nothing has been loaded.
    required int loadedPage,

    /// The total number of pages the last response reported, -1 until the first one completes.
    required int totalPages,

    /// True while a further page is being appended - drives the paging footer's spinner.
    required bool isLoadingMore,

    /// True once the last page has been appended, after which no further page is requested.
    required bool hasReachedEnd,

    /// If something goes wrong
    required bool hasError,
    required String message,
  }) = _DiscoverListState;

  factory DiscoverListState.initial() {
    return const DiscoverListState(
      initialLoading: true,
      models: [],
      loadedPage: 0,
      totalPages: -1,
      isLoadingMore: false,
      hasReachedEnd: false,
      hasError: false,
      message: '',
    );
  }
}

/// The filter panel's state. Only the inner [filters] payload is persisted; the panel flags and
/// the genre catalogues are rebuilt on every page open.
@freezed
abstract class DiscoverFilterPageState with _$DiscoverFilterPageState {
  const DiscoverFilterPageState._();

  const factory DiscoverFilterPageState({
    required bool containerExpanded,
    required bool filtersApplied,

    /// The genres known to the local database, per type, for the panel to offer. TMDB's movie
    /// and TV genre catalogues are different id spaces, so they are never mixed. Empty until the
    /// genres have been stored, so never persisted with the options.
    required List<Genre> availableMovieGenres,
    required List<Genre> availableShowGenres,
    required DiscoverFilterOptions filters,
  }) = _DiscoverFilterPageState;

  factory DiscoverFilterPageState.initial() {
    return DiscoverFilterPageState(
      containerExpanded: false,
      filtersApplied: true,
      availableMovieGenres: const [],
      availableShowGenres: const [],
      filters: DiscoverFilterOptions.initial(),
    );
  }

  List<Genre> availableGenresFor(ItemType type) => type == ItemType.movie ? availableMovieGenres : availableShowGenres;
}

/// Everything the Discover page's filter panel can set. Persisted as JSON, so the selection
/// survives an application restart.
@freezed
abstract class DiscoverFilterOptions with _$DiscoverFilterOptions {
  const DiscoverFilterOptions._();

  const factory DiscoverFilterOptions({
    /// Which TMDB list the grid pages through. Stored by name - see [DiscoverMode].
    @Default(DiscoverMode.popular) DiscoverMode mode,

    /// `vote_count.gte` for the top rated list; ignored by the other lists.
    @Default(DiscoverService.defaultMinVoteCount) int minVoteCount,
    @JsonSerializable(explicitToJson: true) required FilterRatingRange ratingRange,
    @JsonSerializable(explicitToJson: true) required FilterYearRange yearRange,

    /// One selection per type, because a movie genre id means something else (or nothing) in
    /// TMDB's TV catalogue. The panel shows and edits the active type's list.
    required List<Genre> selectedMovieGenres,
    required List<Genre> selectedShowGenres,
  }) = _DiscoverFilterOptions;

  factory DiscoverFilterOptions.initial() {
    return DiscoverFilterOptions(
      ratingRange: FilterRatingRange.initial(),
      yearRange: FilterYearRange.initial(),
      selectedMovieGenres: const [],
      selectedShowGenres: const [],
    );
  }

  factory DiscoverFilterOptions.fromJson(Map<String, dynamic> json) => _$DiscoverFilterOptionsFromJson(json);

  List<Genre> selectedGenresFor(ItemType type) => type == ItemType.movie ? selectedMovieGenres : selectedShowGenres;

  DiscoverFilterOptions withSelectedGenres(ItemType type, List<Genre> genres) {
    return type == ItemType.movie ? copyWith(selectedMovieGenres: genres) : copyWith(selectedShowGenres: genres);
  }
}
