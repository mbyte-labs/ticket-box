import 'package:drift/native.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';

/// The fixture the TMDB account tests share: an in-memory database and preferences, a session
/// service installed as the singleton, and a mock transport behind every TMDB wrapper.
class TmdbTestHarness {
  static const int accountId = 42;
  static const String sessionId = 'sess-1';
  static const String username = 'alex';

  late DatabaseConnectionManager db;
  late KeyValueStore store;
  late TmdbSessionService session;

  /// Every request the mock transport saw, in order.
  final List<Request> requests = [];

  Future<void> setUp({required Future<Response> Function(Request request) handler}) async {
    requests.clear();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    store = KeyValueStore.instance();
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    );
    session = TmdbSessionService.forTesting(store: store);
  }

  Future<void> tearDown() async {
    TmdbHttpClient.resetForTesting();
    await GetIt.I.reset();
    await db.close();
  }

  /// Stores a session in the preferences and loads it, as a launch after a login would.
  Future<void> logIn({Set<String> enabledToggles = const {}}) async {
    await store.setString(TmdbAccountKeys.sessionId, sessionId);
    await store.setInt(TmdbAccountKeys.accountId, accountId);
    await store.setString(TmdbAccountKeys.username, username);
    for (final key in enabledToggles) {
      await store.setBool(key, true);
    }
    await session.load();
  }

  /// A mock transport answer with TMDB's generic success body.
  static Future<Response> ok(Request request) async => Response('{"success":true,"status_code":1,"status_message":"Success."}', 201);

  /// A page of a list endpoint.
  static Response page(int page, int totalPages, List<Map<String, Object?>> results) {
    final rows = results.map((row) => row.entries.map((e) => '"${e.key}":${_json(e.value)}').join(',')).map((row) => '{$row}').join(',');
    return Response('{"page":$page,"total_pages":$totalPages,"total_results":${results.length},"results":[$rows]}', 200);
  }

  static String _json(Object? value) => value is String ? '"$value"' : '$value';
}

/// An outbox service whose flush does nothing, for tests that look at what was queued.
class NoFlushOutboxService extends TmdbSyncOutboxService {
  @override
  Future<void> flush() async {}

  @override
  Future<void> flushIfPending() async {}
}
