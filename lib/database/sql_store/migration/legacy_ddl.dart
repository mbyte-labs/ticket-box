/// The `CREATE TABLE` statements of tables that no longer exist in the Dart schema, or that a
/// later step reshapes, as the version that introduced them wrote them.
///
/// `Migrator.createAll()` builds the *current* schema. The 3 → 4 step runs it and then puts every
/// table a later step reads or reshapes back in its v4 shape from these constants, so the walk
/// 3 → 4 → … → 10 runs each step on exactly the file that version would have left. A step that
/// reshapes a table in place (6 → 7) creates the new shape from here too, never from the Dart
/// schema. Pure strings, no imports — nothing here may change once shipped.
abstract final class LegacyDdl {
  /// The v9 catalogue tables the 9 → 10 step rebuilds, parked under `v9_` names meanwhile.
  static const List<String> v9CatalogueTables = ['movies', 'movie_summaries', 'shows', 'show_summaries', 'seasons', 'episodes'];

  /// The tables v10 dropped: recreated in their v4 shape after `createAll()` in the 3 → 4 step and
  /// dropped again by the 9 → 10 step.
  static const List<String> v10DroppedTables = [
    'posters',
    'show_images',
    'movie_images',
    'season_images',
    'episode_images',
    'item_people',
    'item_people_syncs',
    'show_progress_items',
    'season_progress_items',
    'episode_progress_items',
    'up_next_episode_items',
    'dropped_items',
  ];

  /// The v10-only objects `createAll()` builds that a v4 file must not have yet; the 9 → 10 step
  /// creates them.
  static const List<String> v10OnlyTables = ['snapshot_documents', 'show_states', 'pending_deletions', 'asset_jobs'];

  static const List<String> v10OnlyIndexes = [
    'idx_history_items_key',
    'idx_history_items_watched_at',
    'idx_episodes_air_date',
    'idx_asset_jobs_status',
    'idx_asset_jobs_item',
  ];

  /// Every table the 3 → 4 step recreates in its v4 shape right after `createAll()`, in creation
  /// order. `episodes` is the v4–v6 shape the 6 → 7 step merges `episode_summaries` into;
  /// `recommended_items` the name the 8 → 9 step renames from.
  static const Map<String, String> v4Shapes = {
    'movies': v4Movies,
    'movie_summaries': v4MovieSummaries,
    'shows': v4Shows,
    'show_summaries': v4ShowSummaries,
    'seasons': v4Seasons,
    'episodes': v6Episodes,
    'episode_summaries': v6EpisodeSummaries,
    'dropped_items': v4DroppedItems,
    'posters': v4Posters,
    'show_images': v4ShowImages,
    'movie_images': v4MovieImages,
    'season_images': v4SeasonImages,
    'episode_images': v4EpisodeImages,
    'item_people': v4ItemPeople,
    'item_people_syncs': v4ItemPeopleSyncs,
    'show_progress_items': v4ShowProgressItems,
    'season_progress_items': v4SeasonProgressItems,
    'episode_progress_items': v4EpisodeProgressItems,
    'up_next_episode_items': v4UpNextEpisodeItems,
    'recommended_items': v6RecommendedItems,
  };

  static const String v4Movies =
      'CREATE TABLE "movies" ("tmdb_id" INTEGER NOT NULL, "imdb_id" TEXT NULL, "title" TEXT NULL, "year" INTEGER NULL, '
      '"synchronized_at" INTEGER NOT NULL, PRIMARY KEY(tmdb_id))';

  static const String v4MovieSummaries =
      'CREATE TABLE "movie_summaries" ("tmdb_id" INTEGER NOT NULL, "title" TEXT NULL, "year" INTEGER NULL, "overview" TEXT NULL, '
      '"tagline" TEXT NULL, "released" INTEGER NULL, "runtime" INTEGER NULL, "certification" TEXT NULL, "country" TEXT NULL, '
      '"language" TEXT NULL, "trailer" TEXT NULL, "homepage" TEXT NULL, "vote_average" REAL NOT NULL, "vote_count" INTEGER NOT NULL, '
      '"popularity" REAL NOT NULL, "genres" TEXT NOT NULL, "status" TEXT NULL, "synchronized_at" INTEGER NOT NULL, PRIMARY KEY(tmdb_id))';

