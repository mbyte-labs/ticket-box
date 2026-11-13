/// Seeding helpers shared by the offline-first service tests: an in-memory database registered in
/// GetIt, catalogue rows built from stubs, plays, and the TMDB bodies the snapshot requests return.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_hooks.dart';

import 'snapshot_fixtures.dart';

/// Opens an in-memory database and registers it as the connection every repo resolves. With
/// [withPreferences] the SharedPreferences platform is swapped for an empty in-memory store too.
DatabaseConnectionManager openTestDatabase({bool withPreferences = false}) {
  if (withPreferences) {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  }
  final db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
  GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
  if (withPreferences) {
    KeyValueStore.instance();
  }
  return db;
}

Future<void> closeTestDatabase(DatabaseConnectionManager db) async {
  await GetIt.I.reset();
  await db.close();
}

/// An artwork facade that touches no file system: every call logs and no-ops.
ArtworkService noArtwork() => ArtworkService.unavailable();

/// Sync hooks that queue nothing, for tests that look only at the local write.
class NoopSyncHooks extends TmdbSyncHooks {
  @override
  Future<void> ratingChanged(_, _) async {}

  @override
  Future<void> watchlistChanged(_, {required bool listed}) async {}

  @override
  Future<void> favoriteChanged(_, {required bool favorite}) async {}
}

/// `YYYY-MM-DD` of a local date, the way the catalogue stores dates.
String ymd(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// A show row; [fetchedAt] null makes it a stub waiting for the backfill.
Future<ShowEntity> seedShow(
  int tmdbId, {
  String? title,
  DateTime? fetchedAt,
  DateTime? trackedAt,
  String? status,
  String? region,
  String? nextEpisodeAirDate,
  String? posterPath,
}) async {
  final show = ShowEntity.stub(tmdbId: tmdbId, trackedAt: trackedAt ?? DateTime.utc(2026, 1, 1), title: title ?? 'Show $tmdbId')
    ..fetchedAt = fetchedAt
    ..status = status
    ..watchProvidersRegion = region
    ..nextEpisodeAirDate = nextEpisodeAirDate
    ..posterPath = posterPath;
  await ShowRepo().insert(show);
  return show;
}

Future<MovieEntity> seedMovie(int tmdbId, {String? title, DateTime? fetchedAt, DateTime? trackedAt, String? region}) async {
  final movie = MovieEntity.stub(tmdbId: tmdbId, trackedAt: trackedAt ?? DateTime.utc(2026, 1, 1), title: title ?? 'Movie $tmdbId')
    ..fetchedAt = fetchedAt
    ..watchProvidersRegion = region;
  await MovieRepo().insert(movie);
  return movie;
}

Future<void> seedSeason(int showTmdbId, int season, {String? posterPath, DateTime? fetchedAt, int? episodeCount}) {
  return SeasonRepo().insert(
    SeasonEntity.build(
      showTmdbId: showTmdbId,
      season: season,
      tmdbId: null,
      title: 'Season $season',
      episodeCount: episodeCount,
      airDate: null,
      posterPath: posterPath,
      fetchedAt: fetchedAt,
    ),
  );
}

/// An episode row; [airDate] is `YYYY-MM-DD` or null for an unscheduled one.
Future<void> seedEpisode(int showTmdbId, int season, int episode, {String? airDate, String? title, String? stillPath}) {
  return EpisodeRepo().insert(
    EpisodeEntity.build(
      showTmdbId: showTmdbId,
      season: season,
      episode: episode,
      tmdbId: null,
      imdbId: null,
      title: title ?? 'S${season}E$episode',
      overview: null,
      voteAverage: 0,
      voteCount: 0,
      runtime: 45,
      airDate: airDate,
      episodeType: null,
      stillPath: stillPath,
    ),
  );
}

/// One play of an episode; returns the history id.
Future<int> playEpisode(int showTmdbId, int season, int episode, {DateTime? at}) {
  return HistoryRepo().insertNew(
    NewHistoryEntry.episode(
      showTmdbId: showTmdbId,
      season: season,
      episode: episode,
      action: HistoryAction.watch,
      watchedAt: (at ?? DateTime.utc(2026, 6, 1)).toUtc(),
    ),
  );
}

Future<int> playMovie(int tmdbId, {DateTime? at}) {
  return HistoryRepo().insertNew(
    NewHistoryEntry.movie(tmdbId: tmdbId, action: HistoryAction.watch, watchedAt: (at ?? DateTime.utc(2026, 6, 1)).toUtc()),
  );
}

Future<void> seedState(int showTmdbId, ShowWatchStatus status, {DateTime? at}) {
  return ShowStateRepo().upsert(showTmdbId, status, at ?? DateTime.utc(2026, 6, 1));
}

/// A `/tv/{id}` root body without appended seasons — what the tracking root request answers.
Map<String, dynamic> showRootBody({List<int> listedSeasons = const [1, 2]}) {
  final body = rawShow()..removeWhere((key, _) => key.startsWith('season/'));
  body['seasons'] = [
    for (final n in listedSeasons)
      {'id': 3623 + n, 'season_number': n, 'episode_count': 2, 'air_date': '2011-0$n-17', 'name': 'Season $n', 'poster_path': '/s$n.jpg'},
  ];
  body['number_of_seasons'] = listedSeasons.length;
  return body;
}

/// The `season/N` keys a request appends, in order.
List<int> appendedSeasonsOf(Request request) {
  final append = request.url.queryParameters['append_to_response'] ?? '';
  return [
    for (final key in append.split(','))
      if (key.startsWith('season/')) int.parse(key.substring('season/'.length)),
  ];
}

Response jsonResponse(Map<String, dynamic> body, [int status = 200]) {
  return Response.bytes(utf8.encode(json.encode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});
}

Response notFoundResponse() => jsonResponse({'success': false, 'status_code': 34, 'status_message': 'Not found'}, 404);

/// Routes the TMDB snapshot requests onto bodies: a movie request answers [movie] (its `id` set to
/// the requested one), a show request [showRoot] likewise, with the seasons it asks for appended
/// from [seasonDoc]. A null body is a 404.
Future<Response> Function(Request) snapshotAnswers({
  Map<String, dynamic>? movie,
  Map<String, dynamic>? showRoot,
  Map<String, dynamic> Function(int season)? seasonDoc,
}) {
  return (request) async {
    final segments = request.url.pathSegments;
    final id = int.tryParse(segments.length > 2 ? segments[2] : '');
    if (segments[1] == 'movie') {
      return movie == null ? notFoundResponse() : jsonResponse({...movie, 'id': id});
    }
    if (segments[1] == 'tv') {
      final root = showRoot;
      if (root == null) {
        return notFoundResponse();
      }
      final seasons = appendedSeasonsOf(request);
      return jsonResponse({...root, 'id': id, for (final n in seasons) 'season/$n': (seasonDoc ?? rawAppendedSeason)(n)});
    }
    return Response('', 500);
  };
}

/// The distinct paths the transport saw — `TmdbHttpClient` retries a failed attempt, so the raw
/// request list holds every attempt.
Set<String> distinctPaths(Iterable<Request> requests) => requests.map((r) => r.url.path).toSet();

/// Now, at the second precision the database stores instants with.
DateTime nowToTheSecond() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch - now.millisecondsSinceEpoch % 1000, isUtc: true);
}
