import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';

import 'tmdb_test_support.dart';

/// Login, logout and invalidation, and what each leaves behind in the preferences and the outbox.
void main() {
  final harness = TmdbTestHarness();
  final link = Uri.parse('ticketbox://tmdb-auth?request_token=tok-1&approved=true');

  Future<Response> tmdb(Request request) async {
    final path = request.url.path;
    if (path == '/3/authentication/token/new') {
      return Response('{"success":true,"expires_at":"2026-10-09 12:00:00 UTC","request_token":"tok-1"}', 200);
    }
    if (path == '/3/authentication/session/new') {
      return Response('{"success":true,"session_id":"sess-1"}', 200);
    }
    if (path == '/3/authentication/session') {
      return Response('{"success":true}', 200);
    }
    if (path == '/3/account') {
      return Response('{"id":42,"username":"alex","name":"Alex D"}', 200);
    }
    return Response('{"status_code":34}', 404);
  }

  setUp(() => harness.setUp(handler: tmdb));

  tearDown(harness.tearDown);

  test('nothing is logged in until load() has run, so the hooks stay inert', () {
    expect(harness.session.isLoggedIn, isFalse);
    expect(harness.session.isSyncEnabled(TmdbDataSet.ratings), isFalse);
  });

  test('beginLogin remembers the request token and points at the approval page', () async {
    final url = await harness.session.beginLogin(Uri.parse('ticketbox://tmdb-auth'));

    expect(url.path, '/authenticate/tok-1');
    expect(url.queryParameters['redirect_to'], 'ticketbox://tmdb-auth');
    expect(harness.session.hasPendingLogin, isTrue);
    expect(await harness.store.getString(TmdbAccountKeys.pendingRequestToken), 'tok-1');
  });

  test('the approval link logs in, persists the account and asks for the sync prompt', () async {
    await harness.session.beginLogin(Uri.parse('ticketbox://tmdb-auth'));
    final outcomes = <TmdbLoginOutcome>[];
    final subscription = harness.session.loginOutcomes.listen(outcomes.add);
    addTearDown(subscription.cancel);

    final outcome = await harness.session.completeLogin(link);
    await pumpEventQueue();

    expect(outcome, TmdbLoginOutcome.loggedIn);
    expect(outcomes, [TmdbLoginOutcome.loggedIn]);
    expect(harness.session.isLoggedIn, isTrue);
    expect(harness.session.session!.accountId, 42);
    expect(harness.session.session!.displayName, 'Alex D');
    expect(harness.session.hasPendingLogin, isFalse);
    expect(harness.session.initialSyncPromptPending, isTrue);
    expect(await harness.store.getString(TmdbAccountKeys.sessionId), 'sess-1');
    expect(await harness.store.getInt(TmdbAccountKeys.accountId), 42);
    expect(await harness.store.getString(TmdbAccountKeys.username), 'alex');
    expect(await harness.store.containsKey(TmdbAccountKeys.pendingRequestToken), isFalse);
    // The token was sent on, and the session id went into the account call's query.
    expect(harness.requests.map((r) => r.url.path), ['/3/authentication/token/new', '/3/authentication/session/new', '/3/account']);
    expect(harness.requests.last.url.queryParameters['session_id'], 'sess-1');
  });

  test('a stored session survives a relaunch', () async {
    await harness.session.beginLogin(Uri.parse('ticketbox://tmdb-auth'));
    await harness.session.completeLogin(link);
    await harness.session.setSyncEnabled(TmdbDataSet.watchlist, true);

    final relaunched = TmdbSessionService.forTesting(store: harness.store);
    await relaunched.load();

    expect(relaunched.isLoggedIn, isTrue);
    expect(relaunched.session!.sessionId, 'sess-1');
    expect(relaunched.session!.username, 'alex');
    expect(relaunched.isSyncEnabled(TmdbDataSet.watchlist), isTrue);
    expect(relaunched.isSyncEnabled(TmdbDataSet.ratings), isFalse);
    expect(relaunched.initialSyncPromptPending, isTrue);
  });

  test('a link with another token, or with no login in progress, is ignored', () async {
    expect(await harness.session.completeLogin(link), TmdbLoginOutcome.notPending);

    await harness.session.beginLogin(Uri.parse('ticketbox://tmdb-auth'));
    final other = Uri.parse('ticketbox://tmdb-auth?request_token=someone-else&approved=true');

    expect(await harness.session.completeLogin(other), TmdbLoginOutcome.notPending);
    expect(harness.session.hasPendingLogin, isTrue, reason: 'the real login is still waiting');
    expect(harness.session.isLoggedIn, isFalse);
  });

  test('a denied link ends the login', () async {
    await harness.session.beginLogin(Uri.parse('ticketbox://tmdb-auth'));

    final outcome = await harness.session.completeLogin(Uri.parse('ticketbox://tmdb-auth?request_token=tok-1&denied=true'));

    expect(outcome, TmdbLoginOutcome.denied);
    expect(harness.session.hasPendingLogin, isFalse);
    expect(harness.session.isLoggedIn, isFalse);
  });

  test('a token that expired while the app was closed is dropped on load', () async {
    await harness.store.setString(TmdbAccountKeys.pendingRequestToken, 'tok-old');
    await harness.store.setString(TmdbAccountKeys.pendingRequestTokenExpiresAt, DateTime.utc(2020).toIso8601String());

    await harness.session.load();

    expect(harness.session.hasPendingLogin, isFalse);
    expect(await harness.store.containsKey(TmdbAccountKeys.pendingRequestToken), isFalse);
  });

  test('cancelling forgets the login in progress', () async {
    await harness.session.beginLogin(Uri.parse('ticketbox://tmdb-auth'));

    await harness.session.cancelPendingLogin();

    expect(harness.session.hasPendingLogin, isFalse);
    expect(await harness.session.completeLogin(link), TmdbLoginOutcome.notPending);
  });

  test('invalidating keeps the username, the toggles and the outbox, and drops only the session', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncRatings});
    await TmdbSyncOutboxRepo().enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 8);

    await harness.session.invalidateSession();

    expect(harness.session.isLoggedIn, isFalse);
    expect(harness.session.sessionInvalid, isTrue);
    expect(harness.session.lastUsername, 'alex');
    expect(harness.session.enabledDataSets, {TmdbDataSet.ratings});
    expect(harness.session.isSyncEnabled(TmdbDataSet.ratings), isFalse, reason: 'nothing is pushed while logged out');
    expect(await harness.store.containsKey(TmdbAccountKeys.sessionId), isFalse);
    expect(await harness.store.getBool(TmdbAccountKeys.sessionInvalid), isTrue);
    expect(await TmdbSyncOutboxRepo().count(), 1);
  });

  test('logging out revokes the session, forgets everything and empties the outbox', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncRatings, TmdbAccountKeys.syncWatchlist});
    await TmdbSyncOutboxRepo().enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 8);

    await harness.session.logout();

    expect(harness.requests.single.method, 'DELETE');
    expect(harness.requests.single.url.path, '/3/authentication/session');
    expect(harness.session.isLoggedIn, isFalse);
    expect(harness.session.sessionInvalid, isFalse);
    expect(harness.session.lastUsername, isNull);
    expect(harness.session.enabledDataSets, isEmpty);
    for (final key in TmdbAccountKeys.all) {
      expect(await harness.store.containsKey(key), isFalse, reason: key);
    }
    expect(await TmdbSyncOutboxRepo().count(), 0);
  });
}
