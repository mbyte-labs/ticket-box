import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/http/response_decoding.dart';
import 'package:ticketbox/api/tmdb/tmdb_configuration.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/api/tmdb/v3/model/image.dart';
import 'package:ticketbox/api/tmdb/v3/people/model/person_image_response.dart';

/// Queries the TMDB API V3 for people's images and returns their images URLs
/// Documentation: https://developers.themoviedb.org/3/people/get-person-images
class TmdbPeopleImagesApi {
  static final _log = Logger('[API] [Tmdb] TmdbPeopleImagesApi');
  static final _singleton = TmdbPeopleImagesApi._internal();

  final Client _client = TmdbHttpClient.instance;

  TmdbPeopleImagesApi._internal();

  factory TmdbPeopleImagesApi() {
    return _singleton;
  }

  Future<TmdbImage?> getImages(int personTmDbId) async {
    _log.finer('entering method getImages');
    // https://api.themoviedb.org/3/person/{person_id}/images?api_key=<<api_key>>
    final uri = Uri.https(TmDbApi.url, '/3/person/$personTmDbId/images');
    final Response responseData = await _client.get(uri);

    TmdbPersonImageResponse imagesResponse;
    if (responseData.statusCode >= 200 && responseData.statusCode <= 201) {
      final responseJson = decodeJsonMapBody(responseData, ApiProvider.tmdb, 'person images');
      imagesResponse = TmdbPersonImageResponse.fromJson(responseJson);
    } else if (responseData.statusCode == 404) {
      return null;
    } else {
      throw ApiException(ApiProvider.tmdb, responseData.statusCode, responseData.body, "Error downloading person's images");
    }

    List<TmdbImage> allImages = imagesResponse.profiles;
    allImages.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    if (imagesResponse.profiles.isEmpty) {
      return null;
    }
    return imagesResponse.profiles[0];
  }
}
