import 'package:drift/drift.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/media_ref.dart';
import 'package:ticketbox/common/model/show_status.dart';

/// A tracked show: the convenience columns every list and page reads, plus the snapshot's
/// bookkeeping. The verbatim TMDB document lives in `snapshot_documents`; its seasons and episodes
/// in their own tables and exist only while the show does.
///
/// A row exists iff the show is in the library (any episode play, a rating, a watchlist or
/// favorite row, a state row); browsing writes nothing. [fetchedAt] is the only freshness state —
/// `null` means the snapshot has not been materialised yet.
@UseRowClass(ShowEntity, constructor: 'build', generateInsertable: true)
class Shows extends Table {
  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  TextColumn get imdbId => text().nullable()();

  TextColumn get title => text().named('title').nullable()();

  IntColumn get year => integer().nullable()();

  TextColumn get overview => text().named('overview').nullable()();

  TextColumn get tagline => text().nullable()();

  /// TMDB's `first_air_date`, `YYYY-MM-DD` verbatim; null when unknown.
  TextColumn get firstAirDate => text().nullable()();

  /// TMDB's `last_air_date`, `YYYY-MM-DD` verbatim; null when unknown.
  TextColumn get lastAirDate => text().nullable()();

  /// Runtime of a regular episode, in minutes (TMDB `episode_run_time[0]`, often absent).
  IntColumn get runtime => integer().nullable()();

  TextColumn get certification => text().nullable()();

  TextColumn get network => text().nullable()();

  TextColumn get country => text().nullable()();

  TextColumn get language => text().nullable()();

  TextColumn get trailer => text().nullable()();

  TextColumn get homepage => text().nullable()();

  RealColumn get voteAverage => real().withDefault(const Constant(0))();

  IntColumn get voteCount => integer().withDefault(const Constant(0))();

  RealColumn get popularity => real().withDefault(const Constant(0))();

  IntColumn get numberOfSeasons => integer().withDefault(const Constant(0))();

  /// TMDB's `next_episode_to_air.air_date`, `YYYY-MM-DD`; the refresh scheduler's accelerator.
  TextColumn get nextEpisodeAirDate => text().nullable()();

  IntColumn get nextEpisodeSeason => integer().nullable()();

  IntColumn get nextEpisodeNumber => integer().nullable()();

  /// Comma separated list of TMDB genre ids
  TextColumn get genres => text().named('genres').withDefault(const Constant(''))();

  /// [ShowStatus.name] — TMDB's *production* status, never a watch status; null when omitted.
  TextColumn get status => text().nullable()();

  /// TMDB's relative poster path (`/abc.jpg`), never a URL.
  TextColumn get posterPath => text().nullable()();

  TextColumn get backdropPath => text().nullable()();

  /// When the root snapshot was fetched; null = never (no document yet).
  DateTimeColumn get fetchedAt => dateTime().nullable()();

  /// When the show entered the library.
  DateTimeColumn get trackedAt => dateTime()();

  /// The country the stored `watch/providers` was pruned to; a region change forces one refresh.
  TextColumn get watchProvidersRegion => text().nullable()();

  @override
  Set<Column> get primaryKey => {tmdbId};
}

class ShowEntity {
  int tmdbId;
  String? imdbId;

  /// Show's title
  String? title;

  int? year;
  String? overview;
  String? tagline;

  /// `YYYY-MM-DD`, or null.
  String? firstAirDate;

  /// `YYYY-MM-DD`, or null.
  String? lastAirDate;

  /// Runtime of a regular episode, in minutes
  int? runtime;

  String? certification;
  String? network;
  String? country;
  String? language;
  String? trailer;
  String? homepage;
  double voteAverage;
  int voteCount;
  double popularity;
  int numberOfSeasons;

  /// `YYYY-MM-DD`, or null.
  String? nextEpisodeAirDate;
  int? nextEpisodeSeason;
  int? nextEpisodeNumber;

  /// Comma separated list of TMDB genre ids
  String genres;

  /// [ShowStatus.name]; null when TMDB omitted it, which [statusValue] reads as [ShowStatus.unknown].
  String? status;

  String? posterPath;
  String? backdropPath;
  DateTime? fetchedAt;
  DateTime trackedAt;
  String? watchProvidersRegion;

  ShowEntity.build({
    required this.tmdbId,
    required this.imdbId,
    required this.title,
    required this.year,
    required this.overview,
    required this.tagline,
    required this.firstAirDate,
    required this.lastAirDate,
    required this.runtime,
    required this.certification,
    required this.network,
    required this.country,
    required this.language,
    required this.trailer,
    required this.homepage,
    required this.voteAverage,
    required this.voteCount,
    required this.popularity,
    required this.numberOfSeasons,
    required this.nextEpisodeAirDate,
    required this.nextEpisodeSeason,
    required this.nextEpisodeNumber,
    required this.genres,
    required this.status,
    required this.posterPath,
    required this.backdropPath,
    required this.fetchedAt,
    required this.trackedAt,
    required this.watchProvidersRegion,
  });

  /// A row that only says "this show is in the library since [trackedAt]" — what a backup restore
  /// or a TMDB account pull creates before the backfill fetches the snapshot.
  ShowEntity.stub({required this.tmdbId, required this.trackedAt, this.title})
    : imdbId = null,
      year = null,
      overview = null,
      tagline = null,
      firstAirDate = null,
      lastAirDate = null,
      runtime = null,
      certification = null,
      network = null,
      country = null,
      language = null,
      trailer = null,
      homepage = null,
      voteAverage = 0,
      voteCount = 0,
      popularity = 0,
      numberOfSeasons = 0,
      nextEpisodeAirDate = null,
      nextEpisodeSeason = null,
      nextEpisodeNumber = null,
      genres = '',
      status = null,
      posterPath = null,
      backdropPath = null,
      fetchedAt = null,
      watchProvidersRegion = null;

  /// Whether a snapshot document has been materialised for this row.
  bool get hasSnapshot => fetchedAt != null;

  /// When the show was/will be first aired, at local midnight.
  DateTime? get firstAired => tmdbDateOrNull(firstAirDate);

  /// When the most recent episode aired, at local midnight.
  DateTime? get lastAired => tmdbDateOrNull(lastAirDate);

  /// When the announced next episode airs, at local midnight.
  DateTime? get nextEpisodeAirsAt => tmdbDateOrNull(nextEpisodeAirDate);

  ShowStatus get statusValue => ShowStatus.fromName(status);

  List<int> get genreList => genres.isEmpty ? [] : genres.split(',').map(int.tryParse).whereType<int>().toList();

  ShowRef toRef() => ShowRef(tmdbId: tmdbId, imdbId: imdbId, title: title, year: year);
}
