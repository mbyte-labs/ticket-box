# Ticket Box – Agent Instructions

Flutter app for tracking movies & TV shows. Metadata and images come from TMDB (plus OMDB for IMDb scores); everything the
user owns — watch history, ratings, watchlist, dropped shows, favorite movies and shows — lives on the device and works without
any account. The app is **offline-first**: once a title is in the library (tracked) its details, seasons, episodes, cast,
providers, artwork and every action work with no network; TMDB is only needed to *add* a title or to browse (search, discover,
people). Optionally the user logs in to their **TMDB account** (Settings), which mirrors ratings, watchlist and favorites to that
account — see *TMDB account sync* below; nothing else leaves the device. Android is the only platform target (there are no
`linux/`, `windows/` or `web/` folders).
---

## Architecture

The codebase is split into four strict layers (no layer should import from one above it):

| Layer | Path | Responsibility |
|---|---|---|
| API clients | `lib/api/` | Raw HTTP calls to TMDB and OMDB |
| Database | `lib/database/` | Drift SQLite (`sql_store/`) + SharedPreferences (`key_value_store/`) |
| Services | `lib/service/` | Business logic, the tracking gate, snapshot capture, the refresh scheduler, artwork, DI registration |
| UI | `lib/ui/` | Flutter widgets, pages, routing, theme |

Converters in `lib/common/converter/` translate TMDB DTOs → Drift entities (e.g. `ShowConverter.fromDetails()`).
Nothing under `lib/database/` imports `lib/api/`: entities expose `toRef()` (`MovieRef`/`ShowRef`/`SeasonRef`/
`EpisodeRef` in `lib/common/model/media_ref.dart`) and the UI passes those around instead of API models.

**Identity.** Everything is keyed by TMDB id. Seasons and episodes are addressed by **show id + season /
episode number**, exactly as TMDB's `/tv/{id}/season/{n}/episode/{e}` does; their own TMDB ids are stored but
never used as keys. `MediaKey` (`lib/common/model/media_key.dart`) is the `(type, tmdbId, season, episode)`
quadruple every user-data table uses. **Movies and shows share TMDB's numeric id space**, so `type` is part of
every key and every `WHERE tmdb_id = ?` on a mixed table must also filter on type (`LibraryService.referenceCount`'s
per-table `EXISTS` clauses are the canonical example).

---

## Critical Developer Commands

```bash
# After modifying any @freezed class, Drift table, or @JsonSerializable model:
dart run build_runner build

# Run the app (keys come from the gitignored secrets.json)
flutter run --dart-define-from-file=secrets.json

# Run tests
flutter test
```

Code generation produces `*.freezed.dart` and `*.g.dart` files — **always regenerate after touching annotated classes**.

---

## Dependency Injection (GetIt)

Services are registered as singletons via GetIt. The canonical pattern is a private constructor + static `instance()` factory:

```dart
static KeyValueStore instance() {
  if (GetIt.I.isRegistered<KeyValueStore>()) return GetIt.I.get<KeyValueStore>();
  final repo = KeyValueStore._();
  GetIt.I.registerSingleton<KeyValueStore>(repo);
  return repo;
}
```

All registrations happen during `StartUpConfiguration.configureApp()` (`lib/service/configuration/start_up_configuration_service.dart`).
Everything runs in the main isolate; there are no background isolates any more.

---

## State Management

BLoC Cubits pattern throughout. State classes are `@freezed` immutable records. Use `copyWith` (generated) to produce new states:

```dart
final newState = state.copyWith.filters(filtersApplied: false).copyWith.filters.filters(orderBy: orderBy);
emit(newState);
```

State files always pair: `*_state.dart` (defines the Freezed class) + `*_bloc.dart` (the Cubit).

---

## Data Storage

- **SQLite (Drift)** – all entities defined as `Table` subclasses under `lib/database/sql_store/`. All tables registered in
  `DatabaseConnectionManager` (`lib/database/sql_store/database_connection_manager.dart`). Schema version is **10**.
- **The catalogue is a snapshot store.** `movies` and `shows` are one row per title (the old `*_summaries` are folded in) with
  the convenience columns every list reads (`title`, `year`, `poster_path`, `backdrop_path`, `genres`, `status`, …), a
  `tracked_at`, a nullable `fetched_at` (**the only freshness state**: NULL = in the library but the document not fetched yet)
  and the region the stored providers were pruned to (`watch_providers_region`). The TMDB document itself lives in
  **`snapshot_documents`** (`type`, `tmdb_id`, `season`, `metadata_json`), a separate table so list queries never load JSON.
  `seasons` (`(show_tmdb_id, season)`, nullable `tmdb_id`, `poster_path`, own `fetched_at`) and `episodes`
  (`(show_tmdb_id, season, episode)`, `still_path`, `imdb_id`) are projections of the season documents. **Air and release dates
  are `TEXT 'YYYY-MM-DD'`**, verbatim from TMDB and zone-proof; instants stay INTEGER unix seconds. Only tracked titles have rows:
  browsing writes nothing.
- **User tables**: `history_items` (AUTOINCREMENT ids, indices on the key and on `watched_at`), `user_ratings`, `watchlists`,
  `favorite_items`, **`show_states`** (`show_tmdb_id`, `status` ∈ `watching | watched | dropped`, `updated_at`; a row exists iff
  the show has an episode play — system-maintained — or the user dropped it — sticky), **`pending_deletions`** (titles nothing
  references any more, swept after a grace period), **`asset_jobs`** (the artwork download queue, `dest_path` UNIQUE,
  `status` ∈ `pending | done | failed`), `tmdb_sync_outbox`, `job_states`, `caches` (OMDb ratings, discover page one, the
  provider region list) and `genres`. There is no stored progress, no poster table and no image tables any more.
