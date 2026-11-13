import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/discover/discover_params.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_page.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';
import 'package:ticketbox/common/model/item_type.dart';

/// `/3/discover/{movie|tv}`, sorted by [TmdbDiscoverParams.sort] and filtered by the rest of
/// [TmdbDiscoverParams].
///
/// Documentation: https://developer.themoviedb.org/reference/discover-movie
class TmdbDiscoverApi {
  static final _log = Logger('[API] [Tmdb] TmdbDiscoverApi');
  static final _singleton = TmdbDiscoverApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbDiscoverApi._internal();

  factory TmdbDiscoverApi() {
    return _singleton;
  }

  Future<TmdbPage<TmdbMovieListItem>> movies(int page, TmdbDiscoverParams params) async {
    final uri = tmdbUri('/3/discover/movie', {'include_adult': 'false', 'page': '$page', ...params.toQuery(ItemType.movie)});
    _log.finer('Discovering movies, page $page, query ${params.toQuery(ItemType.movie)}');

    final json = await tmdbGetJsonMap(_client, uri, _log, 'discover movies');
    return TmdbPage.fromJson(json, TmdbMovieListItem.fromJson);
  }

  /// `include_null_first_air_dates=false` drops the unannounced entries that would otherwise
  /// surface as blank cards at the top of a popularity sort.
  Future<TmdbPage<TmdbShowListItem>> shows(int page, TmdbDiscoverParams params) async {
    final uri = tmdbUri('/3/discover/tv', {
      'include_adult': 'false',
      'include_null_first_air_dates': 'false',
      'page': '$page',
      ...params.toQuery(ItemType.show),
    });
    _log.finer('Discovering shows, page $page, query ${params.toQuery(ItemType.show)}');

    final json = await tmdbGetJsonMap(_client, uri, _log, 'discover shows');
    return TmdbPage.fromJson(json, TmdbShowListItem.fromJson);
  }
}
