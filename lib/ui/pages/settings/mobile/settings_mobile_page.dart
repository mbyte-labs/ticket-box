import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ticketbox/common/byte_size_format.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/service/backup/backup_file_picker.dart';
import 'package:ticketbox/service/backup/backup_file_saver.dart';
import 'package:ticketbox/service/backup/backup_import_service.dart';
import 'package:ticketbox/service/donation/donation_service.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_initial_sync_service.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/settings/settings_bloc.dart';
import 'package:ticketbox/ui/pages/settings/settings_state.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsMobilePage extends StatefulWidget {
  const SettingsMobilePage({super.key});

  @override
  State<SettingsMobilePage> createState() => _SettingsMobilePageState();
}

class _SettingsMobilePageState extends State<SettingsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      drawer: CustomNavigationDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(title: Text('Settings'), floating: true, pinned: false),
          SliverToBoxAdapter(child: _StreamingSection()),
          SliverToBoxAdapter(child: _LibrarySection()),
          SliverToBoxAdapter(child: _AccountSection()),
          SliverToBoxAdapter(child: _SupportSection()),
          SliverBottomInset(),
        ],
      ),
    );
  }
}

class _StreamingSection extends StatelessWidget {
  const _StreamingSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: ScreenSizeUtil.fromLTRB(16, 12, 16, 0),
              child: Text(
                'STREAMING',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('Country'),
              subtitle: Text(
                state.watchProviderRegionName ?? 'Not set — pick one to see where shows stream',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: state.loading ? null : () => _pickCountry(context),
            ),
            Padding(
              padding: ScreenSizeUtil.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your country is used only to look up which streaming services carry a movie or show. '
                      "It's stored on this device and nowhere else.",
                      style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickCountry(BuildContext context) async {
    final bloc = context.read<SettingsBloc>();
    final result = await showModalBottomSheet<_CountryPickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CountryPickerSheet(regions: bloc.state.regions, selectedCode: bloc.state.watchProviderRegion),
    );

    switch (result) {
      case _CountrySelected(:final region):
        await bloc.setWatchProviderRegion(region.code);
      case _CountryCleared():
        await bloc.clearWatchProviderRegion();
      case null:
        break;
    }
  }
}

/// The artwork kept on the device for the library — how much there is, what is still downloading,
/// a way to fetch what failed — and the browse image cache.
class _LibrarySection extends StatelessWidget {
  const _LibrarySection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) =>
          previous.artwork != current.artwork ||
          previous.artworkBusy != current.artworkBusy ||
          previous.artworkDownloading != current.artworkDownloading,
      builder: (context, state) {
        final artwork = state.artwork;
        final busy = state.artworkBusy || state.artworkDownloading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: ScreenSizeUtil.fromLTRB(16, 12, 16, 0),
              child: Text(
                'LIBRARY',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Library artwork'),
              subtitle: Text(_artworkSubtitle(state), style: TextStyle(color: colorScheme.onSurfaceVariant)),
              trailing: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Re-download missing artwork'),
              subtitle: Text(
                artwork == null || artwork.failedJobs == 0
                    ? 'Fetches any library image that is not on the device'
                    : '${artwork.failedJobs} failed before',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              enabled: !busy && artwork != null,
              onTap: () => _redownload(context),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Clear browse cache'),
              subtitle: Text(
                artwork == null
                    ? 'Images from search, discover and people pages'
                    : 'Images from search, discover and people pages — ${formatByteSize(artwork.cacheBytes)}',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              enabled: !busy && artwork != null,
              onTap: () => _clearCache(context),
            ),
          ],
        );
      },
    );
  }

  static String _artworkSubtitle(SettingsState state) {
    final artwork = state.artwork;
    if (artwork == null) {
      return 'Measuring…';
    }
    final parts = [
      '${artwork.assetFiles} ${artwork.assetFiles == 1 ? 'file' : 'files'}, ${formatByteSize(artwork.assetBytes)} on this device',
    ];
    if (state.artworkDownloading) {
      parts.add('downloading');
    } else if (artwork.pendingJobs > 0) {
      parts.add('${artwork.pendingJobs} waiting for a connection');
    }
    return parts.join(' · ');
  }

  Future<void> _redownload(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final succeeded = await context.read<SettingsBloc>().redownloadMissingArtwork();
    messenger.showSnackBar(
      SnackBar(content: Text(succeeded ? 'Missing artwork queued for download' : 'Could not queue the artwork. Please try again.')),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await context.read<SettingsBloc>().clearBrowseCache();
    messenger.showSnackBar(const SnackBar(content: Text('Browse cache cleared')));
  }
}

