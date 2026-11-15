import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/backup/backup_export_service.dart';
import 'package:ticketbox/service/backup/backup_import_service.dart';
import 'package:ticketbox/service/catalog/catalog_artwork_manifests.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_auth_link_handler.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_initial_sync_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';
import 'package:ticketbox/service/watch_provider/watch_provider_regions_service.dart';
import 'package:ticketbox/ui/pages/settings/settings_state.dart';

class SettingsBloc extends Cubit<SettingsState> {
  static final _log = Logger('SettingsBloc');

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  SettingsBloc() : super(SettingsState.initial());

  Future<void> init() async {
    _bindTmdb();
    _bindArtwork();
    unawaited(refreshArtworkSummary());

    final region = await KeyValueStore.instance().getString(GeneralPropertiesKeys.watchProviderRegion);
    if (isClosed) return;
    emit(state.copyWith(watchProviderRegion: region));

    // Cached for 30 days, so this only hits the network on the first visit in a month.
    final regions = await WatchProviderRegionsService().getAvailableRegions();
    if (isClosed) return;
    emit(
      state.copyWith(
        loading: false,
        regions: regions.map((e) => SettingsRegionOption(code: e.iso3166_1, name: e.englishName)).toList(),
      ),
    );
  }

  Future<void> setWatchProviderRegion(String code) async {
    _log.fine('Setting watch provider region to $code');
    await KeyValueStore.instance().setString(GeneralPropertiesKeys.watchProviderRegion, code);
    if (isClosed) return;
    emit(state.copyWith(watchProviderRegion: code));
  }

  /// Falls back to not showing streaming availability anywhere in the app.
  Future<void> clearWatchProviderRegion() async {
    _log.fine('Clearing watch provider region');
    await KeyValueStore.instance().remove(GeneralPropertiesKeys.watchProviderRegion);
    if (isClosed) return;
    emit(state.copyWith(watchProviderRegion: null));
  }

  /// Builds the history + ratings + watchlist backup file, or `null` if that failed — the caller is
  /// responsible for surfacing the failure and for sharing the file on success.
  Future<File?> exportBackup() async {
    if (isClosed) return null;
    emit(state.copyWith(exportingBackup: true));

    File? file;
    try {
      file = await BackupExportService().buildBackupFile();
    } catch (e, stackTrace) {
      _log.severe('Failed to build backup file', e, stackTrace);
    }

    if (isClosed) return file;
    emit(state.copyWith(exportingBackup: false));
    return file;
  }

  /// Parses a picked backup file. Throws a [BackupFormatException] carrying a user-facing message
  /// when the file cannot be restored.
  BackupContents parseBackup(String json) => BackupImportService().parse(json);

  /// Replaces the user data with [contents]. Returns `false` if the write failed, in which case
  /// nothing was changed (the restore is one transaction).
  Future<bool> restoreBackup(BackupContents contents) async {
    if (isClosed) return false;
    emit(state.copyWith(importingBackup: true));

    var restored = false;
    try {
      await BackupImportService().restore(contents);
      restored = true;
    } catch (e, stackTrace) {
      _log.severe('Failed to restore backup', e, stackTrace);
    }

    if (isClosed) return restored;
    emit(state.copyWith(importingBackup: false));
    return restored;
  }

  // --- TMDB account -------------------------------------------------------------------------------

  /// Mirrors the session service, the sync job row and the outbox into the state, live.
  void _bindTmdb() {
    if (_subscriptions.isNotEmpty) {
      return;
    }
    final session = TmdbSessionService.instance();
    _applySession(session);
    _subscriptions.add(session.changes.listen((_) => _applySession(session)));
    _subscriptions.add(session.loginOutcomes.listen(_showLoginOutcome));
    _subscriptions.add(
      JobStateRepo().streamChanges(TMDB_SYNC_JOB_ID).listen((job) {
        if (isClosed) return;
        emit(state.copyWith(tmdbSyncRunning: job?.state == JobState.running, tmdbSyncMessage: job?.userMessage));
      }),
    );
    _subscriptions.add(
      TmdbSyncOutboxRepo().watchCount().listen((count) {
        if (isClosed) return;
        emit(state.copyWith(tmdbPendingPushes: count));
      }),
    );
  }

