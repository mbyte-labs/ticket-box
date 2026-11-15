import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';

part 'settings_state.freezed.dart';

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    /// True until the country list has been read (from cache or the API).
    required bool loading,

    /// ISO 3166-1 code of the chosen streaming country, null while the user has not picked one.
    required String? watchProviderRegion,

    /// Countries TMDB reports watch-provider data for, alphabetical by English name. Empty while
    /// loading, or when nothing is cached and the API was unreachable.
    required List<SettingsRegionOption> regions,

    /// True while a backup export is being built, so the "Backup account" tile can disable
    /// itself and show progress instead of being tapped twice.
    required bool exportingBackup,

    /// True while a backup file is being restored, which disables both backup tiles.
    required bool importingBackup,

    /// The connected TMDB account, null while logged out or while the session is invalid.
    required TmdbAccountView? tmdbAccount,

    /// True when TMDB stopped accepting the stored session: the account row asks to log in again.
    required bool tmdbSessionInvalid,

    /// The username of the account whose session became invalid (also set while logged in).
    required String? tmdbLastUsername,

    /// True while the user is approving the app in the browser.
    required bool tmdbLoggingIn,

    /// The data sets whose changes are mirrored to TMDB.
    required Set<TmdbDataSet> tmdbSyncEnabled,

    /// True while the one-time pull / push run is going, which disables the account tiles.
    required bool tmdbSyncRunning,

    /// The sync job's progress line, shown under the "Sync now" tile while it runs.
    required String? tmdbSyncMessage,

    /// Changes waiting in the outbox to reach TMDB.
    required int tmdbPendingPushes,

    /// True right after a login, until the pull / push / skip dialog has been shown.
    required bool tmdbInitialSyncPromptPending,

    /// A one-shot message for a SnackBar (login outcome, sync result); cleared once shown.
    required String? tmdbNotice,

    /// What the library artwork takes on disk and what the download queue holds; null until read.
    required ArtworkStorageSummary? artwork,

    /// True while the artwork worker is downloading (its job row is running).
    required bool artworkDownloading,

    /// True while one of the artwork actions (re-download, clear cache) runs from this page.
    required bool artworkBusy,
  }) = _SettingsState;

  factory SettingsState.initial() {
    return const SettingsState(
      loading: true,
      watchProviderRegion: null,
      regions: [],
      exportingBackup: false,
      importingBackup: false,
      tmdbAccount: null,
      tmdbSessionInvalid: false,
      tmdbLastUsername: null,
      tmdbLoggingIn: false,
      tmdbSyncEnabled: {},
      tmdbSyncRunning: false,
      tmdbSyncMessage: null,
      tmdbPendingPushes: 0,
      tmdbInitialSyncPromptPending: false,
      tmdbNotice: null,
      artwork: null,
      artworkDownloading: false,
      artworkBusy: false,
    );
  }
}

/// The connected TMDB account as the Settings page shows it.
@freezed
abstract class TmdbAccountView with _$TmdbAccountView {
  const factory TmdbAccountView({required String username, required String displayName}) = _TmdbAccountView;
}

extension SettingsStateLookups on SettingsState {
  /// Display name of the chosen streaming country, null while unset or before the list loaded.
  String? get watchProviderRegionName {
    final region = watchProviderRegion;
    if (region == null) {
      return null;
    }
    for (final option in regions) {
      if (option.code == region) {
        return option.name;
      }
    }
    // The list has not loaded (or the code vanished from TMDB's list) — the bare code still
    // beats pretending nothing is selected.
    return region;
  }
}

/// One entry of the streaming-country picker.
@freezed
abstract class SettingsRegionOption with _$SettingsRegionOption {
  const factory SettingsRegionOption({required String code, required String name}) = _SettingsRegionOption;
}
