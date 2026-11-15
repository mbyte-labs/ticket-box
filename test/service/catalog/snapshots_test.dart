import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';

import 'snapshot_fixtures.dart';

void main() {
  group('MovieSnapshot', () {
    final stored = json.encode(SnapshotPruner.movie(rawMovie(), region: 'US'));

    test('a stored document and a live view read the same', () {
      final fromDb = MovieSnapshot.fromJson(stored, fetchedAt: DateTime(2025, 1, 1), providersRegion: 'US');
      final live = MovieSnapshot.live(rawMovie(), region: 'US');

      expect(fromDb.tracked, isTrue);
      expect(live.tracked, isFalse);
      for (final snapshot in [fromDb, live]) {
        expect(snapshot.tmdbId, 550);
        expect(snapshot.imdbId, 'tt0137523');
        expect(snapshot.posterPath, '/p-en-7.jpg');
        expect(snapshot.backdropPath, '/b-2.jpg');
        expect(snapshot.cast.length, SnapshotPruner.castLimit);
        expect(snapshot.related.map((m) => m.id).first, 101);
        expect(snapshot.genreNames, ['Drama', 'Thriller']);
        expect(snapshot.trailerUrl, 'https://www.youtube.com/watch?v=yt1');
        expect(snapshot.certification('US'), 'R');
      }
    });

    test('providers come back for the stored region only, sorted with logo URLs', () {
      final snapshot = MovieSnapshot.fromJson(stored, fetchedAt: DateTime(2025, 1, 1), providersRegion: 'US');

      final result = snapshot.providersFor('US')!;
      expect(result.providers.map((p) => p.providerId), [9, 8]);
      expect(result.providers.first.logoPath, 'https://image.tmdb.org/t/p/w92/logo9.jpg');
      expect(result.justWatchLink, 'https://www.themoviedb.org/movie/550/watch?locale=US');
      expect(snapshot.providersFor('GB'), isNull);
    });

    test('the top-level paths are the fallback when the document has no images', () {
      final snapshot = MovieSnapshot.live({'id': 1, 'poster_path': '/p.jpg', 'backdrop_path': '/b.jpg'}, region: null);

      expect(snapshot.posterPath, '/p.jpg');
      expect(snapshot.backdropPath, '/b.jpg');
      expect(snapshot.providersFor('US'), isNull);
      expect(snapshot.cast, isEmpty);
      expect(snapshot.related, isEmpty);
    });

    test('staleness follows fetchedAt', () {
      final fresh = MovieSnapshot.fromJson(stored, fetchedAt: DateTime.now(), providersRegion: 'US');
      final old = MovieSnapshot.fromJson(stored, fetchedAt: DateTime.now().subtract(const Duration(hours: 49)), providersRegion: 'US');

      expect(fresh.isStale, isFalse);
      expect(old.isStale, isTrue);
      expect(MovieSnapshot.live(rawMovie(), region: 'US').isStale, isTrue);
    });

    test('a corrupt stored document throws a FormatException', () {
      expect(() => MovieSnapshot.fromJson('[1, 2]', fetchedAt: null, providersRegion: null), throwsFormatException);
      expect(() => MovieSnapshot.fromJson('{', fetchedAt: null, providersRegion: null), throwsFormatException);
    });
  });

  group('ShowSnapshot', () {
    test('a live view carries its appended seasons, pruned', () {
      final snapshot = ShowSnapshot.live(rawShow(), region: 'US');

      expect(snapshot.tmdbId, 1399);
      expect(snapshot.imdbId, 'tt0944947');
      expect(snapshot.seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(snapshot.appendedSeasons.keys, [1, 2]);
      final season = snapshot.appendedSeasons[1]!;
      expect(season.details.id, 3624);
      expect(season.episodes.length, 2);
      expect(season.episode(1)!.guestStars.length, SnapshotPruner.guestStarsLimit);
      expect(season.episode(3), isNull);
      expect(season.posterPath, '/season-1.jpg');
    });

    test('a stored document reads the same as the live root', () {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: 'US');
      final fromDb = ShowSnapshot.fromJson(json.encode(pruned.root), fetchedAt: DateTime(2025, 1, 1), providersRegion: 'US');
      final live = ShowSnapshot.live(rawShow(), region: 'US');

      expect(fromDb.appendedSeasons, isEmpty);
      for (final snapshot in [fromDb, live]) {
        expect(snapshot.posterPath, '/sp-en-7.jpg');
        expect(snapshot.backdropPath, '/sb-1.jpg');
        expect(snapshot.cast.length, SnapshotPruner.castLimit);
        expect(snapshot.related.map((s) => s.id), [1, 2]);
        expect(snapshot.certification('US'), 'TV-MA');
        expect(snapshot.trailerUrl, 'https://www.youtube.com/watch?v=yt-got');
        expect(snapshot.providersFor('US')!.providers.single.providerId, 8);
        expect(snapshot.providersFor('RO'), isNull);
      }
    });
  });

  group('SeasonSnapshot', () {
    test('a stored season document parses with its episodes', () {
      final pruned = SnapshotPruner.season(rawAppendedSeason(3, episodes: 3), id: 77);
      final snapshot = SeasonSnapshot.fromJson(json.encode(pruned), fetchedAt: DateTime(2025, 1, 1));

      expect(snapshot.seasonNumber, 3);
      expect(snapshot.details.id, 77);
      expect(snapshot.episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(snapshot.episode(3)!.airDate, isNull);
      expect(snapshot.tracked, isTrue);
    });
  });
}
