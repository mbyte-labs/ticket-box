import 'package:drift/drift.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/media_ref.dart';

/// One season of a tracked show. A row exists iff its show does: the show's `seasons[]` stubs
/// create it, a fetched season document (kept in `snapshot_documents`, episodes in `episodes`)
/// fills it in. [fetchedAt] null = a stub whose episode list has not been fetched.
@UseRowClass(SeasonEntity, constructor: 'build', generateInsertable: true)
class Seasons extends Table {
  IntColumn get showTmdbId => integer().customConstraint('NOT NULL')();

  IntColumn get season => integer().customConstraint('NOT NULL')();

  /// TMDB's own id for the season — informational (the backup exports it), never a key. Null on
  /// rows migrated without one.
  IntColumn get tmdbId => integer().nullable()();

  TextColumn get title => text().named('title').nullable()();

  /// How many episodes TMDB lists for the season.
  IntColumn get episodeCount => integer().nullable()();

  /// TMDB's `air_date`, `YYYY-MM-DD` verbatim; null for an unaired or sparsely edited season.
  TextColumn get airDate => text().nullable()();

  /// TMDB's relative poster path (`/abc.jpg`), never a URL.
  TextColumn get posterPath => text().nullable()();

  /// When the season document was fetched; null = stub only.
  DateTimeColumn get fetchedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {showTmdbId, season};
}

class SeasonEntity {
  int showTmdbId;

  /// The season number
  int season;

  int? tmdbId;
  String? title;
  int? episodeCount;

  /// `YYYY-MM-DD`, or null.
  String? airDate;
  String? posterPath;
  DateTime? fetchedAt;

  SeasonEntity.build({
    required this.showTmdbId,
    required this.season,
    required this.tmdbId,
    required this.title,
    required this.episodeCount,
    required this.airDate,
    required this.posterPath,
    required this.fetchedAt,
  });

  /// Whether the season's episodes have been fetched (a stub says the season exists, no more).
  bool get hasSnapshot => fetchedAt != null;

  /// The air date at local midnight.
  DateTime? get airedAt => tmdbDateOrNull(airDate);

  SeasonRef toRef() => SeasonRef(showTmdbId: showTmdbId, season: season, tmdbId: tmdbId, title: title);
}