/// The TMDB account — login, the three sync toggles, "Sync now" and the queue of changes waiting
/// for TMDB — and the personal JSON backup of watch history, ratings and watchlist.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MultiBlocListener(
      listeners: [
        // One-shot messages (login outcome, logout, sync setting failures).
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) => previous.tmdbNotice != current.tmdbNotice && current.tmdbNotice != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.tmdbNotice!)));
            context.read<SettingsBloc>().clearTmdbNotice();
          },
        ),
        // The pull / push / skip dialog, once per login: only the moment the flag turns on counts, and
        // the dialog consumes the flag as it opens, so no later state change can open a second copy.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) => !previous.tmdbInitialSyncPromptPending && current.tmdbInitialSyncPromptPending,
          listener: (context, state) {
            if (state.tmdbAccount != null && !state.tmdbSyncRunning) {
              unawaited(_chooseSync(context, firstTime: true));
            }
          },
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          final busy = state.exportingBackup || state.importingBackup || state.tmdbSyncRunning;
          final account = state.tmdbAccount;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: ScreenSizeUtil.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'ACCOUNT',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant),
                ),
              ),
              if (account == null && !state.tmdbSessionInvalid)
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Log in with TMDB'),
                  subtitle: Text(
                    state.tmdbLoggingIn
                        ? 'Waiting for your approval in the browser…'
                        : 'Keep your ratings, watchlist and favorites on your TMDB account too',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: state.tmdbLoggingIn
                      ? TextButton(onPressed: () => unawaited(context.read<SettingsBloc>().cancelTmdbLogin()), child: const Text('Cancel'))
                      : const Icon(Icons.chevron_right),
                  onTap: busy ? null : () => unawaited(_loginWithTmdb(context)),
                )
              else ...[
                ListTile(
                  leading: Icon(Icons.account_circle_outlined, color: state.tmdbSessionInvalid ? colorScheme.error : null),
                  title: Text(account?.displayName ?? state.tmdbLastUsername ?? 'TMDB account'),
                  subtitle: Text(
                    state.tmdbSessionInvalid ? 'Session expired — log in again' : '@${account?.username}',
                    style: TextStyle(color: state.tmdbSessionInvalid ? colorScheme.error : colorScheme.onSurfaceVariant),
                  ),
                  trailing: TextButton(onPressed: busy ? null : () => unawaited(_logout(context, state)), child: const Text('Log out')),
                ),
                if (state.tmdbSessionInvalid)
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Log in again'),
                    subtitle: Text(
                      state.tmdbLoggingIn ? 'Waiting for your approval in the browser…' : 'Your sync settings and pending changes are kept',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: state.tmdbLoggingIn
                        ? TextButton(
                            onPressed: () => unawaited(context.read<SettingsBloc>().cancelTmdbLogin()),
                            child: const Text('Cancel'),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: busy ? null : () => unawaited(_loginWithTmdb(context)),
                  ),
                for (final dataSet in TmdbDataSet.values)
                  SwitchListTile(
                    secondary: Icon(_dataSetIcon(dataSet)),
                    title: Text('Sync ${dataSet.label.toLowerCase()}'),
                    subtitle: Text(_dataSetSubtitle(dataSet), style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    value: state.tmdbSyncEnabled.contains(dataSet),
                    onChanged: busy || account == null
                        ? null
                        : (enabled) => unawaited(context.read<SettingsBloc>().setTmdbSync(dataSet, enabled)),
                  ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync now…'),
                  subtitle: Text(
                    state.tmdbSyncRunning ? (state.tmdbSyncMessage ?? 'Syncing with TMDB…') : 'Pull from or push to TMDB, per list',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: state.tmdbSyncRunning
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: busy || account == null ? null : () => unawaited(_chooseSync(context, firstTime: false)),
                ),
                if (state.tmdbPendingPushes > 0)
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text('${state.tmdbPendingPushes} ${state.tmdbPendingPushes == 1 ? 'change' : 'changes'} waiting to reach TMDB'),
                    subtitle: Text(
                      state.tmdbSessionInvalid ? 'Sent once you log in again' : 'Sent automatically when TMDB can be reached',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: account == null
                        ? null
                        : TextButton(
                            onPressed: () => unawaited(context.read<SettingsBloc>().retryTmdbPushes()),
                            child: const Text('Retry'),
                          ),
                  ),
              ],
              Padding(
                padding: ScreenSizeUtil.fromLTRB(16, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You log in on themoviedb.org; Ticket Box never sees your TMDB password. '
                        'The session is stored on this device only. Everything else stays local.',
                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Backup account'),
                subtitle: Text(
                  state.exportingBackup ? 'Preparing backup…' : 'Save or share your history, ratings and watchlist as JSON',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                trailing: state.exportingBackup
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                onTap: busy ? null : () => unawaited(_exportBackup(context)),
              ),
              ListTile(
                leading: const Icon(Icons.settings_backup_restore),
                title: const Text('Restore from backup'),
                subtitle: Text(
                  state.importingBackup ? 'Restoring…' : 'Replace your history, ratings and watchlist with a backup file',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                trailing: state.importingBackup
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: busy ? null : () => unawaited(_restoreBackup(context)),
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _dataSetIcon(TmdbDataSet dataSet) => switch (dataSet) {
    TmdbDataSet.ratings => Icons.star_outline,
    TmdbDataSet.watchlist => Icons.bookmark_outline,
    TmdbDataSet.favorites => Icons.favorite_border,
  };

  static String _dataSetSubtitle(TmdbDataSet dataSet) => switch (dataSet) {
    TmdbDataSet.ratings => 'Ratings you add or remove are mirrored on TMDB',
    TmdbDataSet.watchlist => 'Movies and shows only — seasons and episodes stay on this device',
    TmdbDataSet.favorites => 'Kept as favorites on your TMDB account',
  };

  Future<void> _loginWithTmdb(BuildContext context) async {
    final bloc = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final url = await bloc.loginWithTmdb();
    if (url == null) {
      return;
    }

    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      opened = false;
    }
    if (!opened) {
      await bloc.cancelTmdbLogin();
      messenger.showSnackBar(const SnackBar(content: Text('Could not open the browser')));
    }
  }

  Future<void> _logout(BuildContext context, SettingsState state) async {
    final bloc = context.read<SettingsBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _TmdbLogoutDialog(pendingPushes: state.tmdbPendingPushes),
    );
    if (confirmed == true) {
      await bloc.logoutTmdb();
    }
  }

  /// Opens the pull / push / skip dialog, which runs the sync itself and comes back with the summary
  /// (or null when the user bowed out).
  Future<void> _chooseSync(BuildContext context, {required bool firstTime}) async {
    final bloc = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    // Consumed on open: a second copy must never appear on top of this one.
    await bloc.markInitialSyncPromptShown();
    if (!context.mounted) {
      return;
    }

    final result = await showDialog<TmdbInitialSyncResult>(
      context: context,
      barrierDismissible: false,
      // The dialog lives on the root navigator, outside this page's BlocProvider.
      builder: (dialogContext) => BlocProvider.value(
        value: bloc,
        child: _TmdbInitialSyncDialog(firstTime: firstTime),
      ),
    );
    if (result == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(_summarize(result))));
  }

  static String _summarize(TmdbInitialSyncResult result) {
    final parts = <String>[];
    for (final entry in result.perDataSet.entries) {
      final label = entry.key.label.toLowerCase();
      final (:pulled, :pushed, :queued) = entry.value;
      if (pulled > 0 || (pushed == 0 && queued == 0)) {
        parts.add('pulled $pulled $label');
      }
      if (pushed > 0) {
        parts.add('pushed $pushed $label');
      }
      if (queued > 0) {
        parts.add('$queued $label queued for later');
      }
    }
    final failure = result.failureMessage;
    if (failure != null) {
      return parts.isEmpty ? failure : '$failure Done so far: ${parts.join(', ')}.';
    }
    if (parts.isEmpty) {
      return 'TMDB sync finished.';
    }
    final summary = parts.join(', ');
    return 'TMDB sync finished: ${summary[0].toUpperCase()}${summary.substring(1)}.';
  }

  Future<void> _exportBackup(BuildContext context) async {
    final bloc = context.read<SettingsBloc>();
    final file = await bloc.exportBackup();
    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    if (file == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not build the backup. Please try again.')));
      return;
    }

    final action = await showModalBottomSheet<_BackupAction>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => const _BackupActionSheet(),
    );

    switch (action) {
      case _BackupAction.save:
        try {
          if (await BackupFileSaver().saveToDevice(file)) {
            messenger.showSnackBar(const SnackBar(content: Text('Backup saved')));
          }
        } on PlatformException {
          messenger.showSnackBar(const SnackBar(content: Text('Could not save the backup. Please try again.')));
        }
      case _BackupAction.share:
        await _share(file);
      case null:
        break;
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final bloc = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);

    final String? json;
    try {
      json = await BackupFilePicker().pickFromDevice();
    } on PlatformException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not read the file. Please try again.')));
      return;
    }
    if (json == null || !context.mounted) {
      return;
    }

    final BackupContents contents;
    try {
      contents = bloc.parseBackup(json);
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RestoreConfirmationDialog(contents: contents),
    );
    if (confirmed != true) {
      return;
    }

    final restored = await bloc.restoreBackup(contents);
    messenger.showSnackBar(
      SnackBar(
        content: Text(restored ? 'Backup restored. Up Next is being rebuilt…' : 'Could not restore the backup. Your data was not changed.'),
      ),
    );
  }

  Future<void> _share(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Ticket Box backup',
        text: 'Your Ticket Box history, ratings and watchlist backup.',
      ),
    );
  }
}

