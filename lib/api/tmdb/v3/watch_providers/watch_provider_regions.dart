import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/http/response_decoding.dart';
import 'package:ticketbox/api/tmdb/tmdb_configuration.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/model.dart';

/// Queries the TMDB API V3 for available provider regions
///
/// Documentation: https://developers.themoviedb.org/3/watch-providers/get-available-regions
class TmdbWatchProviderRegionsApi {
  static final _log = Logger('[API] [Tmdb] TmdbWatchProviderRegionsApi');
  static final _singleton = TmdbWatchProviderRegionsApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbWatchProviderRegionsApi._internal();

  factory TmdbWatchProviderRegionsApi() {
    return _singleton;
  }

  Future<List<TmdbAvailableProviderRegion>> getAvailable() async {
    _log.fine('Downloading available watch providers regions');
    final uri = Uri.https(TmDbApi.url, '/3/watch/providers/regions');
    final Response responseData = await _client.get(uri);

    if (responseData.statusCode == 200) {
      final responseJson = decodeJsonMapBody(responseData, ApiProvider.tmdb, 'watch provider regions');
      return _fromJson(responseJson['results'] as List<dynamic>);
    } else {
      throw ApiException(ApiProvider.tmdb, responseData.statusCode, responseData.body, 'Error downloading available provider regions');
    }
  }

  List<TmdbAvailableProviderRegion> _fromJson(List<dynamic> json) {
    List<TmdbAvailableProviderRegion> availableRegions = [];
    for (final regionRaw in json) {
      final region = regionRaw as Map<String, dynamic>;
      availableRegions.add(
        TmdbAvailableProviderRegion(
          iso3166_1: region['iso_3166_1'],
          englishName: region['english_name'],
          nativeName: region['native_name'],
        ),
      );
    }

    return availableRegions;
  }
}