- **Migrations are stepwise where it matters.** `DatabaseConnectionManager.nonDestructiveMigrations` lists the single
  `(n, n + 1)` steps `onUpgrade` can run without losing user data, and `canMigrateInPlace` walks them in one transaction
  (3 → 10 runs every step in order) — `(3, 4)`, the v3 → TMDB re-key (`_migrateV3ToV4`: park the v3 tables under `v3_*`,
  `createAll()`, `INSERT OR IGNORE … SELECT` with joins, drop the parked tables), `(4, 5)`, seasons no longer rated, `(5, 6)`,
  the recommended list, `(6, 7)`, episode summaries folded into `episodes`, `(7, 8)`, the TMDB sync outbox, `(8, 9)`, the
  favorites rename, and **`(9, 10)`, the snapshot store** (`_migrateV9ToV10`: park the six catalogue tables, create the v10
  ones, copy only the titles a user table references — the browse-only rows are dropped — with the poster / backdrop paths
  harvested out of the old size-baked URLs, insert `(tmdb_id, tracked_at)` stubs for referenced titles that had no catalogue
  row, derive `show_states` from the plays with the same aired predicate the runtime uses, drop the poster, image, people,
  progress and `dropped_items` tables). `_migrateV3ToV4`'s `createAll()` builds the *current* schema, so a later step that
  changes a table's shape has to account for that: a new table is fine (`createTable` is `IF NOT EXISTS`), but every table a
  later step reshapes or drops must be put back in its **v4 shape right after `createAll()`** — the DDL constants live in
  `lib/database/sql_store/migration/legacy_ddl.dart` (`LegacyDdl`) and `_migrateV3ToV4` drops the v10 objects and recreates
  the v4 ones from them, so 6 → 7, 8 → 9 and 9 → 10 run as on any real v4 file. Indices use
  `@TableIndex.sql('CREATE INDEX IF NOT EXISTS …')` for the same reason. `PreferenceVersionGuard` walks the same steps for its
  key removals. Any other version change is the destructive reset: every object in the file is dropped and recreated like a
  first install. Shipping a schema change therefore means: bump `schemaVersion`, add the step to `nonDestructiveMigrations`,
  write its SQL, dump the schema (`dart run drift_dev schema dump lib/database/sql_store/database_connection_manager.dart
  drift_schemas/drift_schema_vN.json`, then `dart run drift_dev schema generate --data-classes --companions drift_schemas/
  test/database/sql_store/generated/`) and extend `test/database/sql_store/database_migration_test.dart`, which runs the real
  step through drift's `SchemaVerifier` and asserts both the data and that the migrated schema equals a fresh install.
  Migration callbacks are **pure SQL + logging**: no platform channels, no network. `tool/make_v3_fixture.dart` and
  `tool/make_v9_fixture.dart` build seeded database files for an on-device upgrade test;
  `test/tool/migrate_fixture_smoke_test.dart --dart-define=FIXTURE=<file>` migrates a copy and prints what survived.
- **`PreferenceVersionGuard`** (`lib/service/configuration/preference_version_guard.dart`) mirrors this on the SharedPreferences
  side: a non-destructive step removes only the keys it made obsolete (`_selectiveRemovals`); a destructive one removes every
  user-created key. Legacy keys that are only ever removed live in `keys/legacy_preference_keys.dart`.
- **History ids are AUTOINCREMENT.** Rows migrated from the v3 database kept their old ids and SQLite continues the sequence after
  the largest one, so ids never collide and a deleted id is never reused (the check-in cancel flow relies on that). New plays go
  through `HistoryRepo.insertNew` / `insertAllNew`; `toInsertable()` always carries an explicit id and is for upserts and tests.
- **SharedPreferences** – wrapped by `KeyValueStore` singleton for settings. Keys are typed string constants in
  `lib/database/key_value_store/keys/`.

---

## Service Layer Patterns

### Snapshots & tracking
The one rule: **a render path never calls TMDB for a tracked title**. A title enters the library through
`LibraryService.ensureTracked(key)` (`lib/service/library/library_service.dart`): tracked → return, no network ever; untracked →
`materialise`, which captures the snapshot in **one request per type** — `TmdbMovieDetailsApi.getRaw` with
`credits,external_ids,videos,images,watch/providers,recommendations,similar,release_dates` appended, `TmdbShowDetailsApi.getRaw`
with the eight fixed appends plus up to 12 `season/N` documents (`maxAppendedSeasons`), the rest through `getSeasonsRaw` 20 at a
time — prunes it (`SnapshotPruner`, `lib/service/catalog/snapshot_pruner.dart`: providers to the configured region, related
capped at 10, images 5 per kind, cast 30, crew dropped, YouTube videos only, `season/N` split out with guest stars capped at 15)
and writes it in one transaction (`CatalogWriter`: the `movies`/`shows` row, the document, season stubs, season documents +
`episodes`). A failed capture throws `TrackingUnavailableException` and writes nothing; a 404 on an untracked title is
`ItemGoneException`. Every write service calls the gate **before** its own write (see *Local writes*).

Pages read through `MovieService.getDetails` / `ShowService.getDetails | getSeason | getEpisode` (`lib/service/movie/`,
`lib/service/show/`): a tracked title returns its stored snapshot immediately (`MovieSnapshot` / `ShowSnapshot` /
`SeasonSnapshot` in `lib/service/catalog/snapshots.dart` wrap the API DTOs; a row whose document is not fetched yet renders a
synthetic one from its columns — `SnapshotFallback`), and the bloc then runs `refreshIfStale` in the background: older than
`SnapshotFreshness.viewTtl` (48 h) or pruned to another region → re-fetch, rewrite, re-emit; any failure is logged and the stale
copy stays. A view refresh of a show re-fetches the root and materialises **new** seasons only, never a season document it
already has. An untracked title is fetched live (`ShowSnapshot.live`), rendered and **discarded** — the only place a page can fail
to load, which it shows as the `DetailsLoadStatus.unreachable` / `notFound` copy (`lib/ui/pages/details/common/`). Season and
episode pages borrow the show's providers and regulars (the snapshot carries both at show level) and add the episode's guest
stars. The remaining caches (OMDb ratings 14 d, provider regions 30 d, genres 30 d, discover page one 1 d) go through
`CacheNeedsUpdate.generalItem`.