enum _BackupAction { save, share }

/// Lets the user pick where the freshly built backup goes: a file on the device, or another app.
class _BackupActionSheet extends StatelessWidget {
  const _BackupActionSheet();

  @override
  Widget build(BuildContext context) {
    // The sheet sits on top of the gesture bar, so it owns its bottom inset.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Save to device'),
            onTap: () => Navigator.of(context).pop(_BackupAction.save),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share…'),
            onTap: () => Navigator.of(context).pop(_BackupAction.share),
          ),
        ],
      ),
    );
  }
}

/// Last chance before a restore wipes the current data: what the backup holds and when it was made.
class _RestoreConfirmationDialog extends StatelessWidget {
  final BackupContents contents;

  const _RestoreConfirmationDialog({required this.contents});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final exportedAt = contents.exportedAt;
    final favorites = contents.favorites;

    return AlertDialog(
      title: const Text('Replace your data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exportedAt != null) Text('Backup from ${DateFormat.yMMMd().add_jm().format(exportedAt.toLocal())}'),
          const SizedBox(height: 8),
          Text('• ${contents.history.length} plays'),
          Text('• ${contents.ratings.length} ratings'),
          Text('• ${contents.watchlist.length} watchlist items'),
          Text(favorites == null ? '• Favorites kept as they are (not in this backup)' : '• ${favorites.length} favorites'),
          const SizedBox(height: 12),
          Text(
            "Your current history, ratings and watchlist on this device will be replaced. This can't be undone.",
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Replace'),
        ),
      ],
    );
  }
}

