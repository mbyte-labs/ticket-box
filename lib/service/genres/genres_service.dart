import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/genres/genres_api.dart';
import 'package:ticketbox/common/converter/genre.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/genres/genres.dart';
import 'package:ticketbox/database/sql_store/genres/genres_repository.dart';
import 'package:ticketbox/service/cache_update_calculator.dart';

/// TMDB's movie and TV genre lists, cached for a month. Never throws when a cached list exists.
class GenresService {
  static final _log = Logger('[Service] GenresService');

  static const _refreshDays = 30;

  final GenresRepo _repo;
  final TmdbGenresApi _api;

  GenresService({GenresRepo? repo, TmdbGenresApi? api}) : _repo = repo ?? GenresRepo(), _api = api ?? TmdbGenresApi();

  Future<List<GenreEntity>> getByType(ItemType type, [bool updateCache = true]) async {
    final cached = await _repo.getByType(type);
    final stale = cached.isEmpty || (updateCache && CacheNeedsUpdate.generalItem(cached.first.synchronizedAt, _refreshDays, _refreshDays));
    if (!stale) {
      return cached;
    }
    try {
      final remote = type == ItemType.movie ? await _api.movies() : await _api.shows();
      final entities = GenreConverter.fromApi(type, remote);
      await _repo.replaceByType(type, entities);
      return await _repo.getByType(type);
    } catch (e, stackTrace) {
      if (cached.isNotEmpty) {
        _log.warning('Could not refresh ${type.name} genres, using the cached list', e, stackTrace);
        return cached;
      }
      rethrow;
    }
  }

  /// `id → name` for the given type, for labelling stored genre ids.
  Future<Map<int, String>> namesByType(ItemType type) async {
    final genres = await getByType(type);
    return {for (final genre in genres) genre.id: genre.name};
  }
}
