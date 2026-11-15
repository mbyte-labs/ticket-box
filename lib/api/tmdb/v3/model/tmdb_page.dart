import 'package:logging/logging.dart';
import 'package:ticketbox/api/http/response_decoding.dart';

/// One page of a TMDB list endpoint (`search`, `discover`, `trending`, `recommendations`, ...).
///
/// Hand-written rather than generated because the item type is generic: [TmdbPage.fromJson] takes
/// the item parser and builds rows tolerantly, so one malformed row is dropped instead of killing
/// the whole page. TMDB caps `page` at 500 and `total_pages` at 500 for every list endpoint.
class TmdbPage<T> {
  static final _log = Logger('[API] [Tmdb] TmdbPage');

  final int page;
  final int totalPages;
  final int totalResults;
  final List<T> results;

  const TmdbPage({required this.page, required this.totalPages, required this.totalResults, required this.results});

  const TmdbPage.empty() : page = 1, totalPages = 0, totalResults = 0, results = const [];

  bool get hasMore => page < totalPages;

  factory TmdbPage.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic> row) parseItem) {
    final rawResults = json['results'];
    final rows = rawResults is List ? rawResults : const <dynamic>[];
    return TmdbPage(
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      totalResults: (json['total_results'] as num?)?.toInt() ?? 0,
      results: buildRowsTolerantly(rows, parseItem, _log, 'TmdbPage<$T>'),
    );
  }

  /// Same paging, items transformed (or dropped when [convert] returns null).
  TmdbPage<R> map<R>(R? Function(T item) convert) {
    final converted = <R>[];
    for (final item in results) {
      final result = convert(item);
      if (result != null) {
        converted.add(result);
      }
    }
    return TmdbPage(page: page, totalPages: totalPages, totalResults: totalResults, results: converted);
  }
}
