// Builds a schema-v3 `ticketbox_database` file with a small seeded library, for
// exercising the v3 → v4 migration on a device or emulator:
//
//   dart run tool/make_v3_fixture.dart /tmp/ticketbox_database
//   adb push /tmp/ticketbox_database /data/local/tmp/ticketbox_database
//   adb shell run-as ro.madcodestudios.ticket.box cp /data/local/tmp/ticketbox_database files/ticketbox_database
//
// Uses real TMDB ids so the migrated library resolves against TMDB: Breaking Bad (tmdb 1396,
// v3 id 1388), The Office US (tmdb 2316, v3 id 1443), The Matrix (tmdb 603, v3 id 481), Inception
// (tmdb 27205, v3 id 16662).
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../test/database/sql_store/generated/schema_v3.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/make_v3_fixture.dart <output file>');
    exit(2);
  }
  final file = File(args.first);
  if (file.existsSync()) {
    file.deleteSync();
  }
  final db = DatabaseAtV3(NativeDatabase(file));
  // Opening runs onCreate for the v3 schema and sets user_version = 3.
  await db.customSelect('SELECT 1').get();

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  int secondsAgo(int days) => now - days * 86400;

  Future<void> run(String sql, [List<Variable> vars = const []]) => db.customStatement(sql, vars.map((v) => v.value).toList());

  // Shows: Breaking Bad, The Office.
  await run("INSERT INTO shows VALUES (1388, 1396, 81189, 'tt0903747', 'breaking-bad', 'Breaking Bad', 2008, ?)", [
    Variable(secondsAgo(10)),
  ]);
  await run("INSERT INTO shows VALUES (1443, 2316, 73244, 'tt0386676', 'the-office', 'The Office', 2005, ?)", [Variable(secondsAgo(20))]);
  // Movies: The Matrix, Inception.
  await run("INSERT INTO movies VALUES (481, 603, 'tt0133093', 'the-matrix-1999', 'The Matrix', 1999, ?)", [Variable(secondsAgo(5))]);
  await run("INSERT INTO movies VALUES (16662, 27205, 'tt1375666', 'inception-2010', 'Inception', 2010, ?)", [Variable(secondsAgo(5))]);

  // Breaking Bad S1E1–E3 episodes + summaries (v3 episode ids 73640..73642).
  for (var e = 1; e <= 3; e++) {
    await run('INSERT INTO episodes VALUES (?, ?, NULL, NULL, ?, 1, ?, 1388, ?, ?)', [
      Variable(73639 + e),
      Variable(62085 + e),
      Variable('Episode $e'),
      Variable(e),
      Variable(secondsAgo(10)),
      Variable(secondsAgo(10)),
    ]);
    await run("INSERT INTO episode_summaries VALUES (?, 'Overview', 8.5, 1000, 0, 'en', 48, ?, NULL, ?)", [
      Variable(73639 + e),
      Variable(DateTime(2008, 1, 19 + e).millisecondsSinceEpoch ~/ 1000),
      Variable(e == 1 ? 'series_premiere' : 'standard'),
    ]);
  }
  await run('INSERT INTO seasons VALUES (3577, 3572, 30272, NULL, 1, 1388, ?)', [Variable(secondsAgo(10))]);

  // History: Matrix watched twice, Inception once, Breaking Bad S1E1–E2 watched.
  await run("INSERT INTO trakt_history_items VALUES (1001, 481, NULL, 0, 0, 'watch', 'movie', ?)", [Variable(secondsAgo(30))]);
  await run("INSERT INTO trakt_history_items VALUES (1002, 481, NULL, 0, 0, 'watch', 'movie', ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO trakt_history_items VALUES (1003, 16662, NULL, 0, 0, 'scrobble', 'movie', ?)", [Variable(secondsAgo(15))]);
  await run("INSERT INTO trakt_history_items VALUES (1004, 1388, 73640, 1, 1, 'watch', 'episode', ?)", [Variable(secondsAgo(8))]);
  await run("INSERT INTO trakt_history_items VALUES (1005, 1388, 73641, 1, 2, 'watch', 'episode', ?)", [Variable(secondsAgo(7))]);
  // An orphan: history for a show that was never cached. Must be dropped by the migration.
  await run("INSERT INTO trakt_history_items VALUES (1006, 999999, NULL, 1, 1, 'watch', 'episode', ?)", [Variable(secondsAgo(7))]);

  // Ratings and watchlist.
  await run("INSERT INTO user_ratings VALUES ('movie', 481, 481, 0, 0, 9, ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO user_ratings VALUES ('show', 1388, 1388, 0, 0, 10, ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO user_ratings VALUES ('episode', 1388, 73640, 1, 1, 8, ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO watchlists VALUES ('movie', 16662, 16662, 0, 0, ?)", [Variable(secondsAgo(2))]);
  await run("INSERT INTO watchlists VALUES ('show', 1443, 1443, 0, 0, ?)", [Variable(secondsAgo(2))]);
  await run("INSERT INTO watchlists VALUES ('season', 1443, NULL, 2, 0, ?)", [Variable(secondsAgo(2))]);

  // Progress for Breaking Bad: 62 aired, 2 completed, up next S1E3.
  await run('INSERT INTO trakt_show_progress_items VALUES (1388, 62, 2, ?, NULL)', [Variable(secondsAgo(7))]);
  await run('INSERT INTO trakt_season_progress_items VALUES (1388, 1, 7, 2)');
  for (var e = 1; e <= 3; e++) {
    await run('INSERT INTO trakt_episode_progress_items VALUES (1388, 1, ?, ?)', [Variable(e), Variable(e <= 2 ? 1 : 0)]);
  }
  await run('INSERT INTO up_next_episode_items VALUES (1388, 73642, 1, 3)');

  // The Office is dropped.
  await run("INSERT INTO dropped_items VALUES (1443, 2316, 73244, 'tt0386676', 'the-office', ?)", [Variable(secondsAgo(1))]);

  // A couple of poster rows (old concatenated ids) and a show image.
  await run(
    "INSERT INTO posters VALUES (913880, 1388, 0, 0, 'show', 'Breaking Bad', 1, 0, 0, 0, 0, 0, 0, '95%', '10', NULL, 'Breaking Bad', 0, 0, ?, ?)",
    [Variable(secondsAgo(10)), Variable(secondsAgo(10))],
  );
  await run(
    "INSERT INTO posters VALUES (948100, 481, 0, 0, 'movie', 'The Matrix', 1, 0, 0, 0, 0, 0, 0, '88%', '9', NULL, 'The Matrix', 0, 0, ?, ?)",
    [Variable(secondsAgo(10)), Variable(secondsAgo(10))],
  );
  await run("INSERT INTO show_images VALUES (1388, 'https://image.tmdb.org/t/p/w500/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg', NULL, ?)", [
    Variable(secondsAgo(10)),
  ]);

  // v3-only tables with a row each, to prove they get dropped.
  await run("INSERT INTO authentications VALUES ('trakt', 'token', 'refresh', 0)");
  await run("INSERT INTO sync_states VALUES (1, 'finished', 'none', 1, 1, NULL, ?, ?)", [
    Variable(secondsAgo(10)),
    Variable(secondsAgo(10)),
  ]);
  await run("INSERT INTO genres VALUES ('Drama', 'drama', 'show', ?)", [Variable(secondsAgo(10))]);

  final version = await db.customSelect('PRAGMA user_version').getSingle();
  stdout.writeln('Wrote ${file.path} at user_version ${version.read<int>('user_version')}');
  await db.close();
}