**References and deletion.** A title is referenced by a play, a rating, a watchlist row, a favorite or (shows) a `show_states` row.
When the last one goes, the write service calls `LibraryService.onReferenceRemoved`, which queues the title in
`pending_deletions`; `sweepPendingDeletions` (every scheduler tick) deletes the catalogue rows, documents, state, asset jobs and
artwork of anything still unreferenced after `deletionGrace` (7 days), and re-tracking removes the queue row. Nothing is deleted
synchronously, so an undo within the week costs no fetch.

### Discover
One page (`lib/ui/pages/discover/`, route `/discover?type=movies|shows&mode=popular|topRated|trending`, both query
parameters optional) for TMDB's browse lists. The Movies / Shows switch is instant and keeps a loaded list per type; the
filter panel (list, minimum votes, rating, years, per-type genres — movie and TV genre ids are different id spaces) is
Apply-gated and resets both lists. `DiscoverService` maps `popular` to `/discover` sorted by popularity, `topRated` to
`/discover` sorted by vote average with `vote_count.gte` (default 300, the only list the minimum applies to — enforced in
`DiscoverParamsMapper`) and `trending` to `/trending/{movie|tv}/week`, which has no filters and therefore falls back to
`/discover` as soon as any narrowing filter is active. Only page one is cached, under `InternalCacheRepo` (the pruned list items themselves, so page one paints offline), and for top
rated only at the default vote floor. Browsing writes no catalogue rows: the grid renders `BrowseEntry` payloads as `PosterModel`s. A `mode` in the route overrides the persisted list for that visit without saving it.

### Local writes
Every user action is a Drift write — the UI never calls an API to *record* anything. The shape of every write service is the
same: **tracking and validation before, the local rows and the show-status recompute inside one `db.transaction`, hooks /
cascades / artwork after the commit** (an unawaited outbox flush inside drift's transaction zone would land on a closed
transaction). The gate is the one step that can need TMDB, and only for a title that is not in the library yet; the UI maps
`TrackingUnavailableException` to "Needs a connection to add this title to your library" (`DetailsActionResult`,
`MarkAsWatchedOutcome`).

| Action | Service (`lib/service/library/`) |
|---|---|
| Mark watched / remove plays | `WatchHistoryWriteService.addToHistory(target, …, rewatch:, rating:)` — expands a show/season into one row per **aired** episode from the local `episodes` rows (specials only when season 0 is the target), stamps `rightNow` / `custom` / the air date; **every mark inserts, whatever the history holds** — marking a season again logs a new play of each aired episode, marking an episode again logs a rewatch; a future custom instant is an `ArgumentError`; an optional rating rides the same transaction; then `ShowStateService.recomputeShowStatus`, then the watchlist cascade and the artwork drain |
| Rate / un-rate | `RatingService` — movies, shows and episodes only. A season is never rated directly: its score is the average of the user's episode ratings (`RatingService.seasonAverage`, `LibraryMarksService` for the tiles) |
| Watchlist | `WatchlistService` (`lib/service/watchlist/`) — by show id + numbers only |
| Drop ("ignore") a show | `DroppedShowsService` — a facade over `ShowStateService.drop` / `undrop`; dropped is sticky, un-dropping recomputes to watching / watched / no row |
| Favorite / un-favorite | `FavoriteService` — movies and shows only, keyed `(type, tmdb_id)` in `favorite_items` |
| Check in | `CheckInService` — see below |

Every remove calls `LibraryService.onReferenceRemoved` after the commit. "Watched at release" uses the TMDB **air date at local
midnight**: TMDB publishes dates, not instants.

### Show progress, status & up next
Nothing is stored for this; it is **derived at query time**. `ShowProgressQueries`
(`lib/database/sql_store/progress/show_progress_queries.dart`, `customSelect` with `readsFrom`) splices one aired predicate into
every query — `e.season > 0 AND e.air_date IS NOT NULL AND e.air_date <= ?today`, `today` bound from Dart as `'YYYY-MM-DD'`,
never `date('now')` in SQL — and tests a play with `EXISTS` over `history_items`, so rewatches never inflate a count and an
undated announced episode never reads as aired. `showCounts` / `seasonCounts` give aired, watched-aired, watched and total;
`nextEpisode(id, mode)` is the first unplayed non-special episode **after the latest-aired one the user watched** (gaps are
skipped), or after the most recently watched one when the `nextEpisodeBasedOnLastActivity` preference is on; `upNext` is one
statement (window function per show, joined on `show_states.status = 'watching'`, so finished and dropped shows are hidden) with
the release-date filters and the three orderings; `listing` feeds Show Progress and Stats. `ShowProgressCalculator`
(`lib/service/progress/`, pure) survives for the Show Progress page's expanded season / episode chips and documents both
next-episode modes in its tests.

`ShowStateService` (`lib/service/library/show_state_service.dart`) is the **one writer of `show_states.status`**:
`recomputeShowStatus(showId)` — transaction-zone safe, never TMDB — keeps `dropped`, deletes the row when no play remains, and
otherwise writes `watched` iff `aired > 0 AND watchedAired >= aired`, else `watching`, upserting only on change. It runs inside
every history write, check-in and un-drop, and `recomputeAll` runs on every scheduler tick (even offline — a stored episode's
air date passing flips `watched` back to `watching`), after the backfill and after a restore. A show whose `episodes` rows are
not fetched yet reads `watching` until the backfill lands. Movies: `HistoryRepo.isMovieWatched` / `getWatchedMovieIds`.

### Check-in ("watching now")
A check-in is a history row with `action = checkin` dated at the moment the item **ends** (`now + runtime`, fallbacks 40 min /
120 min). While that instant is in the future `HistoryRepo.getCurrentCheckInItems` reports it and `CheckInBloc` (app-wide,
`main.dart`) renders the banner with a 10 s heartbeat; once it passes, the row is an ordinary play. Progress counts the episode
from the start, so nothing has to happen at expiry. One check-in at a time (`CheckInOutcome.alreadyActive`). Cancelling deletes the row.