enum _SyncDialogStep { choosing, confirming, running }

/// Pull / push / skip per data set, right after the login and again from "Sync now".
///
/// Three steps in one dialog: the choices, a last confirmation when anything is pulled, and the run
/// itself with its live progress line. It pops with the [TmdbInitialSyncResult] once the run ends,
/// or with null when the user bows out; it cannot be dismissed while running.
class _TmdbInitialSyncDialog extends StatefulWidget {
  final bool firstTime;

  const _TmdbInitialSyncDialog({required this.firstTime});

  @override
  State<_TmdbInitialSyncDialog> createState() => _TmdbInitialSyncDialogState();
}

class _TmdbInitialSyncDialogState extends State<_TmdbInitialSyncDialog> {
  TmdbSyncChoices _choices = const TmdbSyncChoices.skipAll();
  _SyncDialogStep _step = _SyncDialogStep.choosing;
  Map<TmdbDataSet, int> _localCounts = const {};

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _SyncDialogStep.running,
      child: switch (_step) {
        _SyncDialogStep.choosing => _buildChoosing(context),
        _SyncDialogStep.confirming => _buildConfirming(context),
        _SyncDialogStep.running => _buildRunning(context),
      },
    );
  }

  Widget _buildChoosing(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hint = TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant);

    return AlertDialog(
      title: Text(widget.firstTime ? 'Sync with TMDB?' : 'Sync with TMDB'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pull replaces the list on this device with your TMDB list. '
              'Push adds what is on this device to TMDB and removes nothing there.',
              style: hint,
            ),
            for (final dataSet in TmdbDataSet.values) ...[
              const SizedBox(height: 16),
              Text(dataSet.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (dataSet == TmdbDataSet.watchlist) Text('Movies and shows only; seasons and episodes stay on this device.', style: hint),
              if (dataSet == TmdbDataSet.favorites) Text('Kept as favorites on TMDB.', style: hint),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<TmdbSyncChoice>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: TmdbSyncChoice.pull, label: Text('Pull')),
                    ButtonSegment(value: TmdbSyncChoice.push, label: Text('Push')),
                    ButtonSegment(value: TmdbSyncChoice.skip, label: Text('Skip')),
                  ],
                  selected: {_choices.of(dataSet)},
                  onSelectionChanged: (selection) => setState(() => _choices = _choices.withChoice(dataSet, selection.first)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Each list you pull or push is then kept in sync: changes you make in the app are sent to TMDB. '
              'Note that TMDB takes a title off your watchlist when you rate it.',
              style: hint,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text(widget.firstTime ? 'Not now' : 'Cancel')),
        TextButton(onPressed: _choices.isNoOp ? null : () => unawaited(_start()), child: const Text('Start')),
      ],
    );
  }

  /// Last chance before a pull replaces local lists: what is on the device right now.
  Widget _buildConfirming(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulled = TmdbDataSet.values.where((dataSet) => _choices.of(dataSet) == TmdbSyncChoice.pull).toList();

    return AlertDialog(
      title: const Text('Replace with your TMDB lists?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('On this device right now:'),
          const SizedBox(height: 8),
          for (final dataSet in pulled)
            Text(
              '• ${_localCounts[dataSet] ?? 0} ${dataSet.label.toLowerCase()}'
              '${dataSet == TmdbDataSet.watchlist ? ' items (seasons and episodes are kept)' : ''}',
            ),
          const SizedBox(height: 12),
          Text(
            "These will be replaced by what is on your TMDB account. This can't be undone.",
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => setState(() => _step = _SyncDialogStep.choosing), child: const Text('Back')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
          onPressed: () => unawaited(_run()),
          child: const Text('Replace'),
        ),
      ],
    );
  }

  Widget _buildRunning(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Syncing with TMDB'),
      content: BlocBuilder<SettingsBloc, SettingsState>(
        buildWhen: (previous, current) => previous.tmdbSyncMessage != current.tmdbSyncMessage,
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(state.tmdbSyncMessage ?? 'Talking to TMDB…', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('This closes on its own when done.', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _start() async {
    if (!_choices.pullsAnything) {
      await _run();
      return;
    }
    final counts = await context.read<SettingsBloc>().tmdbLocalCounts();
    if (!mounted) {
      return;
    }
    setState(() {
      _localCounts = counts;
      _step = _SyncDialogStep.confirming;
    });
  }

  Future<void> _run() async {
    final bloc = context.read<SettingsBloc>();
    setState(() => _step = _SyncDialogStep.running);
    final result = await bloc.runTmdbInitialSync(_choices);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }
}

class _TmdbLogoutDialog extends StatelessWidget {
  final int pendingPushes;

  const _TmdbLogoutDialog({required this.pendingPushes});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Log out of TMDB?'),
      content: Text(
        'Your ratings, watchlist and favorites stay on this device. Sync is turned off'
        '${pendingPushes > 0 ? ', and $pendingPushes unsent ${pendingPushes == 1 ? 'change is' : 'changes are'} dropped' : ''}.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log out'),
        ),
      ],
    );
  }
}

