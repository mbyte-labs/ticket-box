import 'package:ticketbox/api/tmdb/v3/search/search_api.dart';
import 'package:ticketbox/api/tmdb/v3/search/search_result.dart';
import 'package:ticketbox/common/model/search_item_type_filter.dart';
import 'package:ticketbox/service/browse/browse_entry.dart';

/// One 1 based page of search results: the items in TMDB's relevance order, plus the total page
/// count the response reported.
class SearchPage {
  final int totalPages;
  final List<BrowseEntry> items;

  const SearchPage(this.totalPages, this.items);
}

/// Free-text search against TMDB's catalog. Live on every call, never stored: a search result is
/// not the library's, and a browsed title gets a catalogue row only once the user tracks it.
///
/// TMDB fixes the page size at 20. `/search/multi` also ranks people, which are dropped, so a
/// "both" page can carry fewer rows than that while `totalPages` still counts them.
class SearchService {
  Future<SearchPage> search(String query, SearchItemTypeFilter filter, int page) async {
    final api = TmdbSearchApi();
    final response = switch (filter) {
      SearchItemTypeFilter.both => await api.searchMulti(query, page),
      SearchItemTypeFilter.movies => await api.searchMovies(query, page),
      SearchItemTypeFilter.shows => await api.searchShows(query, page),
    };
    final items = [
      for (final result in response.results)
        switch (result) {
          TmdbMovieSearchResult(:final movie) => BrowseEntry.movie(movie),
          TmdbShowSearchResult(:final show) => BrowseEntry.show(show),
        },
    ];
    return SearchPage(response.totalPages, items);
  }
}