  static const String v4Shows =
      'CREATE TABLE "shows" ("tmdb_id" INTEGER NOT NULL, "imdb_id" TEXT NULL, "title" TEXT NULL, "year" INTEGER NULL, '
      '"synchronized_at" INTEGER NOT NULL, PRIMARY KEY(tmdb_id))';

  static const String v4ShowSummaries =
      'CREATE TABLE "show_summaries" ("tmdb_id" INTEGER NOT NULL, "title" TEXT NULL, "year" INTEGER NULL, "overview" TEXT NULL, '
      '"tagline" TEXT NULL, "first_aired" INTEGER NULL, "last_air_date" INTEGER NULL, "runtime" INTEGER NULL, "certification" TEXT NULL, '
      '"network" TEXT NULL, "country" TEXT NULL, "language" TEXT NULL, "trailer" TEXT NULL, "homepage" TEXT NULL, '
      '"vote_average" REAL NOT NULL, "vote_count" INTEGER NOT NULL, "popularity" REAL NOT NULL, "aired_episodes" INTEGER NOT NULL, '
      '"number_of_seasons" INTEGER NOT NULL, "next_episode_air_date" INTEGER NULL, "next_episode_season" INTEGER NULL, '
      '"next_episode_number" INTEGER NULL, "genres" TEXT NOT NULL, "status" TEXT NULL, "synchronized_at" INTEGER NOT NULL, '
      'PRIMARY KEY(tmdb_id))';

  static const String v4Seasons =
      'CREATE TABLE "seasons" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "tmdb_id" INTEGER NOT NULL, '
      '"title" TEXT NULL, "episode_count" INTEGER NULL, "air_date" INTEGER NULL, "synchronized_at" INTEGER NOT NULL, '
      'PRIMARY KEY(show_tmdb_id, season))';

  /// The `episodes` table as v4–v6 created it, before the 6 → 7 step merged the summaries in.
  static const String v6Episodes =
      'CREATE TABLE "episodes" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "episode" INTEGER NOT NULL, '
      '"tmdb_id" INTEGER NULL, "imdb_id" TEXT NULL, "title" TEXT NULL, "synchronized_at" INTEGER NOT NULL, '
      '"synchronized_summary_at" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id, season, episode))';

  /// The `episode_summaries` table as v4–v6 created it.
  static const String v6EpisodeSummaries =
      'CREATE TABLE "episode_summaries" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "episode" INTEGER NOT NULL, '
      '"overview" TEXT NULL, "vote_average" REAL NOT NULL, "vote_count" INTEGER NOT NULL, "runtime" INTEGER NULL, '
      '"first_aired" INTEGER NULL, "episode_type" TEXT NULL, "synchronized_at" INTEGER NOT NULL, '
      'PRIMARY KEY(show_tmdb_id, season, episode))';

  /// The `episodes` table as v7–v9 created it (the 6 → 7 merge), before the 9 → 10 step rebuilt it.
  static const String v7Episodes =
      'CREATE TABLE "episodes" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "episode" INTEGER NOT NULL, '
      '"tmdb_id" INTEGER NULL, "imdb_id" TEXT NULL, "title" TEXT NULL, "overview" TEXT NULL, "vote_average" REAL NOT NULL, '
      '"vote_count" INTEGER NOT NULL, "runtime" INTEGER NULL, "first_aired" INTEGER NULL, "episode_type" TEXT NULL, '
      '"synchronized_at" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id, season, episode))';

  /// The `recommended_items` table as v6–v8 created it, before the 8 → 9 step renamed it.
  static const String v6RecommendedItems =
      'CREATE TABLE IF NOT EXISTS "recommended_items" ("type" TEXT NOT NULL, "tmdb_id" INTEGER NOT NULL, '
      '"recommended_at" INTEGER NOT NULL, PRIMARY KEY(type, tmdb_id))';

  static const String v4DroppedItems =
      'CREATE TABLE "dropped_items" ("tmdb_id" INTEGER NOT NULL, "imdb_id" TEXT NULL, "dropped_at" INTEGER NOT NULL, PRIMARY KEY(tmdb_id))';

