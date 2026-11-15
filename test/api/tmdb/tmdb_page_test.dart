import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_page.dart';
import 'package:ticketbox/api/tmdb/v3/search/search_result.dart';

void main() {
  test('parses paging and every well-formed row', () {
    final page = TmdbPage.fromJson({
      'page': 2,
      'total_pages': 10,
      'total_results': 195,
      'results': [
        {
          'id': 1,
          'title': 'One',
          'release_date': '2001-01-01',
          'vote_average': 7.1,
          'vote_count': 10,
          'popularity': 5,
          'genre_ids': [28],
        },
        {'id': 2, 'title': 'Two'},
      ],
    }, TmdbMovieListItem.fromJson);

    expect(page.page, 2);
    expect(page.totalPages, 10);
    expect(page.totalResults, 195);
    expect(page.hasMore, isTrue);
    expect(page.results.map((m) => m.id), [1, 2]);
    expect(page.results.first.genreIds, [28]);
    expect(page.results.last.voteAverage, 0);
    expect(page.results.last.genreIds, isEmpty);
  });

  test('a malformed row is skipped instead of failing the page', () {
    final page = TmdbPage.fromJson({
      'page': 1,
      'total_pages': 1,
      'total_results': 3,
      'results': [
        {'id': 1, 'name': 'Good'},
        {'name': 'No id'},
        'not even an object',
        {'id': 3, 'name': 'Also good'},
      ],
    }, TmdbShowListItem.fromJson);

    expect(page.results.map((s) => s.id), [1, 3]);
    expect(page.totalResults, 3);
    expect(page.hasMore, isFalse);
  });

  test('a payload without results or paging yields an empty first page', () {
    final page = TmdbPage.fromJson(<String, dynamic>{}, TmdbMovieListItem.fromJson);

    expect(page.page, 1);
    expect(page.totalPages, 0);
    expect(page.results, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('multi search rows map to movie or show and drop persons', () {
    final page = TmdbPage<TmdbSearchResult?>.fromJson({
      'page': 1,
      'total_pages': 1,
      'total_results': 3,
      'results': [
        {'id': 550, 'media_type': 'movie', 'title': 'Fight Club', 'popularity': 60},
        {'id': 287, 'media_type': 'person', 'name': 'Brad Pitt'},
        {'id': 1399, 'media_type': 'tv', 'name': 'Game of Thrones', 'popularity': 500},
      ],
    }, TmdbSearchResult.fromMultiJson).map((result) => result);

    expect(page.results, hasLength(2));
    expect(page.results.first, isA<TmdbMovieSearchResult>());
    expect(page.results.first.tmdbId, 550);
    expect(page.results.first.title, 'Fight Club');
    expect(page.results.last, isA<TmdbShowSearchResult>());
    expect(page.results.last.title, 'Game of Thrones');
    expect(page.results.last.popularity, 500);
  });
}
