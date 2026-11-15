import 'package:drift/drift.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/media_ref.dart';
import 'package:ticketbox/common/model/movie_status.dart';

/// A tracked movie: the convenience columns every list and page reads, plus the snapshot's
/// bookkeeping. The verbatim TMDB document lives in `snapshot_documents`.
///
/// A row exists iff the movie is in the library (a play, a rating, a watchlist or favorite row);
/// browsing writes nothing. [fetchedAt] is the only freshness state — `null` means the snapshot
/// has not been materialised yet (the backfill's work list) and the row holds whatever the
/// previous schema knew, which is enough to render the pages until it lands.
@UseRowClass(MovieEntity, constructor: 'build', generateInsertable: true)
class Movies extends Table {
  IntColumn get tmdbId => integer().customConstraint('NOT NULL')();

  TextColumn get imdbId => text().nullable()();

  TextColumn get title => text().named('title').nullable()();

  IntColumn get year => integer().nullable()();

  TextColumn get overview => text().named('overview').nullable()();

  TextColumn get tagline => text().nullable()();

  /// TMDB's `release_date`, `YYYY-MM-DD` verbatim (a date, never an instant); null when unknown.
  TextColumn get releaseDate => text().nullable()();

  /// Runtime in minutes
  IntColumn get runtime => integer().nullable()();

  TextColumn get certification => text().nullable()();

  TextColumn get country => text().nullable()();

  TextColumn get language => text().nullable()();

  TextColumn get trailer => text().nullable()();

  TextColumn get homepage => text().nullable()();

  RealColumn get voteAverage => real().withDefault(const Constant(0))();

  IntColumn get voteCount => integer().withDefault(const Constant(0))();

  RealColumn get popularity => real().withDefault(const Constant(0))();

  /// Comma separated list of TMDB genre ids
  TextColumn get genres => text().named('genres').withDefault(const Constant(''))();

  /// [MovieStatus.name], or null when TMDB omitted it.
  TextColumn get status => text().nullable()();

  /// TMDB's relative poster path (`/abc.jpg`), never a URL; the artwork file is named by the key.
  TextColumn get posterPath => text().nullable()();

  TextColumn get backdropPath => text().nullable()();

  /// When the snapshot was fetched; null = never (no document yet).
  DateTimeColumn get fetchedAt => dateTime().nullable()();

  /// When the movie entered the library.
  DateTimeColumn get trackedAt => dateTime()();

  /// The country the stored `watch/providers` was pruned to; a region change forces one refresh.
  TextColumn get watchProvidersRegion => text().nullable()();

  @override
  Set<Column> get primaryKey => {tmdbId};
}

class MovieEntity {
  int tmdbId;
  String? imdbId;
  String? title;
  int? year;
  String? overview;
  String? tagline;

  /// `YYYY-MM-DD`, or null.
  String? releaseDate;

  /// Runtime in minutes
  int? runtime;

  String? certification;
  String? country;
  String? language;
  String? trailer;
  String? homepage;
  double voteAverage;
  int voteCount;
  double popularity;

  /// Comma separated list of TMDB genre ids
  String genres;

  /// [MovieStatus.name]; null when TMDB omitted it.
  String? status;

  String? posterPath;
  String? backdropPath;
  DateTime? fetchedAt;
  DateTime trackedAt;
  String? watchProvidersRegion;

  MovieEntity.build({
    required this.tmdbId,
    required this.imdbId,
    required this.title,
    required this.year,
    required this.overview,
    required this.tagline,
    required this.releaseDate,
    required this.runtime,
    required this.certification,
    required this.country,
    required this.language,
    required this.trailer,
    required this.homepage,
    required this.voteAverage,
    required this.voteCount,
    required this.popularity,
    required this.genres,
    required this.status,
    required this.posterPath,
    required this.backdropPath,
    required this.fetchedAt,
    required this.trackedAt,
    required this.watchProvidersRegion,
  });

  /// A row that only says "this movie is in the library since [trackedAt]" — what a backup restore
  /// or a TMDB account pull creates before the backfill fetches the snapshot.
  MovieEntity.stub({required this.tmdbId, required this.trackedAt, this.title})
    : imdbId = null,
      year = null,
      overview = null,
      tagline = null,
      releaseDate = null,
      runtime = null,
      certification = null,
      country = null,
      language = null,
      trailer = null,
      homepage = null,
      voteAverage = 0,
      voteCount = 0,
      popularity = 0,
      genres = '',
      status = null,
      posterPath = null,
      backdropPath = null,
      fetchedAt = null,
      watchProvidersRegion = null;

  /// Whether a snapshot document has been materialised for this row.
  bool get hasSnapshot => fetchedAt != null;

  /// The release date at local midnight, for comparisons and the "watched at release" option.
  DateTime? get released => tmdbDateOrNull(releaseDate);

  MovieStatus get statusValue => MovieStatus.fromName(status);

  List<int> get genreList => genres.isEmpty ? [] : genres.split(',').map(int.tryParse).whereType<int>().toList();

  MovieRef toRef() => MovieRef(tmdbId: tmdbId, imdbId: imdbId, title: title, year: year);
}
