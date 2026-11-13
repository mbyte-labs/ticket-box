import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/people/model/person_details.dart';
import 'package:ticketbox/api/tmdb/v3/tmdb_request.dart';

/// `/3/person/{id}` with `combined_credits` and `external_ids` appended: everything the person page
/// shows, in one request.
///
/// The credits are the page — the filmography is laid out from this payload alone, with no
/// per-title request behind it — so there is nothing to gain from fetching them separately: the
/// page cannot lay out until both halves are in, and one round trip beats two.
///
/// Documentation: https://developer.themoviedb.org/reference/person-details
class TmdbPersonDetailsApi {
  static final _log = Logger('[API] [Tmdb] TmdbPersonDetailsApi');
  static final _singleton = TmdbPersonDetailsApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbPersonDetailsApi._internal();

  factory TmdbPersonDetailsApi() {
    return _singleton;
  }

  /// Returns `null` when TMDB has no person with that id.
  Future<TmdbPersonDetails?> get(int tmdbId) async {
    final uri = tmdbUri('/3/person/$tmdbId', {'append_to_response': 'combined_credits,external_ids'});
    _log.finer('Downloading person $tmdbId with credits');

    final json = await tmdbGetJsonMapOrNull(_client, uri, _log, 'person $tmdbId');
    return json == null ? null : TmdbPersonDetails.fromJson(json);
  }
}