  /// The artwork job row: the tile shows "downloading" while it runs and re-measures when it ends.
  void _bindArtwork() {
    _subscriptions.add(
      JobStateRepo().streamChanges(ARTWORK_DOWNLOAD_JOB_ID).listen((job) {
        if (isClosed) return;
        final running = job?.state == JobState.running;
        final wasRunning = state.artworkDownloading;
        emit(state.copyWith(artworkDownloading: running));
        if (wasRunning && !running) {
          unawaited(refreshArtworkSummary());
        }
      }),
    );
  }

  Future<void> refreshArtworkSummary() async {
    try {
      final summary = await ArtworkService.instance().storageSummary();
      if (isClosed) return;
      emit(state.copyWith(artwork: summary));
    } catch (e, stackTrace) {
      _log.warning('Could not measure the library artwork: $e', e, stackTrace);
    }
  }

  /// Queues every library file that is missing or failed before and downloads it. Returns false
  /// when the queue could not be rebuilt.
  Future<bool> redownloadMissingArtwork() async {
    if (state.artworkBusy) return false;
    emit(state.copyWith(artworkBusy: true));
    try {
      final manifests = await _libraryManifests();
      await ArtworkService.instance().redownloadMissing(manifests);
      return true;
    } catch (e, stackTrace) {
      _log.severe('Re-downloading the library artwork failed', e, stackTrace);
      return false;
    } finally {
      if (!isClosed) {
        emit(state.copyWith(artworkBusy: false));
        unawaited(refreshArtworkSummary());
      }
    }
  }

  /// Empties the browse image cache (search, discover, people, untracked titles). The library
  /// artwork is untouched.
  Future<void> clearBrowseCache() async {
    if (state.artworkBusy) return;
    emit(state.copyWith(artworkBusy: true));
    try {
      await ArtworkService.instance().clearBrowseCache();
    } finally {
      if (!isClosed) {
        emit(state.copyWith(artworkBusy: false));
        unawaited(refreshArtworkSummary());
      }
    }
  }

  /// One manifest per tracked movie and show, built from the stored catalogue.
  Future<List<ArtworkManifest>> _libraryManifests() async {
    final manifests = CatalogArtworkManifests();
    final (movieIds, showIds) = await (MovieRepo().getAllIds(), ShowRepo().getAllIds()).wait;
    final result = <ArtworkManifest>[];
    for (final id in movieIds) {
      final manifest = await manifests.forMovie(id);
      if (manifest != null) result.add(manifest);
    }
    for (final id in showIds) {
      final manifest = await manifests.forShow(id);
      if (manifest != null) result.add(manifest);
    }
    return result;
  }

  void _applySession(TmdbSessionService session) {
    if (isClosed) return;
    final snapshot = session.session;
    emit(
      state.copyWith(
        tmdbAccount: snapshot == null ? null : TmdbAccountView(username: snapshot.username, displayName: snapshot.displayName),
        tmdbSessionInvalid: session.sessionInvalid,
        tmdbLastUsername: session.lastUsername,
        tmdbLoggingIn: session.hasPendingLogin,
        tmdbSyncEnabled: session.enabledDataSets,
        tmdbInitialSyncPromptPending: session.initialSyncPromptPending,
      ),
    );
  }

