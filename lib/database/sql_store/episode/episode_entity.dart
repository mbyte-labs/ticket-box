import 'package:drift/drift.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/common/model/media_ref.dart';

/// One episode of a tracked show's catalogue — the query substrate of progress, Up Next and the
/// history titles. Addressed by position (show, season, episode), never by its TMDB id: TMDB
/// renumbers, and a second unique key would turn a renumber into a failed refresh. It has no
/// document of its own; it rides its season's.
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_episodes_air_date ON episodes (air_date)')
@UseRowClass(EpisodeEntity, constructor: 'build', generateInsertable: true)
class Episodes extends Table {
  IntColumn get showTmdbId => integer().customConstraint('NOT NULL')();

  IntColumn get season => integer().customConstraint('NOT NULL')();

  IntColumn get episode => integer().customConstraint('NOT NULL')();

  /// TMDB's own id for the episode — informational; null on rows migrated without one.
  IntColumn get tmdbId => integer().nullable()();

  TextColumn get imdbId => text().nullable()();

  TextColumn get title => text().named('title').nullable()();

  TextColumn get overview => text().named('overview').nullable()();

  RealColumn get voteAverage => real().withDefault(const Constant(0))();

  IntColumn get voteCount => integer().withDefault(const Constant(0))();

  IntColumn get runtime => integer().nullable()();

  /// TMDB's `air_date`, `YYYY-MM-DD` verbatim — a date, never an instant, so no time zone can move
  /// it. Null when TMDB has not scheduled the episode; an unknown date never reads as aired.
  TextColumn get airDate => text().nullable()();

  /// [EpisodeType.wireValue]
  TextColumn get episodeType => text().nullable()();

  /// TMDB's relative still path (`/abc.jpg`), never a URL.
  TextColumn get stillPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {showTmdbId, season, episode};
}

class EpisodeEntity {
  int showTmdbId;

  /// Represents the season number
  int season;

  /// Represents the episode number
  int episode;

  int? tmdbId;
  String? imdbId;

  /// Episode's title
  String? title;

  /// Episode's description
  String? overview;

  double voteAverage;
  int voteCount;

  /// Episode's runtime in minutes
  int? runtime;

  /// `YYYY-MM-DD`, or null when unscheduled.
  String? airDate;

  /// [EpisodeType.wireValue]; null reads as [EpisodeType.standard].
  String? episodeType;

  String? stillPath;

  EpisodeEntity.build({
    required this.showTmdbId,
    required this.season,
    required this.episode,
    required this.tmdbId,
    required this.imdbId,
    required this.title,
    required this.overview,
    required this.voteAverage,
    required this.voteCount,
    required this.runtime,
    required this.airDate,
    required this.episodeType,
    required this.stillPath,
  });

  /// When the episode was/will be aired, at local midnight; null when unscheduled.
  DateTime? get firstAired => tmdbDateOrNull(airDate);

  EpisodeType get type => EpisodeType.fromWireValue(episodeType);

  EpisodeRef toRef() => EpisodeRef(showTmdbId: showTmdbId, season: season, episode: episode, tmdbId: tmdbId, title: title);
}
