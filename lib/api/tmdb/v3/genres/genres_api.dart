import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/http/response_decoding.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_genre.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// `/3/genre/{movie|tv}/list` — the id → name table the `genre_ids` of list items resolve against.
///
/// Documentation: https://developer.themoviedb.org/reference/genre-movie-list
class TmdbGenresApi {
  static final _log = Logger('[API] [Tmdb] TmdbGenresApi');
  static final _singleton = TmdbGenresApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbGenresApi._internal();

  factory TmdbGenresApi() {
    return _singleton;
  }

  Future<List<TmdbGenre>> movies() => _get('movie');

  Future<List<TmdbGenre>> shows() => _get('tv');

  Future<List<TmdbGenre>> _get(String kind) async {
    final uri = tmdbUri('/3/genre/$kind/list');
    _log.finer('Downloading $kind genres');

    final json = await tmdbGetJsonMap(_client, uri, _log, '$kind genres');
    final rows = json['genres'];
    return buildRowsTolerantly(rows is List ? rows : const <dynamic>[], TmdbGenre.fromJson, _log, '$kind genre');
  }
}