/// Entry points to the donation page, the Diagnostics log viewer (which used to live in the
/// navigation drawer) and About.
class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: ScreenSizeUtil.fromLTRB(16, 12, 16, 0),
          child: Text(
            'SUPPORT',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: colorScheme.onSurfaceVariant),
          ),
        ),
        // Hidden where there is no Play Store to buy from, i.e. the Linux and Windows builds.
        if (DonationService.instance().isSupported)
          ListTile(
            leading: const Icon(Icons.coffee_outlined, color: ThemeColors.secondary),
            title: const Text('Buy me a coffee'),
            subtitle: Text('The app stays free either way', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(Routes.donate),
          ),
        ListTile(
          leading: const Icon(Icons.build_outlined),
          title: const Text('Diagnostics'),
          subtitle: Text('App logs', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(Routes.diagnostics),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About'),
          subtitle: Text('The app, the developer and the community', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(Routes.about),
        ),
      ],
    );
  }
}

/// Outcome of [_CountryPickerSheet] — a `null` sheet result still means "dismissed, change nothing".
sealed class _CountryPickResult {
  const _CountryPickResult();
}

class _CountrySelected extends _CountryPickResult {
  final SettingsRegionOption region;

  const _CountrySelected(this.region);
}

class _CountryCleared extends _CountryPickResult {
  const _CountryCleared();
}

