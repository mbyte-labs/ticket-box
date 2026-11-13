import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/search_item_type_filter.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

part 'search_state.freezed.dart';

/// The search page's state.
///
/// Deliberately has no `fromJson`/`toJson` and no `.g.dart` part: nothing on this page - the
/// query, the item type filter, the loaded pages - survives a restart. The filter resetting to
/// [SearchItemTypeFilter.both] on every app start is a requirement, not an omission.
@freezed
abstract class SearchState with _$SearchState {
  const SearchState._();

  const factory SearchState({
    /// The query the results currently on screen belong to, '' while the page is idle. Text
    /// still sitting in the debounce window lives only in the text field's controller.
    required String query,

    /// The item type the results are restricted to. In memory only, on purpose.
    required SearchItemTypeFilter filter,

    /// True while page one of the current query is in flight. Starts false: the idle page shows
    /// the type-something hint, not a spinner.
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
  }) = _SearchState;

  factory SearchState.initial() {
    return const SearchState(
      query: '',
      filter: SearchItemTypeFilter.both,
      initialLoading: false,
      models: [],
      loadedPage: 0,
      totalPages: -1,
      isLoadingMore: false,
      hasReachedEnd: false,
      hasError: false,
      message: '',
    );
  }

  bool get hasQuery => query.isNotEmpty;
}
