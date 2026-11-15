import 'package:logging/logging.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';

/// What a tracked item's artwork directory should hold, built from the STORED catalogue (never
/// from one response: a show's manifest covers every season on disk, and the reconciler deletes
/// anything it does not name).
///
/// The set is what the pages render: poster, backdrop, season posters, the stills of episodes
/// that have aired or air within [stillHorizonDays], and the headshots of the first [castLimit]
/// cast members. Galleries are not downloaded; the app has no gallery.
class CatalogArtworkManifests {
  static final _log = Logger('[Service] CatalogArtworkManifests');

  static const int castLimit = 10;
  static const int stillHorizonDays = 7;

  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final EpisodeRepo _episodeRepo;
  final SnapshotDocumentRepo _documents;

  CatalogArtworkManifests({
    MovieRepo? movieRepo,
    ShowRepo? showRepo,
    SeasonRepo? seasonRepo,
    EpisodeRepo? episodeRepo,
    SnapshotDocumentRepo? documents,
  }) : _movieRepo = movieRepo ?? MovieRepo(),
       _showRepo = showRepo ?? ShowRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo(),
       _documents = documents ?? SnapshotDocumentRepo();

  /// Null when the movie is not in the library.
  Future<ArtworkManifest?> forMovie(int tmdbId) async {
    final row = await _movieRepo.get(tmdbId);
    if (row == null) {
      return null;
    }
    final cast = <String>{};
    final json = row.hasSnapshot ? await _documents.getMovie(tmdbId) : null;
    if (json != null) {
      try {
        final snapshot = MovieSnapshot.fromJson(json, fetchedAt: row.fetchedAt, providersRegion: row.watchProvidersRegion);
        cast.addAll(snapshot.cast.take(castLimit).map((person) => person.profilePath).whereType<String>());
      } catch (e) {
        _log.warning('Could not read the cast of movie $tmdbId for its artwork: $e');
      }
    }
    return ArtworkManifest.movie(tmdbId: tmdbId, posterPath: row.posterPath, backdropPath: row.backdropPath, castProfilePaths: cast);
  }

  /// Null when the show is not in the library.
  Future<ArtworkManifest?> forShow(int tmdbId, {DateTime? now}) async {
    final row = await _showRepo.get(tmdbId);
    if (row == null) {
      return null;
    }
    final horizon = ShowProgressQueries.today((now ?? DateTime.now()).add(const Duration(days: stillHorizonDays)));
    final seasons = await _seasonRepo.getAllForShow(tmdbId);
    final episodes = await _episodeRepo.getAllForShow(tmdbId);
    final cast = <String>{};
    final json = row.hasSnapshot ? await _documents.getShow(tmdbId) : null;
    if (json != null) {
      try {
        final snapshot = ShowSnapshot.fromJson(json, fetchedAt: row.fetchedAt, providersRegion: row.watchProvidersRegion);
        cast.addAll(snapshot.cast.take(castLimit).map((person) => person.profilePath).whereType<String>());
      } catch (e) {
        _log.warning('Could not read the cast of show $tmdbId for its artwork: $e');
      }
    }
    return ArtworkManifest.show(
      tmdbId: tmdbId,
      posterPath: row.posterPath,
      backdropPath: row.backdropPath,
      seasonPosterPaths: {for (final season in seasons) season.season: season.posterPath},
      stillPaths: {
        for (final episode in episodes)
          if (episode.airDate != null && episode.airDate!.compareTo(horizon) <= 0) (episode.season, episode.episode): episode.stillPath,
      },
      castProfilePaths: cast,
    );
  }
}
