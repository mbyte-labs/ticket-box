import 'dart:convert';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/api_keys.dart';
import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/api/error.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/omdb/item_details.dart';

/// Queries the OMDB API for general details about movies, shows and episodes
/// Documentation: http://www.omdbapi.com/
class OmdbDetailsApi {
  static final _log = Logger('[API-Omdb] OmdbDetailsApi');
  static final _singleton = OmdbDetailsApi._internal();
  static const String omdbUrl = 'www.omdbapi.com';

  /// Free-tier key (~1000 requests/day) shared by every install of the app. Callers must cache
  /// aggressively (see ExternalRatingService's 14-day TTL) and treat failures as "no data".
  static const String omdbApiKey = ApiKeysProvider.omdbKey;

  final Client _client;

  // http://www.omdbapi.com/?apikey=<<api_key>>&i=<<imdb_id>>
  // http://www.omdbapi.com/?apikey=<<api_key>>&i=<<show_imdb_id>>&Season=<<season>>&Episode=<<episode>>

  OmdbDetailsApi._internal() : _client = Client();

  /// A separate instance over [client] — tests hand in a `MockClient`. The app uses the singleton.
  OmdbDetailsApi.withClient(Client client) : _client = client;

  factory OmdbDetailsApi() {
    return _singleton;
  }

  /// The title with the given IMDb id — movie, show or episode alike. Null when OMDb knows no
  /// such id; throws on transport errors and non-200 statuses.
  Future<OmdbItemModel?> get(String imdbId, [bool fullDetails = false]) {
    return _request({'i': imdbId, if (fullDetails) 'plot': 'full'});
  }

  /// One episode of the show with [showImdbId]. OMDb addresses episodes through their show plus
  /// the season and episode numbers; the answer carries the episode's own `imdbID`.
  Future<OmdbItemModel?> getEpisode(String showImdbId, int season, int episode) {
    return _request({'i': showImdbId, 'Season': '$season', 'Episode': '$episode'});
  }

  Future<OmdbItemModel?> _request(Map<String, String> query) async {
    final uri = Uri.https(omdbUrl, '', {'apikey': omdbApiKey, ...query});
    final Response responseData = await _client
        .get(uri)
        .onError((error, stackTrace) => throw ApiClientError(ApiProvider.omdb, 'Error downloading IMDB rating: $error'));

    if (responseData.statusCode != 200) {
      throw ApiException(ApiProvider.omdb, responseData.statusCode, responseData.body, "Error downloading OMDB item's details");
    }

    final responseJson = json.decode(responseData.body) as Map<String, dynamic>;
    // An unknown id is HTTP 200 with `"Response": "False"` — the string, never the boolean.
    final Object? response = responseJson['Response'];
    if (response == false || response == 'False') {
      _log.warning('OMDb has nothing for ${query['i']}: ${responseData.body}');
      return null;
    }
    return OmdbItemModel.fromJson(responseJson);
  }
}
