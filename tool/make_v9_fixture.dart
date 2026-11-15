// Builds a schema-v9 `ticketbox_database` file with a small seeded library, for exercising the
// v9 → v10 migration (the offline-first rebuild) on a device or emulator:
//
//   dart run tool/make_v9_fixture.dart /tmp/ticketbox_database.sqlite
//   adb push /tmp/ticketbox_database.sqlite /data/local/tmp/ticketbox_database.sqlite
//   adb shell run-as ro.madcodestudios.ticket.box cp /data/local/tmp/ticketbox_database.sqlite files/ticketbox_database.sqlite
//
// Uses real TMDB ids so the migrated library resolves against TMDB and the backfill has something
// to fetch: Breaking Bad (1396, S1E1–E3 watched, up next S1E4), The Office US (2316, dropped), The
// Matrix (603, watched twice, rated), Inception (27205, watchlisted), Fight Club (550, favorite),
// plus a browse-only show (Game of Thrones, 1399) and movie (Interstellar, 157336) the migration
// must drop.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../test/database/sql_store/generated/schema_v9.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/make_v9_fixture.dart <output file>');
    exit(2);
  }
  final file = File(args.first);
  if (file.existsSync()) {
    file.deleteSync();
  }
  final db = DatabaseAtV9(NativeDatabase(file));
  // Opening runs onCreate for the v9 schema and sets user_version = 9.
  await db.customSelect('SELECT 1').get();

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  int secondsAgo(int days) => now - days * 86400;
  int localMidnight(int year, int month, int day) => DateTime(year, month, day).millisecondsSinceEpoch ~/ 1000;

  Future<void> run(String sql, [List<Variable> vars = const []]) => db.customStatement(sql, vars.map((v) => v.value).toList());

  // Shows.
  await run("INSERT INTO shows VALUES (1396, 'tt0903747', 'Breaking Bad', 2008, ?)", [Variable(secondsAgo(10))]);
  await run("INSERT INTO shows VALUES (2316, 'tt0386676', 'The Office', 2005, ?)", [Variable(secondsAgo(20))]);
  await run("INSERT INTO shows VALUES (1399, 'tt0944947', 'Game of Thrones', 2011, ?)", [Variable(secondsAgo(1))]);
  await run(
    '''INSERT INTO show_summaries VALUES (1396, 'Breaking Bad', 2008, 'A chemistry teacher turns to crime.', NULL, ?, ?, 47, 'TV-MA',
      'AMC', 'US', 'en', NULL, NULL, 8.9, 12000, 300.5, 62, 5, NULL, NULL, NULL, '18,80', 'ended', ?)''',
    [Variable(localMidnight(2008, 1, 20)), Variable(localMidnight(2013, 9, 29)), Variable(secondsAgo(10))],
  );
  await run(
    "INSERT INTO show_images VALUES (1396, 'https://image.tmdb.org/t/p/w342/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg', 'https://image.tmdb.org/t/p/original/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg', ?)",
    [Variable(secondsAgo(10))],
  );
  await run('INSERT INTO seasons VALUES (1396, 1, 3572, ?, 7, ?, ?)', [
    const Variable('Season 1'),
    Variable(localMidnight(2008, 1, 20)),
    Variable(secondsAgo(10)),
  ]);
  await run("INSERT INTO season_images VALUES (1396, 1, 'https://image.tmdb.org/t/p/w342/1BP4xYv9ZG4ZVHkL7ocOziBbSYH.jpg', ?)", [
    Variable(secondsAgo(10)),
  ]);
  final airDates = [localMidnight(2008, 1, 20), localMidnight(2008, 1, 27), localMidnight(2008, 2, 10), localMidnight(2008, 2, 17)];
  for (var e = 1; e <= 4; e++) {
    await run("INSERT INTO episodes VALUES (1396, 1, ?, ?, NULL, ?, 'Overview', 8.5, 1000, 48, ?, ?, ?)", [
      Variable(e),
      Variable(62085 + e),
      Variable('Episode $e'),
      Variable(airDates[e - 1]),
      Variable(e == 1 ? 'season_premiere' : 'standard'),
      Variable(secondsAgo(10)),
    ]);
  }
  await run("INSERT INTO episode_images VALUES (1396, 1, 1, 'https://image.tmdb.org/t/p/w300/ydlY3iPfeOAvu8gVqrxPoMvzNCn.jpg', ?)", [
    Variable(secondsAgo(10)),
  ]);
  // Browse-only show with a season and an episode: must be dropped.
  await run('INSERT INTO seasons VALUES (1399, 1, 3624, ?, 10, ?, ?)', [
    const Variable('Season 1'),
    Variable(localMidnight(2011, 4, 17)),
    Variable(secondsAgo(1)),
  ]);
  await run("INSERT INTO episodes VALUES (1399, 1, 1, 63056, NULL, 'Winter Is Coming', NULL, 8.0, 100, 62, ?, 'standard', ?)", [
    Variable(localMidnight(2011, 4, 17)),
    Variable(secondsAgo(1)),
  ]);

  // Movies.
  await run("INSERT INTO movies VALUES (603, 'tt0133093', 'The Matrix', 1999, ?)", [Variable(secondsAgo(5))]);
  await run("INSERT INTO movies VALUES (27205, 'tt1375666', 'Inception', 2010, ?)", [Variable(secondsAgo(5))]);
  await run("INSERT INTO movies VALUES (550, 'tt0137523', 'Fight Club', 1999, ?)", [Variable(secondsAgo(5))]);
  await run("INSERT INTO movies VALUES (157336, 'tt0816692', 'Interstellar', 2014, ?)", [Variable(secondsAgo(1))]);
  await run(
    "INSERT INTO movie_summaries VALUES (603, 'The Matrix', 1999, 'A hacker learns the truth.', 'Welcome to the Real World.', ?, 136, 'R', 'US', 'en', NULL, NULL, 8.2, 24000, 80.1, '28,878', 'released', ?)",
    [Variable(localMidnight(1999, 3, 31)), Variable(secondsAgo(5))],
  );
  await run(
    "INSERT INTO movie_images VALUES (603, 'https://image.tmdb.org/t/p/w342/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg', 'https://image.tmdb.org/t/p/original/ncEsesgOJDNrTUED89hYbA117wo.jpg', ?)",
    [Variable(secondsAgo(5))],
  );

  // History: Matrix watched twice, Breaking Bad S1E1–E3, Inception never; a play of a movie with no
  // catalogue row (Alien, 348) that must get a stub.
  await run("INSERT INTO history_items VALUES (1001, 'movie', 603, 0, 0, 'watch', ?)", [Variable(secondsAgo(30))]);
  await run("INSERT INTO history_items VALUES (1002, 'movie', 603, 0, 0, 'watch', ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO history_items VALUES (1003, 'movie', 348, 0, 0, 'scrobble', ?)", [Variable(secondsAgo(15))]);
  for (var e = 1; e <= 3; e++) {
    await run("INSERT INTO history_items VALUES (?, 'episode', 1396, 1, ?, 'watch', ?)", [
      Variable(1003 + e),
      Variable(e),
      Variable(secondsAgo(9 - e)),
    ]);
  }

  // Ratings, watchlist, favorites, dropped.
  await run("INSERT INTO user_ratings VALUES ('movie', 603, 0, 0, 9, ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO user_ratings VALUES ('show', 1396, 0, 0, 10, ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO user_ratings VALUES ('episode', 1396, 1, 1, 8, ?)", [Variable(secondsAgo(3))]);
  await run("INSERT INTO watchlists VALUES ('movie', 27205, 0, 0, ?)", [Variable(secondsAgo(2))]);
  await run("INSERT INTO watchlists VALUES ('season', 2316, 2, 0, ?)", [Variable(secondsAgo(2))]);
  await run("INSERT INTO favorite_items VALUES ('movie', 550, ?)", [Variable(secondsAgo(2))]);
  await run("INSERT INTO dropped_items VALUES (2316, 'tt0386676', ?)", [Variable(secondsAgo(1))]);

  // Stored progress for Breaking Bad (3 of 4 aired, up next S1E4) and poster rows: all derived now.
  await run('INSERT INTO show_progress_items VALUES (1396, 4, 3, ?, ?)', [Variable(secondsAgo(6)), Variable(secondsAgo(6))]);
  await run('INSERT INTO season_progress_items VALUES (1396, 1, 4, 3)');
  for (var e = 1; e <= 4; e++) {
    await run('INSERT INTO episode_progress_items VALUES (1396, 1, ?, ?)', [Variable(e), Variable(e <= 3 ? 1 : 0)]);
  }
  await run('INSERT INTO up_next_episode_items VALUES (1396, 1, 4)');
  await run(
    "INSERT INTO posters VALUES (10000139600000000, 1396, 0, 0, 'show', 'Breaking Bad', 1, 0, 0, 0, 0, 0, 0, '8.9', '10', 'https://image.tmdb.org/t/p/w342/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg', 'Breaking Bad', 0, 0, ?, ?)",
    [Variable(secondsAgo(10)), Variable(secondsAgo(10))],
  );
  await run(
    "INSERT INTO posters VALUES (90002720500000000, 27205, 0, 0, 'movie', 'Inception', 0, 1, 0, 0, 0, 0, 0, '8.4', NULL, 'https://image.tmdb.org/t/p/w342/oYuLEt3zVCKq57qu2F8dT7NIa6f.jpg', 'Inception', 0, 0, ?, ?)",
    [Variable(secondsAgo(10)), Variable(secondsAgo(10))],
  );

  // Caches: two that ride the snapshot now (dropped) and three that stay.
  await run("INSERT INTO caches VALUES ('related_show_1396', '{\"ids\":[1399]}', ?)", [Variable(secondsAgo(1))]);
  await run("INSERT INTO caches VALUES ('watch_providers_show_1396_US', '{\"providers\":[],\"link\":null}', ?)", [Variable(secondsAgo(1))]);
  await run("INSERT INTO caches VALUES ('watch_provider_regions', '{\"regions\":[]}', ?)", [Variable(secondsAgo(1))]);
  await run(
    "INSERT INTO caches VALUES ('external_ratings_movie_603', '{\"tmdbScore\":8.2,\"tmdbVotes\":24000,\"imdbRating\":\"8.7\",\"imdbVotes\":\"2,000,000\"}', ?)",
    [Variable(secondsAgo(1))],
  );
  await run("INSERT INTO caches VALUES ('discover_movies_popular', '{\"ids\":[603],\"totalPages\":1}', ?)", [Variable(secondsAgo(1))]);
  await run("INSERT INTO job_states VALUES (1, 'finished', 'none', NULL, ?, ?)", [Variable(secondsAgo(1)), Variable(secondsAgo(1))]);

  final version = await db.customSelect('PRAGMA user_version').getSingle();
  stdout.writeln('Wrote ${file.path} at user_version ${version.read<int>('user_version')}');
  await db.close();
}