### Live list refresh
`DataChangeMonitor` (`lib/service/data_change_monitor.dart`) is the one debounced broadcast of "a repository changed" — a
`Set<DataChangeEvent>` (`historyRepo, showStateRepo, watchlistRepo, userRatingRepo, favoriteRepo, catalogRepo`) flushed a second
after the first change. Every list bloc subscribes and re-runs its local query + marks (`refresh`, never `reload`, so the user's
scroll survives); the details blocs re-read only their user rows and keep the parsed snapshot. `catalogRepo` fires on
`movies` / `shows` writes so grids pick up backfilled titles and artwork paths; no bloc writes the catalogue, so nothing loops.

### Bounded fan-out
Anything issuing one TMDB request per item goes through `List.chunked(size)` (`lib/common/extension/list_extension.dart`) +
`Future.wait`, never a bare `await` in a `for` loop and never an unbounded `Future.wait`. Existing sizes: 3 titles (the
scheduler and the backfill), 20 seasons per `getSeasonsRaw`, 4 concurrent image downloads behind an 8/s token bucket
(`RateGate`) in the artwork worker. `TmdbHttpClient` (`lib/api/tmdb/tmdb_http_client.dart`) retries 429/5xx/transport errors with
backoff and honours `retry-after`.

### Poster grids render `PosterModel`
There is no poster table and no per-tile stream. Every grid, row and sheet takes `PosterModel` (`lib/service/poster/poster_model.dart`:
key, title, `posterPath` / `stillPath`, `tracked`, TMDB rating, the user's `LibraryMarks`, milestone flags; `id` is the old
arithmetic `MediaKey.gridId`). `PosterModelBuilder` builds one from a catalogue row (`movie`, `show`, `season`, `episode`), a
snapshot stub (`seasonStub`, `episodeEntry`), an Up Next row or a browse payload (`movieListItem`, `showListItem`);
`PosterModelResolver.resolve(keys)` does it for a list of keys with one `getMany` per table. `LibraryMarksService.load()` reads
the user tables as whole sets once per page load (watched movie / started / finished / dropped show ids, watchlist keys, ratings,
favorites, tracked keys, and the played positions of the shows the caller names) and `mark(models, sets)` stamps them. A bloc
re-runs query + marks on `DataChangeMonitor` events; nothing is fetched to paint a grid, and a tile with no artwork path renders
its title. `PosterWithTitle`, `StillWithTitle`, `Poster` and `PosterGridSliver` are stateless over the model.

### The person page reads only
The person page (`lib/ui/pages/details/person/`, `PersonService` in `lib/service/person/`) writes nothing and fires one request:
`/person/{id}?append_to_response=combined_credits,external_ids`. `PersonService.filmography` folds the cast credits in memory into
one `PersonCredit` per `(kind, id)` (characters joined ` / `, episodes = the largest part's, undated first then newest first, no
cap); `withLibraryMarks` stamps watched / in-history / in-library / watchlisted / user-rating from whole-table set reads
(`HistoryRepo.getWatchedMovieIds` / `getWatchedShowIds`, `ShowStateRepo.getFinishedIds`, `WatchlistRepo.getAll`,
`UserRatingRepo.getAll`), never a query per title. On this page "in library" means a play, a watchlist entry or a rating, and a
show's check mark means *finished* (`show_states.status = 'watched'`). The cards are `PosterModel`s and re-mark on
`DataChangeMonitor` events. Tapping a card opens the title by TMDB id; an untracked title renders live, nothing has to exist first.

### Scheduler: `CatalogRefreshService`
One scheduler (`lib/service/catalog/catalog_refresh_service.dart`), one job row (`CATALOG_REFRESH_JOB_ID = 1`, the thin bar under
the app bar). `tickIfDue()` runs on launch (`AppInitPageBloc`), on resume (`AppResumeHandler`) and from a 6 h foreground
`Timer.periodic` (`startForegroundTimer`), with a 15 min cooldown; `tick()` joins a run in flight and never throws. A tick, in order:
1. **Backfill** (`LibraryBackfillService`): every referenced title whose document is not fetched yet (`fetched_at IS NULL`),
   every unfetched season of a fetched show, and every row pruned to a different region than the configured one, materialised
   3 at a time ("Saving offline copies: N of M…"). Also the reconciliation after a restore or a TMDB pull.
2. **Refresh** (`CatalogRefreshQueries`): *active* titles every 7 days — on the watchlist or favorites, or followed shows (a
   non-dropped state) not ended / canceled, or whose announced `next_episode_air_date` has passed since the last fetch, so Up
   Next moves the day an episode airs; *archive* every 90 days — watched movies and followed ended / canceled shows on no list.
   A show refresh is root + its **open seasons** (the latest, and any with an undated or future episode) + new seasons, one write.
   The `OutageBreaker` stops fetching for the tick after 3 consecutive systemic failures (network / down / rate-limited); a 404
   counts nothing and `stampFetched` silences the row for one interval.
3. `ShowStateService.recomputeAll()` — always, even offline.
4. `LibraryService.sweepPendingDeletions()`.
5. `ArtworkService.drain()`.

