// ignore_for_file: constant_identifier_names

/// The catalogue refresh tick: the backfill of missing snapshots, the active / archive refresh of
/// stale ones, the show-state sweep and the deferred-deletion sweep. The same row the progress
/// refresh job used before v10, so the app-bar indicator is unchanged.
const int CATALOG_REFRESH_JOB_ID = 1;

/// The one-time TMDB account sync (pull / push per data set) started from the Settings page.
const int TMDB_SYNC_JOB_ID = 2;

/// The artwork download queue worker.
const int ARTWORK_DOWNLOAD_JOB_ID = 3;

/// The pre-v10 name of [CATALOG_REFRESH_JOB_ID]; the same row.
const int PROGRESS_REFRESH_JOB_ID = CATALOG_REFRESH_JOB_ID;
