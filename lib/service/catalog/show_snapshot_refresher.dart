import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details_api.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';

/// Fetches a show's documents from TMDB and hands them to [CatalogWriter]. The three entry points
/// differ only in which seasons they ask for; none of them is a render path.
///
/// A TMDB 404 keeps the local rows and moves `fetched_at` forward (the row is silenced for one
/// refresh interval): a provider deleting an item is exactly the case the local copy exists for.
/// Transport errors propagate to the caller, who decides (serve the stale snapshot, stop the
/// tick, refuse a tracking action).
class ShowSnapshotRefresher {
  static final _log = Logger('[Service] ShowSnapshotRefresher');

  final TmdbShowDetailsApi _api;
  final CatalogWriter _writer;
  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final EpisodeRepo _episodeRepo;

  ShowSnapshotRefresher({
    TmdbShowDetailsApi? api,
    CatalogWriter? writer,
    ShowRepo? showRepo,
    SeasonRepo? seasonRepo,
    EpisodeRepo? episodeRepo,
  }) : _api = api ?? TmdbShowDetailsApi(),
       _writer = writer ?? CatalogWriter(),
       _showRepo = showRepo ?? ShowRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo();

  /// Tracking a show: the root plus EVERY season it lists, so the whole show is materialised.
  /// Returns null when TMDB has no such show.
  Future<WrittenShow?> materialise(int showTmdbId, {required String? region, DateTime? now}) async {
    final raw = await _api.getRaw(showTmdbId);
    if (raw == null) {
      return null;
    }
    final pruned = SnapshotPruner.showRoot(raw, region: region);
    final listed = _listedSeasons(raw);
    final docs = await _fetchSeasonDocs(showTmdbId, listed, region: region);
    return _writer.writeShow(pruned.root, docs, now: now ?? DateTime.now().toUtc(), region: region);
  }

  /// A page view of a stale tracked show: the root again, and only the seasons the show did not
  /// have before (a new season is materialised; existing season documents are never re-fetched
  /// by a view).
  Future<bool> refreshRoot(int showTmdbId, {required String? region, DateTime? now}) async {
    final raw = await _api.getRaw(showTmdbId);
    if (raw == null) {
      await _gone(showTmdbId, now);
      return false;
    }
    final pruned = SnapshotPruner.showRoot(raw, region: region);
    final known = (await _seasonRepo.getAllForShow(showTmdbId)).where((s) => s.hasSnapshot).map((s) => s.season).toSet();
    final fresh = _listedSeasons(raw).where((n) => !known.contains(n)).toList();
    final docs = await _fetchSeasonDocs(showTmdbId, fresh, region: region);
    await _writer.writeShow(pruned.root, docs, now: now ?? DateTime.now().toUtc(), region: region);
    return true;
  }

  /// The scheduler's refresh: the root with the OPEN seasons appended (the highest-numbered one
  /// plus every non-special season with an undated or future episode), and any new season. A
  /// closed season is never re-fetched by the job.
  Future<bool> refreshForScheduler(int showTmdbId, {required String? region, DateTime? now}) async {
    final today = ShowProgressQueries.today(now);
    final open = await _episodeRepo.getOpenSeasons(showTmdbId, today);
    final inRoot = open.take(TmdbShowDetailsApi.maxAppendedSeasons).toList();
    final raw = await _api.getRaw(showTmdbId, appendSeasons: inRoot);
    if (raw == null) {
      await _gone(showTmdbId, now);
      return false;
    }
    final pruned = SnapshotPruner.showRoot(raw, region: region);
    final known = (await _seasonRepo.getAllForShow(showTmdbId)).where((s) => s.hasSnapshot).map((s) => s.season).toSet();
    final wanted = <int>{...open, ..._listedSeasons(raw).where((n) => !known.contains(n))}..removeAll(pruned.seasons.keys);
    final docs = <int, Map<String, dynamic>>{...pruned.seasons, ...await _fetchSeasonDocs(showTmdbId, wanted, region: region)};
    await _writer.writeShow(pruned.root, docs, now: now ?? DateTime.now().toUtc(), region: region);
    return true;
  }

  /// Only the given seasons of an already tracked show (a stub season opened before the backfill
  /// reached it). The root document is rewritten too, since it comes with the same request.
  Future<bool> fetchSeasons(int showTmdbId, Iterable<int> seasons, {required String? region, DateTime? now}) async {
    final wanted = seasons.toSet().toList()..sort();
    if (wanted.isEmpty) {
      return true;
    }
    final inRoot = wanted.take(TmdbShowDetailsApi.maxAppendedSeasons).toList();
    final raw = await _api.getRaw(showTmdbId, appendSeasons: inRoot);
    if (raw == null) {
      await _gone(showTmdbId, now);
      return false;
    }
    final pruned = SnapshotPruner.showRoot(raw, region: region);
    final rest = wanted.where((n) => !pruned.seasons.containsKey(n));
    final docs = <int, Map<String, dynamic>>{...pruned.seasons, ...await _fetchSeasonDocs(showTmdbId, rest, region: region)};
    await _writer.writeShow(pruned.root, docs, now: now ?? DateTime.now().toUtc(), region: region);
    return true;
  }

  /// Seasons-only requests, twenty at a time; each answer's `season/N` keys pruned.
  Future<Map<int, Map<String, dynamic>>> _fetchSeasonDocs(int showTmdbId, Iterable<int> seasons, {required String? region}) async {
    final docs = <int, Map<String, dynamic>>{};
    for (final chunk in seasons.toSet().toList().chunked(TmdbShowDetailsApi.maxAppendKeys)) {
      final more = await _api.getSeasonsRaw(showTmdbId, chunk);
      if (more == null) {
        break;
      }
      docs.addAll(SnapshotPruner.showRoot(more, region: region).seasons);
    }
    return docs;
  }

  List<int> _listedSeasons(Map<String, dynamic> raw) {
    final stubs = raw['seasons'];
    if (stubs is! List) {
      return const [];
    }
    return [
      for (final stub in stubs)
        if (stub is Map<String, dynamic> && stub['season_number'] is int) stub['season_number'] as int,
    ];
  }

  Future<void> _gone(int showTmdbId, DateTime? now) async {
    _log.warning('Show $showTmdbId is gone from TMDB, keeping the local copy');
    await _showRepo.stampFetched(showTmdbId, now ?? DateTime.now().toUtc());
  }
}
