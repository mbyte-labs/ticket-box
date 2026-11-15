import 'package:ticketbox/api/tmdb/v3/movie/movie_details.dart';
import 'package:ticketbox/common/converter/show.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/movie_status.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';

class MovieConverter {
  /// The movie row from a `/movie/{id}` snapshot body.
  ///
  /// [fetchedAt] stamps the snapshot's freshness; [trackedAt] is when the movie entered the library
  /// (the existing row's value on a refresh). [providersRegion] records which country the stored
  /// `watch/providers` was pruned to.
  static MovieEntity fromDetails(
    TmdbMovieDetails details, {
    required DateTime fetchedAt,
    required DateTime trackedAt,
    required String? providersRegion,
    String certificationRegion = 'US',
  }) {
    final runtime = details.runtime;
    return MovieEntity.build(
      tmdbId: details.id,
      imdbId: details.imdbId ?? details.externalIds?.imdbId,
      title: details.title,
      year: tmdbYearOrNull(details.releaseDate),
      overview: details.overview,
      tagline: (details.tagline == null || details.tagline!.trim().isEmpty) ? null : details.tagline,
      releaseDate: _dateOrNull(details.releaseDate),
      runtime: (runtime == null || runtime == 0) ? null : runtime,
      certification: details.releaseDates?.certificationForCountry(certificationRegion),
      country: details.productionCountries.isEmpty ? null : details.productionCountries.first.iso3166_1,
      language: details.originalLanguage,
      trailer: ShowConverter.youtubeTrailer(details.videos),
      homepage: (details.homepage == null || details.homepage!.trim().isEmpty) ? null : details.homepage,
      voteAverage: details.voteAverage,
      voteCount: details.voteCount,
      popularity: details.popularity,
      genres: details.genres.map((g) => g.id).join(','),
      status: MovieStatus.fromTmdb(details.status).name,
      posterPath: SnapshotPruner.bestImagePath(_imagesJson(details)['posters'], fallback: details.posterPath),
      backdropPath: SnapshotPruner.bestImagePath(_imagesJson(details)['backdrops'], fallback: details.backdropPath),
      fetchedAt: fetchedAt,
      trackedAt: trackedAt,
      watchProvidersRegion: providersRegion,
    );
  }

  static Map<String, List<Map<String, dynamic>>> _imagesJson(TmdbMovieDetails details) {
    final images = details.images;
    if (images == null) {
      return const {};
    }
    return {
      'posters': [
        for (final i in images.posters) {'file_path': i.filePath, 'iso_639_1': i.language, 'vote_average': i.voteAverage},
      ],
      'backdrops': [
        for (final i in images.backdrops) {'file_path': i.filePath, 'iso_639_1': i.language, 'vote_average': i.voteAverage},
      ],
    };
  }

  /// TMDB sends `''` for an unknown date; the column keeps null.
  static String? _dateOrNull(String? value) => (value == null || value.isEmpty) ? null : value;
}