### Artwork: assets vs cache
Two trees, structurally separated (`lib/service/artwork/`). **Library artwork** lives under `<app support dir>/assets/`
(Android `files/assets/`, excluded from Auto Backup by `res/xml/backup_rules.xml` and `data_extraction_rules.xml`) in a fixed
layout — `video/{movies,shows}/<id>/poster.jpg`, `backdrop.jpg`, `cast/<profile basename>`, shows also `seasons/<n>/poster.jpg`
and `episodes/<s>-<e>/still.jpg` (`ArtworkPaths`); one size per kind (`ArtworkSizes`: posters at the poster-quality size capped
at `w780`, backdrops `w1280`, stills at the still-quality size, cast `w185`). What is kept is what the app renders: no galleries.
After every snapshot write the service builds an `ArtworkManifest` from the **stored** rows (`CatalogArtworkManifests`) and calls
`ArtworkService.itemTracked` / `itemRefreshed`: `ArtworkReconciler` deletes files the manifest no longer names and
`AssetDownloadQueue` inserts the rest as `asset_jobs` (idempotent on `dest_path`; a file already on disk is inserted `done`;
stills only for episodes airing within 7 days). `AssetDownloadWorker.drain()` (job 3, launch after 2 s, resume, after a
track / refresh / backfill, from Settings; `pause()` on app pause) downloads 4 at a time behind the 8/s gate, promoting a browse
cache copy when one exists, writes `<dest>.part` and renames; a 404 is `failed('notFound')` (the next snapshot carries a new
path), an own failure backs off 1 m / 10 m / 1 h / 6 h and fails after 5, network / 5xx / 429 stop the drain and keep everything.
`ArtworkStore` is the only code that deletes under `assets/`. `ArtworkIndex` (the set of present relative paths, loaded at
startup within 1.5 s, maintained by the worker, with an `arrivals` stream) feeds `ArtworkResolver.resolve(ref)` — local file →
TMDB URL → nothing — and the `ArtworkImage` widget (`lib/ui/common/artwork/`), which every poster, still, banner and cast card
renders through with an `ArtworkRef`.

The **browse cache** (`lib/service/artwork/cache/artwork_cache.dart`) is a `flutter_cache_manager` instance (`tbBrowseImages`,
14 days / 600 objects, under the temporary directory) for everything untracked: search, discover, people, provider logos, live
views. The file imports nothing that knows the assets root and owns no delete code beyond `emptyCache()`; a structural test pins
that. Both trees build URLs with the same `ArtworkSizes`, so a cached browse file is byte-identical and promotable. Settings
shows the library's size and the queue (`ArtworkService.storageSummary`), re-queues every tracked manifest
(`redownloadMissing`) and clears the browse cache.

### JSON backup export & restore

`BackupExportService` (`lib/service/backup/`) writes the Settings-page backup — history, ratings, watchlist and favorites — as one
JSON file, currently **`schemaVersion` 5** (4 added the section as `recommended`: movie and show entries with a `recommendedAt`;
5 renamed it to `favorites` with a `favoritedAt`, which the external importer has to follow). An
external importer (sofalog) is built against that exact shape, so any change to it (a renamed or
moved key, a different timestamp format) **bumps the version**; never change the payload under an existing number. Entries carry
`type`, `tmdbId` (the row key for movies/shows, the season's/episode's own TMDB id — nullable — for those), `imdbId` where known
(movies, shows, episodes), and the show-scoped keys `showTmdbId`/`season` on season and episode entries (`episode` only on episode
ones). Every timestamp is `.toUtc().toIso8601String()` (UTC with a `Z` suffix). Payload building (`buildBackupPayload`) is separate
from the file write so it is testable without `path_provider`.

The file leaves and enters the device through the system pickers (`ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT`) on the
`ticket_box/backup_files` method channel in `MainActivity` (`BackupFileSaver`, `BackupFilePicker`), so no storage permission is needed.
**Restore replaces, never merges.** `BackupImportService` accepts `schemaVersion` 3, 4 and 5 (v3 has no favorites section, so the current list is
kept; v4's `recommended` section restores into the favorites) and parses the whole file before writing anything: entries are keyed back to the user-table key (`tmdbId` for movies/shows,
`showTmdbId`/`season`/`episode` otherwise; the season's/episode's own ids are ignored), season ratings are skipped. `BackupRestoreRepo`
then swaps history, ratings, watchlist (and favorites) in **one batch**, history rows getting fresh AUTOINCREMENT ids. A restore is
a tracking action: every restored title gets a `(tmdb_id, tracked_at)` stub row when it has none, the non-dropped `show_states`
rows and `pending_deletions` are cleared, and `BackupImportService.restore` then runs `ShowStateService.recomputeAll`,
`LibraryService.enqueueUnreferenced` and `CatalogRefreshService.tick()`, whose backfill fetches the snapshots (and retries on the
next tick when offline). Dropped shows are not in the backup and stay.

### TMDB account sync

Optional, off until the user logs in from Settings. Everything lives in `lib/service/tmdb_account/`; the rules in one place
are `TmdbSyncSupport` (what can be synced, rating rounding).

- **Login** is TMDB's v3 flow: `TmdbSessionService.beginLogin` gets a request token (`TmdbAuthenticationApi`), the page opens
  `https://www.themoviedb.org/authenticate/{token}?redirect_to=ticketbox://tmdb-auth` in the browser, TMDB redirects to that
  scheme with `request_token=…&approved=true` (or `denied=true`), the `AndroidManifest.xml` intent-filter + `app_links` deliver
  it to `TmdbAuthLinkHandler`, and `completeLogin` turns it into a `session_id` + `/account`. The session id is a **query
  parameter** on every account call, next to the app's bearer token (`TmdbHttpClient` is unchanged). It is stored in
  SharedPreferences (`TmdbAccountKeys`) like every other preference; a pending request token survives process death, and
  `AppInitPageBloc` lands on Settings when the app was opened by the approval link. Flutter's own deep linking is turned off in
  the manifest so it does not compete with `app_links`; `MainActivity` needs no `onNewIntent` — the plugin registers its own.
- **Mapping.** Ratings ↔ TMDB ratings (movies, shows, episodes; the app's whole 1–10 goes out as a double, TMDB's half steps
  come in rounded half up). Watchlist ↔ TMDB watchlist and Favorites ↔ TMDB **favorites** (the list took TMDB's name; its sync toggle
  still lives under the `tmdb_account_sync_recommended` key it shipped with), both whole titles only: the app's
  season/episode watchlist rows never leave the device and a pull leaves them alone (`WatchlistRepo.replaceMoviesAndShows`).
  TMDB has no "added at" on v3 list rows, so pulled rows are stamped `now`. TMDB removes a title from its watchlist when it is
  rated (an account setting of theirs).
