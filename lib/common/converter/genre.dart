import 'package:ticketbox/api/tmdb/v3/model/tmdb_genre.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/genres/genres.dart';

class GenreConverter {
  static List<GenreEntity> fromApi(ItemType type, List<TmdbGenre> genres, {DateTime? now}) {
    final syncedAt = now ?? DateTime.now();
    return genres.map((g) => GenreEntity.build(id: g.id, name: g.name, type: type, synchronizedAt: syncedAt)).toList();
  }
}
