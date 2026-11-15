import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';

/// Receives the `ticketbox://tmdb-auth` deep link TMDB redirects to once the user approved (or
/// refused) the app, and finishes the login with it.
///
/// The intent-filter for the scheme lives in `AndroidManifest.xml`; `app_links` delivers both the
/// link that started the process (a cold start) and the ones arriving while it runs. On a cold start
/// the same link can come through both [handleInitialLink] and the stream — the session service
/// joins the two completions, so that is harmless.
class TmdbAuthLinkHandler {
  static final _log = Logger('[Service] TmdbAuthLinkHandler');

  static const String scheme = 'ticketbox';
  static const String host = 'tmdb-auth';

  /// Where TMDB sends the user after the approval page.
  static final Uri redirectUri = Uri(scheme: scheme, host: host);

  static StreamSubscription<Uri>? _subscription;

  TmdbAuthLinkHandler._();

  static bool isTmdbAuthLink(Uri uri) => uri.scheme == scheme && uri.host == host;

  /// Starts answering links while the app runs. Idempotent; the subscription lives as long as the
  /// process.
  static void listen() {
    _subscription ??= AppLinks().uriLinkStream.listen(
      (uri) => unawaited(handle(uri)),
      onError: (Object e, StackTrace stackTrace) => _log.warning('The deep link stream failed', e, stackTrace),
    );
  }

  /// Handles the link the app was started with, if it is a TMDB approval link. Returns whether it
  /// was one, so the start-up flow can land on Settings.
  static Future<bool> handleInitialLink() async {
    try {
      final uri = await AppLinks().getInitialLink();
      if (uri == null || !isTmdbAuthLink(uri)) {
        return false;
      }
      _log.info('The app was opened by a TMDB approval link');
      await handle(uri);
      return true;
    } catch (e, stackTrace) {
      _log.warning('Could not read the initial deep link', e, stackTrace);
      return false;
    }
  }

  /// Finishes the login with [uri]. Null when it is not a TMDB approval link.
  static Future<TmdbLoginOutcome?> handle(Uri uri) async {
    if (!isTmdbAuthLink(uri)) {
      _log.fine('Ignoring a deep link that is not a TMDB approval: ${uri.scheme}://${uri.host}');
      return null;
    }
    final outcome = await TmdbSessionService.instance().completeLogin(uri);
    _log.info('TMDB approval link handled: ${outcome.name}');
    if (outcome == TmdbLoginOutcome.loggedIn) {
      unawaited(TmdbSyncOutboxService.instance().flush());
    }
    return outcome;
  }

  /// Undoes [listen]; for tests.
  @visibleForTesting
  static Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
