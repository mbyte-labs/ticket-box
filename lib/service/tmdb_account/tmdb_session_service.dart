import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_api.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_models.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_auth_models.dart';
import 'package:ticketbox/api/tmdb/v3/authentication/tmdb_authentication_api.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';

/// The logged-in TMDB account, as the sync code needs it.
class TmdbSessionSnapshot {
  final String sessionId;
  final int accountId;
  final String username;
  final String? name;

  const TmdbSessionSnapshot({required this.sessionId, required this.accountId, required this.username, this.name});

  /// The account's display name, falling back to the username TMDB always has.
  String get displayName {
    final name = this.name;
    return name == null || name.trim().isEmpty ? username : name;
  }
}

/// How a returned approval link ended.
enum TmdbLoginOutcome {
  loggedIn,

  /// The user refused on themoviedb.org, or TMDB would not turn the token into a session.
  denied,

  /// The link did not match the login in progress — there was none, or it carried another token.
  notPending,

  /// The request token had outlived its 60 minutes.
  expired,

  /// TMDB could not be reached, or answered something unexpected.
  failed,
}

/// The user's TMDB login and the three sync toggles. Prefs-backed, with an in-memory snapshot so
/// the write hooks can answer "is sync on?" synchronously and without touching storage.
///
/// Until [load] has run (start-up), nothing is logged in — which is also what keeps the hooks inert
/// in unit tests that never set a session up.
class TmdbSessionService {
  static final _log = Logger('[Service] TmdbSessionService');

  /// TMDB gives a request token 60 minutes; the margin covers the clock drift and the round trip.
  static const requestTokenLifetime = Duration(minutes: 55);

  final KeyValueStore? _storeOverride;
  final TmdbAuthenticationApi _authApi;
  final TmdbAccountApi _accountApi;
  final TmdbSyncOutboxRepo Function() _outbox;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<TmdbLoginOutcome> _loginOutcomes = StreamController<TmdbLoginOutcome>.broadcast();

  TmdbSessionSnapshot? _session;
  String? _username;
  bool _sessionInvalid = false;
  final Set<TmdbDataSet> _enabled = {};
  String? _pendingToken;
  DateTime? _pendingExpiresAt;
  bool _initialSyncPromptPending = false;
  Future<TmdbLoginOutcome>? _completing;

  TmdbSessionService._({
    KeyValueStore? store,
    TmdbAuthenticationApi? authApi,
    TmdbAccountApi? accountApi,
    TmdbSyncOutboxRepo Function()? outbox,
  }) : _storeOverride = store,
       _authApi = authApi ?? TmdbAuthenticationApi(),
       _accountApi = accountApi ?? TmdbAccountApi(),
       _outbox = outbox ?? TmdbSyncOutboxRepo.new;

  static TmdbSessionService instance() {
    if (GetIt.I.isRegistered<TmdbSessionService>()) {
      return GetIt.I.get<TmdbSessionService>();
    }
    _log.info('New instance created');
    final service = TmdbSessionService._();
    GetIt.I.registerSingleton<TmdbSessionService>(service);
    return service;
  }

  /// A service over caller-supplied collaborators, installed as [instance] so the hooks and the
  /// sync services pick it up. Tests reset GetIt afterwards.
  @visibleForTesting
  factory TmdbSessionService.forTesting({
    KeyValueStore? store,
    TmdbAuthenticationApi? authApi,
    TmdbAccountApi? accountApi,
    TmdbSyncOutboxRepo Function()? outbox,
  }) {
    if (GetIt.I.isRegistered<TmdbSessionService>()) {
      GetIt.I.unregister<TmdbSessionService>();
    }
    final service = TmdbSessionService._(store: store, authApi: authApi, accountApi: accountApi, outbox: outbox);
    GetIt.I.registerSingleton<TmdbSessionService>(service);
    return service;
  }

  KeyValueStore get _store => _storeOverride ?? KeyValueStore.instance();

  /// Fires after every change to the login state, the toggles or the pending login.
  Stream<void> get changes => _changes.stream;

  /// How each returned approval link ended — the Settings page turns these into a SnackBar.
  Stream<TmdbLoginOutcome> get loginOutcomes => _loginOutcomes.stream;

  bool get isLoggedIn => _session != null;

  TmdbSessionSnapshot? get session => _session;

  /// True when TMDB stopped accepting the stored session. [lastUsername] still names the account.
  bool get sessionInvalid => _sessionInvalid;

  /// The username of the current session, or of the one that became invalid.
  String? get lastUsername => _session?.username ?? _username;

  bool get hasPendingLogin => _pendingToken != null;

