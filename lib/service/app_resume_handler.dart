import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';

/// Class that handles data when an app is resumed. This class should only be used by the AppStateHandler
class AppResumeHandler {
  static final _singleton = AppResumeHandler._internal();
  static final _log = Logger('[Service] AppResumeHandler');

  static bool _isInitialized = false;

  AppResumeHandler._internal();

  factory AppResumeHandler() {
    return _singleton;
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      _log.config('AppStateHandler already registered. Registering a new handler will not be performed.');
      return;
    }
    SystemChannels.lifecycle.setMessageHandler(_handleAppState);
    _isInitialized = true;
    _log.info('AppResumeHandler registered.');
  }

  Future<String?> _handleAppState(String? msg) async {
    _log.info('System Lifecycle: $msg');
    switch (msg) {
      case 'AppLifecycleState.resumed':
        _log.fine('App resumed');
        // Picks up episodes that aired and snapshots that went stale while the app was in the
        // background — the common case, since the app is only backgrounded, not killed, and the
        // launch-time tick would otherwise be the only one. None of these is awaited: this handler
        // has to hand the lifecycle message straight back to the platform channel, and none throws.
        unawaited(CatalogRefreshService.instance().tickIfDue());
        // Changes queued for TMDB while offline or while TMDB was down.
        unawaited(TmdbSyncOutboxService.instance().flushIfPending());
        // Artwork left to download.
        unawaited(ArtworkService.instance().drainIfPending());
        break;
      case 'AppLifecycleState.paused':
        _log.fine('App paused');
        ArtworkService.instance().pause();
        break;
      case 'AppLifecycleState.detached':
        break;
      default:
        return msg;
    }
    return msg;
  }
}
