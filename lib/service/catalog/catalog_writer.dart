import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';
import 'package:ticketbox/common/converter/movie.dart';
import 'package:ticketbox/common/converter/season.dart';
import 'package:ticketbox/common/converter/show.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_entity.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';

/// A movie as one snapshot write left it.
class WrittenMovie {
  final MovieEntity movie;
  final TmdbMovieDetails details;

  const WrittenMovie(this.movie, this.details);
}

/// A show as one snapshot write left it: the row, the root document and the seasons written this
/// time (not necessarily every season of the show).
class WrittenShow {
  final ShowEntity show;
  final TmdbShowDetails details;
  final List<SeasonEntity> seasons;
  final List<EpisodeEntity> episodes;

  const WrittenShow(this.show, this.details, this.seasons, this.episodes);
}

/// Turns pruned TMDB documents into catalogue rows, one transaction per item: the convenience
/// columns derived by the converters, the verbatim document in `snapshot_documents`, and for a
/// show its season stubs, the fetched seasons' rows and episodes. Artwork is NOT enqueued here —
/// the caller does that after the commit, from the stored catalogue.
class CatalogWriter {
  static final _log = Logger('[Service] CatalogWriter');

  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final EpisodeRepo _episodeRepo;
  final SnapshotDocumentRepo _documents;
  final DatabaseConnectionManager _db;

  CatalogWriter({
    MovieRepo? movieRepo,
    ShowRepo? showRepo,
    SeasonRepo? seasonRepo,
    EpisodeRepo? episodeRepo,
    SnapshotDocumentRepo? documents,
  }) : _movieRepo = movieRepo ?? MovieRepo(),
       _showRepo = showRepo ?? ShowRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo(),
       _documents = documents ?? SnapshotDocumentRepo(),
       _db = DatabaseConnectionInitializer.getConnection();

  /// Writes a movie's row and document. An existing row keeps its `trackedAt`.
  Future<WrittenMovie> writeMovie(Map<String, dynamic> pruned, {required DateTime now, required String? region}) async {
    final details = TmdbMovieDetails.fromJson(pruned);
    final existing = await _movieRepo.get(details.id);
    final entity = MovieConverter.fromDetails(details, fetchedAt: now, trackedAt: existing?.trackedAt ?? now, providersRegion: region);
    await _db.transaction(() async {
      await _movieRepo.insert(entity);
      await _documents.upsert(SnapshotDocumentEntity.movie(details.id, json.encode(pruned)));
    });
    _log.fine('Movie ${details.id}: snapshot written');
    return WrittenMovie(entity, details);
  }

  /// Writes a show's row and root document, the stubs of every season TMDB lists, and the rows,
  /// episodes and documents of the seasons in [seasonDocs] (keyed by season number). Seasons TMDB
  /// no longer lists are removed with their episodes and documents. An existing row keeps its
  /// `trackedAt`; a season not in [seasonDocs] keeps whatever it had.
  Future<WrittenShow> writeShow(
    Map<String, dynamic> root,
    Map<int, Map<String, dynamic>> seasonDocs, {
    required DateTime now,
    required String? region,
  }) async {
    final details = TmdbShowDetails.fromJson(root);
    final showId = details.id;
    final existing = await _showRepo.get(showId);
    final entity = ShowConverter.fromDetails(details, fetchedAt: now, trackedAt: existing?.trackedAt ?? now, providersRegion: region);
    final stubs = details.seasons.map((stub) => SeasonConverter.fromStub(showId, stub)).toList();
    final stubIds = {for (final stub in details.seasons) stub.seasonNumber: stub.id};
    final listed = details.seasons.map((stub) => stub.seasonNumber).toSet();
    final cached = await _seasonRepo.getAllForShow(showId);
    final vanished = cached.where((season) => !listed.contains(season.season)).map((season) => season.season).toList();

    final seasons = <SeasonEntity>[];
    final episodes = <EpisodeEntity>[];
    final documents = <SnapshotDocumentEntity>[];
    for (final entry in seasonDocs.entries) {
      if (!listed.contains(entry.key)) {
        continue;
      }
      final converted = SeasonConverter.fromDetails(
        showId,
        TmdbSeasonDetails.fromJson(entry.value),
        showStatus: entity.statusValue,
        lastSeasonNumber: details.numberOfSeasons,
        fetchedAt: now,
        tmdbSeasonId: stubIds[entry.key],
        showRuntime: entity.runtime,
      );
      seasons.add(converted.season);
      episodes.addAll(converted.episodes);
      documents.add(SnapshotDocumentEntity.season(showId, entry.key, json.encode(entry.value)));
    }

    await _db.transaction(() async {
      await _showRepo.insert(entity);
      await _documents.upsert(SnapshotDocumentEntity.show(showId, json.encode(root)));
      await _seasonRepo.upsertStubs(stubs);
      for (final season in vanished) {
        _log.fine('Show $showId season $season is no longer on TMDB, dropping its rows');
        await _episodeRepo.deleteBySeason(showId, season);
        await _seasonRepo.deleteBySeasonNr(showId, season);
        await _documents.deleteSeason(showId, season);
      }
      await _seasonRepo.replaceSeasons(showId, seasons, episodes);
      await _documents.upsertAll(documents);
    });
    _log.fine('Show $showId: snapshot written with ${seasons.length} season(s), ${episodes.length} episode(s)');
    return WrittenShow(entity, details, seasons, episodes);
  }
}