  static const String v4Posters =
      'CREATE TABLE "posters" ("id" INTEGER NOT NULL UNIQUE, "tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, '
      '"episode" INTEGER NOT NULL, "type" TEXT NOT NULL, "title" TEXT NOT NULL, "watched" INTEGER NOT NULL CHECK (watched IN (0, 1)), '
      '"watch_listed" INTEGER NOT NULL CHECK (watch_listed IN (0, 1)), "dropped" INTEGER NOT NULL CHECK (dropped IN (0, 1)), '
      '"season_premiere" INTEGER NOT NULL CHECK (season_premiere IN (0, 1)), '
      '"season_finale" INTEGER NOT NULL CHECK (season_finale IN (0, 1)), '
      '"series_finale" INTEGER NOT NULL CHECK (series_finale IN (0, 1)), '
      '"mid_season_finale" INTEGER NOT NULL CHECK (mid_season_finale IN (0, 1)), "rating" TEXT NULL, "user_rating" TEXT NULL, '
      '"poster_url" TEXT NULL, "no_poster_text" TEXT NOT NULL, "loading" INTEGER NOT NULL CHECK (loading IN (0, 1)), '
      '"loading_count" INTEGER NOT NULL, "poster_url_last_updated_at" INTEGER NOT NULL, "poster_data_updated_at" INTEGER NOT NULL, '
      'PRIMARY KEY(id))';

  static const String v4ShowImages =
      'CREATE TABLE "show_images" ("show_tmdb_id" INTEGER NOT NULL, "posterUrl" TEXT NULL, "bannerUrl" TEXT NULL, '
      '"synchronized_at" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id))';

  static const String v4MovieImages =
      'CREATE TABLE "movie_images" ("movie_tmdb_id" INTEGER NOT NULL, "posterUrl" TEXT NULL, "bannerUrl" TEXT NULL, '
      '"synchronized_at" INTEGER NOT NULL, PRIMARY KEY(movie_tmdb_id))';

  static const String v4SeasonImages =
      'CREATE TABLE "season_images" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "posterUrl" TEXT NULL, '
      '"synchronized_at" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id, season))';

  static const String v4EpisodeImages =
      'CREATE TABLE "episode_images" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "episode" INTEGER NOT NULL, '
      '"stillUrl" TEXT NULL, "synchronized_at" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id, season, episode))';

  static const String v4ItemPeople =
      'CREATE TABLE "item_people" ("type" TEXT NOT NULL, "item_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, '
      '"episode" INTEGER NOT NULL, "role" TEXT NOT NULL, "person_tmdb_id" INTEGER NOT NULL, "name" TEXT NOT NULL, '
      '"characters" TEXT NOT NULL, "profilePath" TEXT NULL, "cast_order" INTEGER NOT NULL, "episode_count" INTEGER NOT NULL, '
      'PRIMARY KEY(type, item_tmdb_id, season, episode, person_tmdb_id, role))';

  static const String v4ItemPeopleSyncs =
      'CREATE TABLE "item_people_syncs" ("type" TEXT NOT NULL, "item_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, '
      '"episode" INTEGER NOT NULL, "synchronized_at" INTEGER NOT NULL, "images_synchronized_at" INTEGER NULL, '
      'PRIMARY KEY(type, item_tmdb_id, season, episode))';

  static const String v4ShowProgressItems =
      'CREATE TABLE "show_progress_items" ("show_tmdb_id" INTEGER NOT NULL, "aired" INTEGER NOT NULL, "completed" INTEGER NOT NULL, '
      '"last_watched_at" INTEGER NULL, "computed_at" INTEGER NULL, PRIMARY KEY(show_tmdb_id))';

  static const String v4SeasonProgressItems =
      'CREATE TABLE "season_progress_items" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "aired" INTEGER NOT NULL, '
      '"completed" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id, season))';

  static const String v4EpisodeProgressItems =
      'CREATE TABLE "episode_progress_items" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "episode" INTEGER NOT NULL, '
      '"completed" INTEGER NOT NULL, PRIMARY KEY(show_tmdb_id, season, episode))';

  static const String v4UpNextEpisodeItems =
      'CREATE TABLE "up_next_episode_items" ("show_tmdb_id" INTEGER NOT NULL, "season" INTEGER NOT NULL, "episode" INTEGER NOT NULL, '
      'PRIMARY KEY(show_tmdb_id))';
}