- **One-time sync** (`TmdbInitialSyncService.run(choices)`, after login and from "Sync now"): per data set *pull* (download
  every page, then `replaceAll` in one batch — a failure half-way changes nothing; a pull is a tracking action, so pulled titles
  get stub catalogue rows, titles the pull removed are queued for the deletion sweep, and a `CatalogRefreshService.tick()` at the
  end backfills the snapshots), *push* (send every local item, chunked 4;
  a refused item is queued, the first sign TMDB is unreachable queues the rest) or *skip*. Reports on the `JobStates` row
  `TMDB_SYNC_JOB_ID = 2` (the app-bar indicator watches jobs 1 and 2 via `JobStateRepo.streamAnyRunning`). A pulled or pushed
  data set gets its toggle turned on.
- **Live sync is a write-ahead outbox.** `RatingService`, `WatchlistService` and `FavoriteService` call `TmdbSyncHooks`
  after their local write; when logged in and the toggle is on, the hook `enqueue`s a `tmdb_sync_outbox` row and starts a
  flush. The outbox holds **one row per data set and key** (the newest intent replaces the older; add-then-remove stays a
  remove because the add may have landed). `TmdbSyncOutboxService.flush()` (single in-flight, never throws) walks the queue
  by id in chunks of 4: delivered → deleted; 404 → dropped; a failure of the row's own → retried, dropped after 5 attempts;
  network / 5xx / 429 → **stop and keep everything** for the next launch (`AppInitPageBloc`) or resume (`AppResumeHandler`);
  a session 401 (`ApiUnauthorizedException.isSessionProblem`) → `invalidateSession()` and stop. A hook failure is logged, never
  rethrown: the local write always wins. Turning a toggle off drops that data set's pending rows; a pull drops them too.
- **The two watchlist bypasses are gone**: `WatchHistoryWriteService` and `CheckInService` clear watchlist rows through
  `WatchlistService.clearForWatched`, which hooks only a movie/show row that actually existed. Keep it that way — a repo-level
  watchlist delete anywhere else would silently miss TMDB. A backup restore is deliberately *not* propagated (it empties the
  outbox; "Sync now → push" sends the restored lists).
- **Invalid session** keeps the username, the toggles and the outbox; Settings shows "log in again" and a new login resumes
  the queue. **Logout** revokes the session (best effort), removes every `TmdbAccountKeys` key, turns the toggles off and empties
  the outbox. Local data is never touched by either.

### Google Play Billing (donations)

`DonationService` (`lib/service/donation/`) is the only thing in the app that touches `in_app_purchase`. It owns the process's **single** `purchaseStream` subscription, attached from `_loadMainInternalServices()` — not from the donate page — because unfinished purchases arrive there: a subscription unacknowledged for 3 days is auto-refunded by Play, and a slow payment can settle while the app is closed. Its `initialize()` is wrapped in a `catch` at the call site: billing must never be able to fail `configureApp` and drop the user on `StartUpErrorApp`.

Invariants that are easy to break:
- **`isSupported` is `Platform.isAndroid`, and every entry point checks it first.** `InAppPurchase.instance` only registers a platform on Android/iOS/macOS; on the Linux and Windows builds the platform instance is a `late` field that is never assigned, so the *first read* throws `LateInitializationError`. That is also why the Settings tile is behind the same check.
- **One-time products are consumed explicitly, never via `autoConsume: true`.** The plugin tracks ids to auto-consume in a per-process in-memory set that only a `buyConsumable` call in the *same session* fills, so a purchase delivered at start-up would silently never be consumed — permanently blocking that tier for that user. `_deliver` calls `InAppPurchaseAndroidPlatformAddition.consumePurchase` for both `purchased` and `restored`, and skips `completePurchase` on success because consuming already acknowledges.
- **Never `completePurchase` a `pending` purchase** — it throws. Play re-delivers it once it settles.
- **Three separate subscription products, one base plan each** (`DonationProducts`). Base plans of a single product all come back with the same `ProductDetails.id`, and `PurchaseDetails.productID` carries no base plan, so tiers would be indistinguishable without a backend.
- **Prices always come from `ProductDetails.price`.** Play prices are per country; a €1 base price is only literally €1 in the eurozone. Its `title` is unusable — Play appends the app name in brackets.
- Purchases are deliberately **not** verified server-side. Donating unlocks nothing, so there is nothing to gain from spoofing one, and nothing is persisted about who donated.

---

## External APIs

