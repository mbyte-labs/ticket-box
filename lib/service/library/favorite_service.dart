import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_hooks.dart';

/// The user's favorite movies and shows. A favorite is a whole movie or a whole show —
/// never a season or an episode — and changes nothing else: unlike a dropped show, a favorite
/// title is not hidden from or surfaced in any other list, and no poster flag mirrors it.
///
/// Every write is a plain Drift write; `DataChangeMonitor` watches the table and the pages that
/// show the flag reload from it. With a TMDB account connected and favorites sync on,
/// [TmdbSyncHooks] mirrors each write onto the account's TMDB **favorites**.
class FavoriteService {
  static final _log = Logger('[Service] FavoriteService');

  final FavoriteRepo _repo;
  final LibraryService _library;
  final TmdbSyncHooks _hooks;

  FavoriteService({FavoriteRepo? repo, LibraryService? library, TmdbSyncHooks? hooks})
    : _repo = repo ?? FavoriteRepo(),
      _library = library ?? LibraryService.instance(),
      _hooks = hooks ?? TmdbSyncHooks.instance();

  Future<void> favorite(ItemType type, int tmdbId) async {
    _assertFavoritable(type);
    _log.info('Adding ${type.name} $tmdbId to the favorites');
    await _library.ensureTracked(MediaKey(type: type, tmdbId: tmdbId));
    await _repo.insert(FavoriteEntity.build(type: type, tmdbId: tmdbId, favoritedAt: DateTime.now().toUtc()));
    await _hooks.favoriteChanged(MediaKey(type: type, tmdbId: tmdbId), favorite: true);
  }

  Future<void> unfavorite(ItemType type, int tmdbId) async {
    _assertFavoritable(type);
    _log.info('Removing ${type.name} $tmdbId from the favorites');
    await _repo.delete(type, tmdbId);
    await _hooks.favoriteChanged(MediaKey(type: type, tmdbId: tmdbId), favorite: false);
    await _library.onReferenceRemoved(MediaKey(type: type, tmdbId: tmdbId));
  }

  Future<bool> isFavorite(ItemType type, int tmdbId) async => await _repo.get(type, tmdbId) != null;

  /// The favorites of the given [types], the most recently added first.
  Future<List<FavoriteEntity>> getAll(List<ItemType> types) => _repo.getAllNewestFirst(types);

  Future<int> count() => _repo.count();

  void _assertFavoritable(ItemType type) {
    if (type != ItemType.movie && type != ItemType.show) {
      throw ArgumentError.value(type, 'type', 'Only movies and shows can be favorites');
    }
  }
}
