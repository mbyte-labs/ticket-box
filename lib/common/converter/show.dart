import 'package:ticketbox/api/tmdb/v3/model/tmdb_video.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/show_status.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';

class ShowConverter {
  /// The show row from a `/tv/{id}` snapshot body.
  ///
  /// [certificationRegion] picks the content rating; US is TMDB's best-populated list.
  static ShowEntity fromDetails(
    TmdbShowDetails details, {
    required DateTime fetchedAt,
    required DateTime trackedAt,
    required String? providersRegion,
    String certificationRegion = 'US',
  }) {
    final next = details.nextEpisodeToAir;
    return ShowEntity.build(
      tmdbId: details.id,
      imdbId: details.imdbId,
      title: details.name,
      year: tmdbYearOrNull(details.firstAirDate),
      overview: details.overview,
      tagline: _nullIfEmpty(details.tagline),
      firstAirDate: _nullIfEmpty(details.firstAirDate),
      lastAirDate: _nullIfEmpty(details.lastAirDate),
      runtime: details.episodeRunTime.isEmpty ? null : details.episodeRunTime.first,
      certification: details.contentRatings?.forCountry(certificationRegion),
      network: details.networks.isEmpty ? null : details.networks.first.name,
      country: details.originCountry.isEmpty ? null : details.originCountry.first,
      language: details.originalLanguage,
      trailer: youtubeTrailer(details.videos),
      homepage: _nullIfEmpty(details.homepage),
      voteAverage: details.voteAverage,
      voteCount: details.voteCount,
      popularity: details.popularity,
      numberOfSeasons: details.numberOfSeasons,
      nextEpisodeAirDate: _nullIfEmpty(next?.airDate),
      nextEpisodeSeason: next?.seasonNumber,
      nextEpisodeNumber: next?.episodeNumber,
      genres: details.genres.map((g) => g.id).join(','),
      status: ShowStatus.fromTmdb(details.status).name,
      posterPath: SnapshotPruner.bestImagePath(_imagesJson(details)['posters'], fallback: details.posterPath),
      backdropPath: SnapshotPruner.bestImagePath(_imagesJson(details)['backdrops'], fallback: details.backdropPath),
      fetchedAt: fetchedAt,
      trackedAt: trackedAt,
      watchProvidersRegion: providersRegion,
    );
  }

  /// The watch URL of the first official YouTube trailer, falling back to any YouTube trailer,
  /// then any YouTube teaser.
  static String? youtubeTrailer(TmdbVideos? videos) {
    if (videos == null) {
      return null;
    }
    final youtube = videos.results.where((v) => v.site.toLowerCase() == 'youtube').toList();
    TmdbVideo? pick(bool Function(TmdbVideo v) test) {
      for (final video in youtube) {
        if (test(video)) {
          return video;
        }
      }
      return null;
    }

    final video = pick((v) => v.type == 'Trailer' && v.official) ?? pick((v) => v.type == 'Trailer') ?? pick((v) => v.type == 'Teaser');
    return video == null ? null : 'https://www.youtube.com/watch?v=${video.key}';
  }

  static Map<String, List<Map<String, dynamic>>> _imagesJson(TmdbShowDetails details) {
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

  static String? _nullIfEmpty(String? value) => (value == null || value.trim().isEmpty) ? null : value;
}
