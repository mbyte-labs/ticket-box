import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/service/progress/show_progress_calculator.dart';

/// Pins down the v3 progress semantics the calculator reproduces locally: what counts as aired, what
/// counts as completed, how specials and unknown episodes are treated, and both flavours of "up next".
void main() {
  // A fixed "now" in the middle of a day, so that "later today" and "tomorrow" are unambiguous.
  final now = DateTime(2026, 10, 4, 12, 30);
  final yesterday = DateTime(2026, 10, 3, 20);
  final laterToday = DateTime(2026, 10, 4, 22);
  final startOfTomorrow = DateTime(2026, 10, 5);
  final longAgo = DateTime(2020, 1, 1);

  CatalogueEpisode ep(int season, int episode, DateTime? firstAired) =>
      CatalogueEpisode(season: season, episode: episode, firstAired: firstAired);

  WatchedEpisode seen(int season, int episode, DateTime watchedAt, {HistoryAction action = HistoryAction.watch}) =>
      WatchedEpisode(season: season, episode: episode, watchedAt: watchedAt, action: action);

  EpisodePosition pos(int season, int episode) => EpisodePosition(season: season, episode: episode);

  /// Two aired seasons of three episodes, plus an unaired S3E1 and a special.
  final twoSeasons = [
    ep(0, 1, longAgo),
    ep(1, 1, longAgo),
    ep(1, 2, longAgo),
    ep(1, 3, longAgo),
    ep(2, 1, longAgo),
    ep(2, 2, longAgo),
    ep(2, 3, yesterday),
    ep(3, 1, startOfTomorrow),
  ];

  group('aired', () {
    test('excludes specials, unaired episodes and episodes without a date', () {
      final result = ShowProgressCalculator.compute(
        catalogue: [ep(0, 1, longAgo), ep(1, 1, longAgo), ep(1, 2, yesterday), ep(1, 3, startOfTomorrow), ep(1, 4, null)],
        watched: const [],
        now: now,
      );

      expect(result.aired, 2);
      expect(result.seasons, [const SeasonProgress(season: 1, aired: 2, completed: 0)]);
    });

    test('an episode airing later today counts as aired', () {
      final result = ShowProgressCalculator.compute(catalogue: [ep(1, 1, longAgo), ep(1, 2, laterToday)], watched: const [], now: now);

      expect(result.aired, 2);
    });

    test('the end-of-day boundary is inclusive and uses the local day of now', () {
      final endOfToday = DateTime(2026, 10, 4, 23, 59, 59);
      final result = ShowProgressCalculator.compute(
        catalogue: [ep(1, 1, endOfToday), ep(1, 2, endOfToday.add(const Duration(seconds: 1)))],
        watched: const [],
        now: now,
      );

      expect(result.aired, 1);
    });
  });

  group('completed', () {
    test('counts any history row regardless of action, including a future-dated check-in', () {
      final result = ShowProgressCalculator.compute(
        catalogue: twoSeasons,
        watched: [
          seen(1, 1, yesterday, action: HistoryAction.scrobble),
          seen(1, 2, yesterday),
          seen(1, 3, now.add(const Duration(minutes: 40)), action: HistoryAction.checkin),
        ],
        now: now,
      );

      expect(result.completed, 3);
      expect(result.seasons.first, const SeasonProgress(season: 1, aired: 3, completed: 3));
      expect(result.episodes.where((item) => item.season == 1).every((item) => item.completed), isTrue);
    });

    test('several rows for the same episode count once', () {
      final result = ShowProgressCalculator.compute(
        catalogue: twoSeasons,
        watched: [
          seen(1, 1, longAgo),
          seen(1, 1, yesterday, action: HistoryAction.scrobble),
        ],
        now: now,
      );

      expect(result.completed, 1);
    });

    test('a watched special is never completed and never counted', () {
      final result = ShowProgressCalculator.compute(catalogue: twoSeasons, watched: [seen(0, 1, yesterday)], now: now);

      expect(result.completed, 0);
      expect(result.episodes.any((item) => item.season == 0), isFalse);
      expect(result.seasons.any((item) => item.season == 0), isFalse);
      // It is still watch history for the show.
      expect(result.hasAnyWatched, isTrue);
      expect(result.lastWatchedAt, yesterday);
    });

    test('a row for an episode missing from the catalogue does not inflate counts but sets lastWatchedAt', () {
      final recent = DateTime(2026, 10, 2);
      final result = ShowProgressCalculator.compute(catalogue: twoSeasons, watched: [seen(1, 1, longAgo), seen(9, 9, recent)], now: now);

      expect(result.completed, 1);
      expect(result.seasons.map((item) => item.completed).toList(), [1, 0, 0]);
      expect(result.episodes.length, 7);
      expect(result.lastWatchedAt, recent);
      expect(result.hasAnyWatched, isTrue);
    });
  });

  group('seasons and episodes', () {
    test('one season row per non-special catalogue season, sorted, with per-season counters', () {
      final result = ShowProgressCalculator.compute(
        catalogue: twoSeasons.reversed.toList(),
        watched: [seen(2, 1, yesterday), seen(1, 3, longAgo)],
        now: now,
      );

      expect(result.seasons, const [
        SeasonProgress(season: 1, aired: 3, completed: 1),
        SeasonProgress(season: 2, aired: 3, completed: 1),
        SeasonProgress(season: 3, aired: 0, completed: 0),
      ]);
      expect(result.aired, 6);
      expect(result.completed, 2);
    });

    test('episodes are sorted S/E, carry the completed flag and skip specials', () {
      final result = ShowProgressCalculator.compute(catalogue: twoSeasons.reversed.toList(), watched: [seen(1, 2, yesterday)], now: now);

      expect(result.episodes, const [
        EpisodeProgress(season: 1, episode: 1, completed: false),
        EpisodeProgress(season: 1, episode: 2, completed: true),
        EpisodeProgress(season: 1, episode: 3, completed: false),
        EpisodeProgress(season: 2, episode: 1, completed: false),
        EpisodeProgress(season: 2, episode: 2, completed: false),
        EpisodeProgress(season: 2, episode: 3, completed: false),
        EpisodeProgress(season: 3, episode: 1, completed: false),
      ]);
    });

    test('lastWatchedAt is the latest row, null when nothing is watched', () {
      final latest = now.add(const Duration(hours: 1));
      final result = ShowProgressCalculator.compute(
        catalogue: twoSeasons,
        watched: [seen(1, 1, yesterday), seen(1, 2, latest), seen(1, 3, longAgo)],
        now: now,
      );
      final empty = ShowProgressCalculator.compute(catalogue: twoSeasons, watched: const [], now: now);

      expect(result.lastWatchedAt, latest);
      expect(empty.lastWatchedAt, isNull);
    });
  });

  group('nextEpisode', () {
    test('nothing watched -> next is S1E1 and hasAnyWatched is false', () {
      final result = ShowProgressCalculator.compute(catalogue: twoSeasons, watched: const [], now: now);

      expect(result.nextEpisode, pos(1, 1));
      expect(result.hasAnyWatched, isFalse);
      expect(result.completed, 0);
    });

    test('only a special watched -> next is still the first regular episode', () {
      final result = ShowProgressCalculator.compute(catalogue: twoSeasons, watched: [seen(0, 1, yesterday)], now: now);

      expect(result.nextEpisode, pos(1, 1));
    });

    test('empty catalogue -> no next episode', () {
      final result = ShowProgressCalculator.compute(catalogue: const [], watched: [seen(1, 1, yesterday)], now: now);

      expect(result.nextEpisode, isNull);
      expect(result.aired, 0);
      expect(result.completed, 0);
      expect(result.hasAnyWatched, isTrue);
    });

    group('afterLatestAiredWatched (default)', () {
      test('skips gaps: watched S1E1 and S1E3 -> next is S1E4', () {
        final result = ShowProgressCalculator.compute(
          catalogue: [ep(1, 1, longAgo), ep(1, 2, longAgo), ep(1, 3, longAgo), ep(1, 4, longAgo)],
          watched: [seen(1, 3, longAgo), seen(1, 1, yesterday)],
          now: now,
        );

        expect(result.nextEpisode, pos(1, 4));
      });

      test('crosses into the next season', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [seen(1, 1, longAgo), seen(1, 2, longAgo), seen(1, 3, longAgo)],
          now: now,
        );

        expect(result.nextEpisode, pos(2, 1));
      });

      test('skips an already-watched episode right after the latest one', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [seen(1, 1, longAgo), seen(1, 2, longAgo), seen(2, 1, longAgo)],
          now: now,
        );

        // S1E3 is a gap and is skipped; S2E1 is watched so the pointer moves past it.
        expect(result.nextEpisode, pos(2, 2));
      });

      test('all aired episodes watched -> next is the unaired S3E1', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [
            for (var i = 1; i <= 3; i++) ...[seen(1, i, longAgo), seen(2, i, longAgo)],
          ],
          now: now,
        );

        expect(result.nextEpisode, pos(3, 1));
        expect(result.aired, 6);
        expect(result.completed, 6);
      });

      test('everything watched -> next is null', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [
            for (var i = 1; i <= 3; i++) ...[seen(1, i, longAgo), seen(2, i, longAgo)],
            seen(3, 1, yesterday),
          ],
          now: now,
        );

        expect(result.nextEpisode, isNull);
        expect(result.hasAnyWatched, isTrue);
      });

      test('the latest watched position may be outside the catalogue', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [seen(1, 1, longAgo), seen(1, 5, yesterday)],
          now: now,
        );

        // S1E5 is unknown to the catalogue but is still the furthest point reached.
        expect(result.nextEpisode, pos(2, 1));
      });
    });

    group('afterMostRecentlyWatched', () {
      test('continues from the most recently watched: S1E1 last -> next is S1E2', () {
        final result = ShowProgressCalculator.compute(
          catalogue: [ep(1, 1, longAgo), ep(1, 2, longAgo), ep(1, 3, longAgo), ep(1, 4, longAgo)],
          watched: [seen(1, 3, longAgo), seen(1, 1, yesterday)],
          now: now,
          mode: NextEpisodeMode.afterMostRecentlyWatched,
        );

        expect(result.nextEpisode, pos(1, 2));
      });

      test('skips watched episodes after the most recent one', () {
        final result = ShowProgressCalculator.compute(
          catalogue: [ep(1, 1, longAgo), ep(1, 2, longAgo), ep(1, 3, longAgo), ep(1, 4, longAgo)],
          watched: [seen(1, 2, longAgo), seen(1, 1, yesterday)],
          now: now,
          mode: NextEpisodeMode.afterMostRecentlyWatched,
        );

        expect(result.nextEpisode, pos(1, 3));
      });

      test('ties on watchedAt resolve to the greater S/E', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [seen(2, 1, yesterday), seen(1, 1, yesterday)],
          now: now,
          mode: NextEpisodeMode.afterMostRecentlyWatched,
        );

        expect(result.nextEpisode, pos(2, 2));
      });

      test('a special is ignored even when it is the most recent row', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: [seen(1, 2, longAgo), seen(0, 1, laterToday)],
          now: now,
          mode: NextEpisodeMode.afterMostRecentlyWatched,
        );

        expect(result.nextEpisode, pos(1, 3));
      });

      test('nothing watched -> next is S1E1', () {
        final result = ShowProgressCalculator.compute(
          catalogue: twoSeasons,
          watched: const [],
          now: now,
          mode: NextEpisodeMode.afterMostRecentlyWatched,
        );

        expect(result.nextEpisode, pos(1, 1));
      });
    });
  });

  group('inputs', () {
    test('are not mutated and the result does not depend on their order', () {
      final catalogue = twoSeasons.reversed.toList();
      final watched = [seen(2, 1, yesterday), seen(1, 1, longAgo), seen(1, 2, longAgo)];
      final catalogueSnapshot = List.of(catalogue);
      final watchedSnapshot = List.of(watched);

      final shuffled = ShowProgressCalculator.compute(catalogue: catalogue, watched: watched, now: now);
      final ordered = ShowProgressCalculator.compute(catalogue: twoSeasons, watched: watched.reversed.toList(), now: now);

      expect(catalogue, catalogueSnapshot);
      expect(watched, watchedSnapshot);
      expect(shuffled.episodes, ordered.episodes);
      expect(shuffled.seasons, ordered.seasons);
      expect(shuffled.nextEpisode, ordered.nextEpisode);
      expect(shuffled.aired, ordered.aired);
      expect(shuffled.completed, ordered.completed);
    });

    test('duplicate catalogue rows count once', () {
      final result = ShowProgressCalculator.compute(
        catalogue: [ep(1, 1, longAgo), ep(1, 1, longAgo)],
        watched: [seen(1, 1, yesterday)],
        now: now,
      );

      expect(result.aired, 1);
      expect(result.completed, 1);
      expect(result.episodes.length, 1);
    });
  });

  group('EpisodePosition', () {
    test('orders by season then episode', () {
      expect(pos(1, 10).compareTo(pos(2, 1)), lessThan(0));
      expect(pos(2, 1).compareTo(pos(1, 10)), greaterThan(0));
      expect(pos(1, 2).compareTo(pos(1, 3)), lessThan(0));
      expect(pos(1, 3).compareTo(pos(1, 3)), 0);
      expect(pos(1, 10) > pos(1, 9), isTrue);
      expect(pos(1, 10) < pos(2, 1), isTrue);
    });

    test('value equality', () {
      expect(pos(1, 2), pos(1, 2));
      expect(pos(1, 2).hashCode, pos(1, 2).hashCode);
      expect(pos(1, 2), isNot(pos(2, 1)));
      expect({pos(1, 2), pos(1, 2)}.length, 1);
    });
  });
}
