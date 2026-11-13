import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/converter/item_type.converter.dart';

/// The verbatim (pruned) TMDB document of a tracked movie, show or season — what the details
/// pages render offline. Kept apart from the catalogue rows so list pages that read titles and
/// paths never load the documents.
///
/// [season] is 0 for movies and shows; a season document is keyed by its show's id and number,
/// like `seasons`. The row exists iff the catalogue row's `fetched_at` is set.
@UseRowClass(SnapshotDocumentEntity, constructor: 'build', generateInsertable: true)
class SnapshotDocuments extends Table {
  TextColumn get type => text().map(const ItemTypeConverter()).customConstraint("NOT NULL CHECK (type IN ('movie', 'show', 'season'))")();

  /// The movie's id, or the SHOW's id for shows and seasons.
  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  IntColumn get season => integer().withDefault(const Constant(0))();

  TextColumn get metadataJson => text()();

  @override
  Set<Column> get primaryKey => {type, tmdbId, season};
}

class SnapshotDocumentEntity {
  ItemType type;
  int tmdbId;
  int season;
  String metadataJson;

  SnapshotDocumentEntity.build({required this.type, required this.tmdbId, required this.season, required this.metadataJson});

  SnapshotDocumentEntity.movie(this.tmdbId, this.metadataJson) : type = ItemType.movie, season = 0;

  SnapshotDocumentEntity.show(this.tmdbId, this.metadataJson) : type = ItemType.show, season = 0;

  SnapshotDocumentEntity.season(int showTmdbId, this.season, this.metadataJson) : type = ItemType.season, tmdbId = showTmdbId;
}
