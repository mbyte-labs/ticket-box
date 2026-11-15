// Diagnostic: migrates a copy of a fixture file (any in-place version, see tool/make_v3_fixture.dart
// and tool/make_v9_fixture.dart) through the real DatabaseConnectionManager and prints what survived.
// Run with:
//   flutter test test/tool/migrate_fixture_smoke_test.dart --dart-define=FIXTURE=/path/to/ticketbox_database.sqlite
// (`V3_FIXTURE` is still accepted for the old name.)
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';

void main() {
  const fixture = String.fromEnvironment('FIXTURE', defaultValue: String.fromEnvironment('V3_FIXTURE'));

  test('migrates the fixture', () async {
    if (fixture.isEmpty) {
      markTestSkipped('no FIXTURE given');
      return;
    }
    final source = File(fixture);
    final copy = File('${source.path}.migrated');
    if (copy.existsSync()) {
      copy.deleteSync();
    }
    source.copySync(copy.path);
    final db = DatabaseConnectionManager.forTesting(NativeDatabase(copy));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    final out = StringBuffer('user_version: ${version.read<int>('user_version')}\n');
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite%' ORDER BY name")
        .get();
    for (final table in tables) {
      final name = table.read<String>('name');
      final count = await db.customSelect('SELECT COUNT(*) AS n FROM "$name"').getSingle();
      out.writeln('${name.padRight(26)} ${count.read<int>('n')}');
    }
    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx%' ORDER BY name").get();
    out.writeln('--- indexes: ${indexes.map((r) => r.read<String>('name')).toList()}');
    out.writeln('--- history:');
    for (final row in await db.customSelect('SELECT * FROM history_items ORDER BY history_id').get()) {
      out.writeln(row.data);
    }
    out.writeln('--- movies: ${(await db.customSelect('SELECT tmdb_id, title, release_date, poster_path, fetched_at FROM movies').get()).map((r) => r.data)}');
    out.writeln('--- shows: ${(await db.customSelect('SELECT tmdb_id, title, first_air_date, poster_path, fetched_at FROM shows').get()).map((r) => r.data)}');
    out.writeln('--- seasons: ${(await db.customSelect('SELECT show_tmdb_id, season, tmdb_id, air_date, poster_path, fetched_at FROM seasons').get()).map((r) => r.data)}');
    out.writeln(
      '--- episodes: ${(await db.customSelect('SELECT show_tmdb_id, season, episode, air_date, episode_type, still_path FROM episodes').get()).map((r) => r.data)}',
    );
    out.writeln('--- show states: ${(await db.customSelect('SELECT * FROM show_states').get()).map((r) => r.data)}');
    out.writeln('--- pending deletions: ${(await db.customSelect('SELECT * FROM pending_deletions').get()).map((r) => r.data)}');
    out.writeln('--- asset jobs: ${(await db.customSelect('SELECT * FROM asset_jobs').get()).map((r) => r.data)}');
    out.writeln('--- ratings: ${(await db.customSelect('SELECT * FROM user_ratings').get()).map((r) => r.data)}');
    out.writeln('--- watchlist: ${(await db.customSelect('SELECT * FROM watchlists').get()).map((r) => r.data)}');
    out.writeln('--- favorites: ${(await db.customSelect('SELECT * FROM favorite_items').get()).map((r) => r.data)}');
    out.writeln('--- caches: ${(await db.customSelect('SELECT key FROM caches').get()).map((r) => r.data)}');
    out.writeln(
      '--- seq: ${(await db.customSelect("SELECT seq FROM sqlite_sequence WHERE name = 'history_items'").get()).map((r) => r.data)}',
    );
    // ignore: avoid_print
    print(out);
    expect(version.read<int>('user_version'), DatabaseConnectionManager.currentSchemaVersion);
    await db.close();
  });
}