  /// True from a login until the Settings page has shown its pull / push / skip dialog.
  bool get initialSyncPromptPending => _initialSyncPromptPending;

  bool isSyncEnabled(TmdbDataSet dataSet) => isLoggedIn && _enabled.contains(dataSet);

  Set<TmdbDataSet> get enabledDataSets => Set.unmodifiable(_enabled);

  /// Reads the stored session and toggles. Prefs only — no network — so it is safe at start-up.
  Future<void> load() async {
    final store = _store;
    final sessionId = await store.getString(TmdbAccountKeys.sessionId);
    final accountId = await store.getInt(TmdbAccountKeys.accountId);
    _username = await store.getString(TmdbAccountKeys.username);
    final name = await store.getString(TmdbAccountKeys.name);
    _sessionInvalid = await store.getBoolOrDefault(TmdbAccountKeys.sessionInvalid, false);
    _session = sessionId != null && accountId != null && _username != null
        ? TmdbSessionSnapshot(sessionId: sessionId, accountId: accountId, username: _username!, name: name)
        : null;

    _enabled.clear();
    for (final dataSet in TmdbDataSet.values) {
      if (await store.getBoolOrDefault(_toggleKey(dataSet), false)) {
        _enabled.add(dataSet);
      }
    }

    _pendingToken = await store.getString(TmdbAccountKeys.pendingRequestToken);
    final expires = await store.getString(TmdbAccountKeys.pendingRequestTokenExpiresAt);
    _pendingExpiresAt = expires == null ? null : DateTime.tryParse(expires);
    if (_pendingToken != null && _isPendingExpired()) {
      _log.info('The pending TMDB login expired while the app was closed');
      await _clearPending();
    }
    _initialSyncPromptPending = await store.getBoolOrDefault(TmdbAccountKeys.initialSyncPromptPending, false);

    _log.info(
      'Loaded TMDB session: ${isLoggedIn
          ? 'logged in as $_username'
          : _sessionInvalid
          ? 'session of $_username invalid'
          : 'logged out'}, '
      'sync on for ${_enabled.map((e) => e.name).join(', ')}',
    );
    _notify();
  }

  /// Starts a login: asks TMDB for a request token, remembers it, and returns the page where the
  /// user approves it. TMDB sends the user back to [redirectTo] afterwards — see [completeLogin].
  Future<Uri> beginLogin(Uri redirectTo) async {
    final token = await _authApi.createRequestToken();
    _pendingToken = token.requestToken;
    _pendingExpiresAt = DateTime.now().add(requestTokenLifetime);
    await _store.setString(TmdbAccountKeys.pendingRequestToken, _pendingToken!);
    await _store.setString(TmdbAccountKeys.pendingRequestTokenExpiresAt, _pendingExpiresAt!.toUtc().toIso8601String());
    _log.info('TMDB login started, waiting for the user to approve the request token');
    _notify();
    return TmdbAuthenticationApi.approvalUrl(token.requestToken, redirectTo);
  }

  /// Finishes a login from the deep link TMDB redirected to. Only the token of the login in
  /// progress is accepted, and a second call with the same link while the first is still running
  /// joins it — the cold-start path can deliver the link twice.
  Future<TmdbLoginOutcome> completeLogin(Uri link) {
    final completing = _completing;
    if (completing != null) {
      return completing;
    }
    late final Future<TmdbLoginOutcome> run;
    run = _completeLogin(link)
        .then((outcome) {
          if (!_loginOutcomes.isClosed) {
            _loginOutcomes.add(outcome);
          }
          return outcome;
        })
        .whenComplete(() {
          if (_completing == run) {
            _completing = null;
          }
        });
    _completing = run;
    return run;
  }

  Future<TmdbLoginOutcome> _completeLogin(Uri link) async {
    final pending = _pendingToken;
    if (pending == null) {
      _log.info('Ignoring a TMDB approval link: no login in progress');
      return TmdbLoginOutcome.notPending;
    }
    if (link.queryParameters['denied'] == 'true') {
      _log.info('The user denied the TMDB login');
      await _clearPending();
      _notify();
      return TmdbLoginOutcome.denied;
    }
    final token = link.queryParameters['request_token'];
    if (token == null || token != pending) {
      _log.warning('Ignoring a TMDB approval link whose token does not match the login in progress');
      return TmdbLoginOutcome.notPending;
    }
    if (_isPendingExpired()) {
      _log.info('The TMDB request token expired before it was approved');
      await _clearPending();
      _notify();
      return TmdbLoginOutcome.expired;
    }

    try {
      final session = await _authApi.createSession(token);
      final account = await _accountApi.get(session.sessionId);
      await _persistSession(session, account);
      await _clearPending();
      _initialSyncPromptPending = true;
      await _store.setBool(TmdbAccountKeys.initialSyncPromptPending, true);
      _log.info('Logged in to TMDB as ${account.username}');
      _notify();
      return TmdbLoginOutcome.loggedIn;
    } on ApiUnauthorizedException catch (e) {
      // TMDB refuses to build a session from a token the user did not approve.
      _log.warning('TMDB would not create a session (status_code ${e.tmdbStatusCode})');
      await _clearPending();
      _notify();
      return TmdbLoginOutcome.denied;
    } catch (e, stackTrace) {
      _log.severe('Could not finish the TMDB login', e, stackTrace);
      await _clearPending();
      _notify();
      return TmdbLoginOutcome.failed;
    }
  }

  /// Forgets the login in progress — the user gave up waiting for the browser.
  Future<void> cancelPendingLogin() async {
    if (_pendingToken == null) {
      return;
    }
    _log.info('TMDB login cancelled');
    await _clearPending();
    _notify();
  }

  /// Logs out: revokes the session on TMDB (best effort), forgets the account, turns every toggle
  /// off and drops the pending pushes. The user's data on the device is untouched.
  Future<void> logout() async {
    final sessionId = _session?.sessionId;
    if (sessionId != null) {
      try {
        await _authApi.deleteSession(sessionId);
      } catch (e, stackTrace) {
        _log.warning('Could not revoke the TMDB session; forgetting it locally anyway', e, stackTrace);
      }
    }
    for (final key in TmdbAccountKeys.all) {
      await _store.remove(key);
    }
    _session = null;
    _username = null;
    _sessionInvalid = false;
    _enabled.clear();
    _pendingToken = null;
    _pendingExpiresAt = null;
    _initialSyncPromptPending = false;
    await _outbox().deleteAll();
    _log.info('Logged out of TMDB');
    _notify();
  }

  /// TMDB answered 401 to the stored session: drop it and flag it, keeping the username, the
  /// toggles and the outbox so a fresh login resumes exactly where this one stopped.
  Future<void> invalidateSession() async {
    if (_session == null) {
      return;
    }
    _log.warning('The TMDB session of $_username is no longer valid');
    _session = null;
    _sessionInvalid = true;
    await _store.remove(TmdbAccountKeys.sessionId);
    await _store.setBool(TmdbAccountKeys.sessionInvalid, true);
    _notify();
  }

  Future<void> setSyncEnabled(TmdbDataSet dataSet, bool enabled) async {
    if (enabled) {
      _enabled.add(dataSet);
    } else {
      _enabled.remove(dataSet);
    }
    await _store.setBool(_toggleKey(dataSet), enabled);
    _log.info('TMDB sync of ${dataSet.name} turned ${enabled ? 'on' : 'off'}');
    _notify();
  }

  /// Clears the "show the pull / push / skip dialog" flag once the page has shown it.
  Future<void> consumeInitialSyncPrompt() async {
    if (!_initialSyncPromptPending) {
      return;
    }
    _initialSyncPromptPending = false;
    await _store.setBool(TmdbAccountKeys.initialSyncPromptPending, false);
    _notify();
  }

  Future<void> _persistSession(TmdbSession session, TmdbAccountDetails account) async {
    final store = _store;
    await store.setString(TmdbAccountKeys.sessionId, session.sessionId);
    await store.setInt(TmdbAccountKeys.accountId, account.id);
    await store.setString(TmdbAccountKeys.username, account.username);
    final name = account.name;
    if (name == null) {
      await store.remove(TmdbAccountKeys.name);
    } else {
      await store.setString(TmdbAccountKeys.name, name);
    }
    await store.setBool(TmdbAccountKeys.sessionInvalid, false);
    _session = TmdbSessionSnapshot(sessionId: session.sessionId, accountId: account.id, username: account.username, name: name);
    _username = account.username;
    _sessionInvalid = false;
  }

  Future<void> _clearPending() async {
    _pendingToken = null;
    _pendingExpiresAt = null;
    await _store.remove(TmdbAccountKeys.pendingRequestToken);
    await _store.remove(TmdbAccountKeys.pendingRequestTokenExpiresAt);
  }

  bool _isPendingExpired() {
    final expiresAt = _pendingExpiresAt;
    return expiresAt == null || DateTime.now().isAfter(expiresAt);
  }

  static String _toggleKey(TmdbDataSet dataSet) => switch (dataSet) {
    TmdbDataSet.ratings => TmdbAccountKeys.syncRatings,
    TmdbDataSet.watchlist => TmdbAccountKeys.syncWatchlist,
    TmdbDataSet.favorites => TmdbAccountKeys.syncFavorites,
  };

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}