/// Searchable country list. Pops a [_CountryPickResult] with the picked country, or with the
/// explicit "no country" choice offered while one is set.
class _CountryPickerSheet extends StatefulWidget {
  final List<SettingsRegionOption> regions;
  final String? selectedCode;

  const _CountryPickerSheet({required this.regions, required this.selectedCode});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.regions
        : widget.regions.where((region) => region.name.toLowerCase().contains(query) || region.code.toLowerCase().contains(query)).toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          Padding(
            padding: ScreenSizeUtil.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search country',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (widget.selectedCode != null) ...[
            ListTile(
              leading: Icon(Icons.location_off_outlined, color: colorScheme.onSurfaceVariant),
              title: const Text('No country'),
              subtitle: Text('Hide streaming availability', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              onTap: () => Navigator.of(context).pop(const _CountryCleared()),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: widget.regions.isEmpty
                ? Center(
                    child: Padding(
                      padding: ScreenSizeUtil.fromLTRB(24, 0, 24, 0),
                      child: Text(
                        'The country list could not be loaded. Check your connection and reopen this page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final region = filtered[index];
                      final isSelected = region.code == widget.selectedCode;
                      return ListTile(
                        title: Text(region.name),
                        subtitle: Text(region.code, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        trailing: isSelected ? Icon(Icons.check, color: colorScheme.primary) : null,
                        selected: isSelected,
                        onTap: () => Navigator.of(context).pop(_CountrySelected(region)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