  void _showLoginOutcome(TmdbLoginOutcome outcome) {
    final notice = switch (outcome) {
      TmdbLoginOutcome.loggedIn => 'Logged in to TMDB as ${TmdbSessionService.instance().lastUsername}',
      TmdbLoginOutcome.denied => 'The TMDB login was not approved.',
      TmdbLoginOutcome.expired => 'The TMDB login expired. Try again.',
      TmdbLoginOutcome.failed => 'Could not finish the TMDB login. Check your connection and try again.',
      TmdbLoginOutcome.notPending => null,
    };
    if (notice != null) {
      _notice(notice);
    }
  }

  void _notice(String message) {
    if (isClosed) return;
    emit(state.copyWith(tmdbNotice: message));
  }

  /// Marks the current notice as shown.
  void clearTmdbNotice() {
    if (isClosed || state.tmdbNotice == null) return;
    emit(state.copyWith(tmdbNotice: null));
  }

  /// Starts a TMDB login and returns the approval page to open in the browser, or null (with a
  /// notice set) when TMDB could not be reached.
  Future<Uri?> loginWithTmdb() async {
    try {
      return await TmdbSessionService.instance().beginLogin(TmdbAuthLinkHandler.redirectUri);
    } catch (e, stackTrace) {
      _log.severe('Could not start the TMDB login', e, stackTrace);
      _notice('Could not reach TMDB. Check your connection and try again.');
      return null;
    }
  }

  Future<void> cancelTmdbLogin() => TmdbSessionService.instance().cancelPendingLogin();

  Future<void> logoutTmdb() async {
    try {
      await TmdbSessionService.instance().logout();
      _notice('Logged out of TMDB. Your data stays on this device.');
    } catch (e, stackTrace) {
      _log.severe('Could not log out of TMDB', e, stackTrace);
      _notice('Could not log out. Please try again.');
    }
  }

  /// Turns the live mirroring of [dataSet] on or off. Off drops the changes still queued for it;
  /// on sends whatever is waiting.
  Future<void> setTmdbSync(TmdbDataSet dataSet, bool enabled) async {
    try {
      await TmdbSessionService.instance().setSyncEnabled(dataSet, enabled);
      if (enabled) {
        unawaited(TmdbSyncOutboxService.instance().flush());
      } else {
        await TmdbSyncOutboxRepo().deleteByDataSet(dataSet);
      }
    } catch (e, stackTrace) {
      _log.severe('Could not change the TMDB sync of ${dataSet.name}', e, stackTrace);
      _notice('Could not change the sync setting. Please try again.');
    }
  }

  /// The pull / push / skip dialog is on screen; it must not be opened again on its own.
  Future<void> markInitialSyncPromptShown() => TmdbSessionService.instance().consumeInitialSyncPrompt();

  /// How many local rows a pull would replace, per data set — for the confirmation dialog.
  Future<Map<TmdbDataSet, int>> tmdbLocalCounts() async {
    return {
      TmdbDataSet.ratings: (await UserRatingRepo().getAll()).length,
      TmdbDataSet.watchlist: await WatchlistRepo().count(),
      TmdbDataSet.favorites: await FavoriteRepo().count(),
    };
  }

  /// Runs the one-time pull / push. The job row drives [SettingsState.tmdbSyncRunning]; the
  /// returned summary is for the SnackBar.
  Future<TmdbInitialSyncResult?> runTmdbInitialSync(TmdbSyncChoices choices) async {
    if (choices.isNoOp) {
      return null;
    }
    if (isClosed) return null;
    emit(state.copyWith(tmdbSyncRunning: true));
    try {
      return await TmdbInitialSyncService().run(choices);
    } catch (e, stackTrace) {
      // run() never throws; this only guards the state flag.
      _log.severe('TMDB sync failed unexpectedly', e, stackTrace);
      return null;
    } finally {
      if (!isClosed) {
        emit(state.copyWith(tmdbSyncRunning: false));
      }
    }
  }

  /// Sends the queued changes now, instead of waiting for the next launch or resume.
  Future<void> retryTmdbPushes() => TmdbSyncOutboxService.instance().flush();

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