API keys (TMDB v3 + v4 read token, OMDB) are compiled in from the gitignored `secrets.json` via `--dart-define-from-file=secrets.json`
and read in `lib/api/api_keys.dart`; never commit them. Every TMDB wrapper under `lib/api/tmdb/v3/`
sends through `TmdbHttpClient.instance` (bearer v4 token, retries); shared decoding lives in `lib/api/http/response_decoding.dart`.
Single-item wrappers return `null` on 404; list wrappers throw `ApiNotFoundException`. `TmdbMovieDetailsApi.getRaw` /
`TmdbShowDetailsApi.getRaw(id, appendSeasons:)` return the raw body for the snapshot store (the typed `get` wraps it);
`getRaw` accepts at most 12 seasons per call (TMDB's 20-key `append_to_response` limit minus the eight fixed appends) and
`getSeasonsRaw` 20. `OmdbDetailsApi.getEpisode(showImdbId, season, episode)` is how an episode learns its own IMDb id.

TMDB's terms require attribution: the About page carries the TMDB logo and the sentence *"This product uses the TMDB API but is
not endorsed or certified by TMDB."* Keep it.

---

## Routing

`go_router` configuration in `lib/ui/routes.dart`. There is no sign-in page and no auth guard; every route is reachable (the
TMDB login happens in the browser and lands back on Settings). Details
routes are `/movie/:tmdbId`, `/show/:showTmdbId`, `/show/:showTmdbId/season/:season`,
`/show/:showTmdbId/season/:season/episode/:episode` and `/person/:personTmdbId`; the browse page is
`/discover?type=movies|shows&mode=popular|topRated|trending` (see Discover above); `PosterNavigation`
(`lib/ui/common/poster/poster_tap_navigation.dart`) is the only place that spells those parameters. The person route also
takes an optional `PersonRouteArgs` as go_router `extra` — the tapped cast card's name and headshot URL, a paint-ahead hint
the hero header shows from the first frame until the person request overwrites it; a deep link carries none and the page
starts blank as before. The drawer's **Lists**
destination (`/lists`) lists the user's lists — today only the built-in **Watchlist** (`/watchlist`), **Dropped Shows**
(`/lists/dropped-shows`, every `DroppedItems` row as a show poster grid, long press to un-drop) and **Favorites**
(`/lists/favorites`, every `FavoriteItems` row as a mixed poster grid behind a collapsible Everything / Movies / Shows
Filters panel, applied with Apply Filters and not persisted, long press to remove). Watchlist is no longer a drawer
entry of its own; it keeps its top-level route so a stored landing page of Watchlist still resolves, and it shows the drawer
only when it is the root page (a back arrow when opened from Lists). The drawer's `_parentDestination` map keeps Lists
highlighted on those sub-pages. `/` redirects to `/app-init`,
whose bloc loads preferences, binds the resume handler, starts the catalogue refresh tick when due (and its foreground timer),
kicks the artwork drain and lands on the user's default
landing page (a drawer destination) or Up Next.

---

## Adaptive UI

`AdaptiveLayoutBuilder` (`lib/ui/adaptive_layout_builder.dart`) resolves mobile/tablet/desktop widgets via `LayoutBuilder` breakpoints defined in `FormFactor`. Use `AdaptiveLayoutBuilder.single(child: ...)` when the same widget serves all form factors.

---

## System bar insets (edge-to-edge)

`targetSdk 36` means Android 15+ draws the app edge-to-edge with **no opt-out** — `windowOptOutEdgeToEdgeEnforcement` is deprecated and ignored on Android 16. `main()` also calls `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` so API 29–34 behave the same rather than only the newest devices going edge-to-edge.

**Never wrap a `Scaffold` in a `SafeArea`.** That was the original bug: it inset the Scaffold itself, so Flutter painted nothing into the bar strips and the transparent strips revealed the Android window background — which resolved *white* in day mode behind a dark-only app. Each edge now has exactly one owner:

| Edge | Owner |
|---|---|
| Top | The `AppBar`/`SliverAppBar` itself — `topPadding = primary ? MediaQuery.paddingOf(context).top : 0` |
| Bottom | `SliverBottomInset` (`lib/ui/common/sliver_bottom_inset.dart`), appended as the **last sliver** of every `CustomScrollView` |
| Left/right | One `SafeArea(top: false, bottom: false)` in `MaterialApp.router`'s `builder` in `main.dart` |
| The drawer | Its own `SafeArea(bottom: false)` in `navigation_drawer_widget.dart` |

Consequences worth knowing before "tidying" any of it:

- **Pages with no app bar keep a real `SafeArea` inside `Scaffold.body`** — nothing else supplies their top inset. That is app init, sign-in, sign-in error, sync error and full sync info. Do not make them match the others.
- **`SliverBottomInset` is needed because `CustomScrollView` does nothing on its own.** `ListView`/`GridView` absorb `MediaQuery.padding` themselves when `padding` is null; `CustomScrollView` does not. It is safe inside a `const` sliver list — reading `MediaQuery` registers an inherited dependency, unlike `ScreenSizeUtil`'s static globals.
- **The horizontal `SafeArea` is not optional.** No app bar absorbs left/right insets, so without it a landscape display cutout puts the camera over the app bar title. This *is* reproducible on the Pixel10Pro emulator in landscape.
- Content deliberately scrolls **under** the status bar on pages whose app bar is `floating: true, pinned: false`. That is intended edge-to-edge behaviour, not a regression.

Verify in **light** system mode (`adb shell cmd uimode night no`) — the day/night divergence this replaced was invisible in dark mode. `res/values/colors.xml` defines `window_background` (`#FF212121`, matching `ThemeColors.greyScale900`) and is used by both `launch_background.xml` variants and both `NormalTheme` styles, with no `values-night` override, on purpose.

The Play Console warning **"Edge-to-edge may not display for all users"** is unrelated to any of this and cannot be fixed here — it is Play's bytecode scan finding deprecated `Window.setStatusBarColor`/`setNavigationBarColor` calls inside the Flutter engine's `PlatformPlugin` and inside `net.openid.appauth`. It is non-blocking.

---

## Theming

**Dark-only.** `main.dart` points *both* of `MaterialApp`'s theme slots at `ThemeDefinition.darkTheme` so no light fallback can ever surface. There is no light `ColorScheme` and no theme switching — don't add one without unwinding the 15 `textTheme` roles that `theme_definition.dart` pins to `ThemeColors.white`.

**Red is the accent; pink is loading.** `ThemeColors.primary` (`#F5484A`, red) drives the chrome — nav selection, chips, switches, buttons, rating hearts. The logo pink `#E91E63` has exactly one job: progress indicators.

**The `ColorScheme` is hand-authored — never paste Material Theme Builder output into `theme_definition_colors.dart`.** It *was* builder output, and every role carried the builder's warm pink: `surfaceContainerHighest` `#534342`, `onSurfaceVariant` `#D8C2C0`, `primary` a pale `#FFB3AE`. Because the app leans on those two roles hardest — `surfaceContainerHighest` backs every `DetailsCard`, breadcrumb and progress track (mostly composited at `alpha 0.25–0.35`), `onSurfaceVariant` every piece of secondary text — the whole app read pink-tinted, contradicting the rule directly above. Two invariants keep it clean:

- **Every surface, foreground and line role is a neutral grey** (R = G = B), drawn from the `ThemeColors` greyscale. So is the `dark1`–`dark4` elevation ladder, which used to be cool blue-greys (`dark2` was `#1F222A`) and fought the warm scheme from the other side.
- **Every accent role is the red** — including `secondary` and `tertiary`, which have no separate job here. Leaving them on a builder pink is how an M3 widget nobody has sub-themed sneaks the tint back in.

Note that `colorScheme.surfaceTint` is **inert** as of Flutter 3.44: every M3 component default now sets `surfaceTintColor: Colors.transparent`, so the elevation overlay never runs. Pink from an M3 theme is a role value, not an overlay — look there first.

Set the `surfaceContainer*` roles explicitly. Omitting one is silent, not an error: Flutter falls it back to `surface` (`surfaceContainerHigh => _surfaceContainerHigh ?? surface`), which is why date pickers — they default to `surfaceContainerHigh` — sat flat against the page for so long.

**Never hand-apply the pink.** It is set once, as `progressIndicatorTheme` in `theme_definition.dart`. Flutter resolves an indicator's colour as `valueColor ?? color ?? ProgressIndicatorTheme.color ?? colorScheme.primary`, so *every* `LinearProgressIndicator` and `CircularProgressIndicator` is pink for free — a new one needs no colour argument, and passing `ThemeColors.loadingIndicator` by hand is a smell. Only three indicators override it, because they are colour-coded to an action rather than being generic loading: the check-in banner bar (red), the details watch-progress bar (violet), and the watchlist toggle spinner (blue).

**The fill/accent rule.** A colour dark enough to sit behind white text is usually too dark to *be* text on a dark surface, so the action colours come in pairs and picking the wrong half is the bug this convention prevents:

| Job | Use | Must clear |
|---|---|---|
| Behind a white label or icon (a *fill*) | `actionCheckIn`, `actionMarkWatched`, `actionWatchlist` | 4.5:1 vs white |
| Drawn onto the dark surface as text, icon or border (an *accent*) | `action*Accent` | 4.5:1 vs `greyScale900` |

`ThemeColors.primary` needs no such pair — at 4.53:1 on `greyScale900` it works as both. Note it is only 3.55:1 behind white, so the `ElevatedButton` label is below AA; that is a known, long-standing tradeoff, kept because any darker red would collide with the check-in action.

Action colours are read through the `ActionColors` `ThemeExtension` (`lib/ui/theme/action_colors.dart`), never inlined:

```dart
final actions = context.actionColors;   // check in · mark as watched · add to watchlist
```

Check in is red, mark as watched violet, add to watchlist blue — one colour each, used consistently by the buttons, the poster pills and the details badges. `ActionColors` is hand-written; it is **not** covered by `build_runner`, so adding a field means updating `copyWith` and `lerp` by hand.

New colours belong in `ThemeColors` as named tokens. Reaching for `Colors.*` in a widget is how the palette drifted before — the pink used to be patched in that way at 12 separate call sites.

---

## Key Files

| File | Purpose |
|---|---|
| `lib/service/configuration/start_up_configuration_service.dart` | App bootstrap & DI wiring (incl. `ArtworkService.initialize`) |
| `lib/database/sql_store/database_connection_manager.dart` | All Drift tables + the stepwise/destructive migration |
| `lib/database/sql_store/migration/legacy_ddl.dart` | The v4-shape DDL `_migrateV3ToV4` restores after `createAll()` |
| `lib/service/configuration/preference_version_guard.dart` | Preference cleanup that mirrors the migration |
| `lib/api/tmdb/tmdb_http_client.dart` | The one TMDB HTTP client (auth, retries) |
| `lib/service/library/library_service.dart` | The tracking gate, reference counting, deferred deletion |
| `lib/service/catalog/snapshot_pruner.dart` / `snapshots.dart` | What a stored document keeps; the read models over it |
| `lib/service/catalog/catalog_writer.dart` | The one transaction that writes a snapshot |
| `lib/service/catalog/catalog_refresh_service.dart` | The scheduler: backfill, refresh, state sweep, deletions, artwork |
| `lib/service/library/show_state_service.dart` | The one writer of `show_states.status` |
| `lib/database/sql_store/progress/show_progress_queries.dart` | Derived counts, next episode, Up Next, the progress listing |
| `lib/service/library/watch_history_write_service.dart` | All history writes (expansion, release dates, watchlist cascade) |
| `lib/service/library/check_in_service.dart` | Local "watching now" |
| `lib/service/artwork/artwork_service.dart` | Facade over the artwork store, queue, worker, reconciler |
| `lib/service/poster/poster_model.dart` / `library_marks_service.dart` | What every grid tile renders and how it is marked |
| `lib/service/tmdb_account/tmdb_session_service.dart` | TMDB login state, session id, sync toggles |
| `lib/service/tmdb_account/tmdb_sync_outbox_service.dart` | Drains the TMDB sync outbox |
| `lib/service/tmdb_account/tmdb_initial_sync_service.dart` | One-time pull / push per data set |
| `lib/service/tmdb_account/tmdb_sync_hooks.dart` | What the write services call to queue a TMDB copy |
| `lib/ui/routes.dart` | All named routes |
| `lib/ui/common/poster/poster_tap_navigation.dart` | The only place that knows the details routes' parameters |
| `lib/common/model/media_key.dart` / `media_ref.dart` | Identity types shared by every layer |
| `lib/ui/theme/theme_colors.dart` | The colour token palette — every colour starts life here |
| `lib/ui/theme/theme_definition.dart` | `ThemeData` incl. `progressIndicatorTheme`, the single source of the loading pink |
| `lib/ui/theme/action_colors.dart` | `ActionColors` ThemeExtension: check-in / watched / watchlist |
| `tool/make_v3_fixture.dart` / `tool/make_v9_fixture.dart` | Seeded old-schema database files for testing the migration on a device |

---

