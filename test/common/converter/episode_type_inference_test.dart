import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/converter/episode_type_inference.dart';
import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/common/model/show_status.dart';

/// TMDB only reports `standard` / `finale` / `mid_season`; everything richer is inferred here, so each rule
/// and its priority over the ones below it is pinned down.
void main() {
  EpisodeType infer({
    required int season,
    required int episode,
    String? tmdbType,
    bool previousWasMidSeasonFinale = false,
    ShowStatus showStatus = ShowStatus.returningSeries,
    int lastSeasonNumber = 3,
  }) {
    return EpisodeTypeInference.infer(
      season: season,
      episode: episode,
      tmdbType: tmdbType,
      previousWasMidSeasonFinale: previousWasMidSeasonFinale,
      showStatus: showStatus,
      lastSeasonNumber: lastSeasonNumber,
    );
  }

  group('infer', () {
    test('specials are always standard, whatever TMDB says', () {
      expect(infer(season: 0, episode: 1), EpisodeType.standard);
      expect(infer(season: 0, episode: 5, tmdbType: 'finale', showStatus: ShowStatus.ended, lastSeasonNumber: 0), EpisodeType.standard);
      expect(infer(season: 0, episode: 2, tmdbType: 'mid_season'), EpisodeType.standard);
      expect(infer(season: 0, episode: 2, previousWasMidSeasonFinale: true), EpisodeType.standard);
    });

    test('S1E1 is the series premiere', () {
      expect(infer(season: 1, episode: 1), EpisodeType.seriesPremiere);
    });

    test('episode 1 of any later season is a season premiere', () {
      expect(infer(season: 2, episode: 1), EpisodeType.seasonPremiere);
      expect(infer(season: 7, episode: 1), EpisodeType.seasonPremiere);
    });

    test('a one-episode season: the premiere wins over the finale flag', () {
      expect(
        infer(season: 3, episode: 1, tmdbType: 'finale', showStatus: ShowStatus.ended, lastSeasonNumber: 3),
        EpisodeType.seasonPremiere,
      );
      expect(
        infer(season: 1, episode: 1, tmdbType: 'finale', showStatus: ShowStatus.ended, lastSeasonNumber: 1),
        EpisodeType.seriesPremiere,
      );
    });

    test('the premiere wins over the mid-season flags', () {
      expect(infer(season: 2, episode: 1, tmdbType: 'mid_season'), EpisodeType.seasonPremiere);
      expect(infer(season: 2, episode: 1, previousWasMidSeasonFinale: true), EpisodeType.seasonPremiere);
    });

    test("TMDB's mid_season is a mid-season finale", () {
      expect(infer(season: 1, episode: 8, tmdbType: 'mid_season'), EpisodeType.midSeasonFinale);
    });

    test('mid_season wins over a stale previousWasMidSeasonFinale flag', () {
      expect(infer(season: 1, episode: 8, tmdbType: 'mid_season', previousWasMidSeasonFinale: true), EpisodeType.midSeasonFinale);
    });

    test('the episode after a mid-season finale is a mid-season premiere', () {
      expect(infer(season: 1, episode: 9, previousWasMidSeasonFinale: true), EpisodeType.midSeasonPremiere);
    });

    test('mid-season premiere wins over a finale flag on the same episode', () {
      expect(
        infer(
          season: 1,
          episode: 9,
          tmdbType: 'finale',
          previousWasMidSeasonFinale: true,
          showStatus: ShowStatus.ended,
          lastSeasonNumber: 1,
        ),
        EpisodeType.midSeasonPremiere,
      );
    });

    test('ended show, finale of the last season -> series finale', () {
      expect(
        infer(season: 3, episode: 10, tmdbType: 'finale', showStatus: ShowStatus.ended, lastSeasonNumber: 3),
        EpisodeType.seriesFinale,
      );
    });

    test('canceled show, finale of the last season -> series finale', () {
      expect(
        infer(season: 3, episode: 10, tmdbType: 'finale', showStatus: ShowStatus.canceled, lastSeasonNumber: 3),
        EpisodeType.seriesFinale,
      );
    });

    test('ended show, finale of an earlier season -> season finale', () {
      expect(
        infer(season: 2, episode: 10, tmdbType: 'finale', showStatus: ShowStatus.ended, lastSeasonNumber: 3),
        EpisodeType.seasonFinale,
      );
    });

    test('returning show, finale of the last known season -> season finale', () {
      expect(
        infer(season: 3, episode: 10, tmdbType: 'finale', showStatus: ShowStatus.returningSeries, lastSeasonNumber: 3),
        EpisodeType.seasonFinale,
      );
      expect(
        infer(season: 3, episode: 10, tmdbType: 'finale', showStatus: ShowStatus.inProduction, lastSeasonNumber: 3),
        EpisodeType.seasonFinale,
      );
      expect(
        infer(season: 3, episode: 10, tmdbType: 'finale', showStatus: ShowStatus.unknown, lastSeasonNumber: 3),
        EpisodeType.seasonFinale,
      );
    });

    test('plain episodes are standard, including unknown or missing TMDB types', () {
      expect(infer(season: 1, episode: 5), EpisodeType.standard);
      expect(infer(season: 1, episode: 5, tmdbType: 'standard'), EpisodeType.standard);
      expect(infer(season: 1, episode: 5, tmdbType: 'something_new'), EpisodeType.standard);
      expect(infer(season: 3, episode: 5, showStatus: ShowStatus.ended, lastSeasonNumber: 3), EpisodeType.standard);
    });
  });

  group('inferSeason', () {
    test('threads the mid-season finale into the following episode', () {
      final types = EpisodeTypeInference.inferSeason(
        season: 2,
        episodes: const [
          (episode: 1, tmdbType: 'standard'),
          (episode: 2, tmdbType: null),
          (episode: 3, tmdbType: 'mid_season'),
          (episode: 4, tmdbType: 'standard'),
          (episode: 5, tmdbType: 'standard'),
          (episode: 6, tmdbType: 'finale'),
        ],
        showStatus: ShowStatus.returningSeries,
        lastSeasonNumber: 2,
      );

      expect(types, const [
        EpisodeType.seasonPremiere,
        EpisodeType.standard,
        EpisodeType.midSeasonFinale,
        EpisodeType.midSeasonPremiere,
        EpisodeType.standard,
        EpisodeType.seasonFinale,
      ]);
    });

    test('sorts by episode number before threading', () {
      final types = EpisodeTypeInference.inferSeason(
        season: 1,
        episodes: const [(episode: 3, tmdbType: 'standard'), (episode: 1, tmdbType: 'standard'), (episode: 2, tmdbType: 'mid_season')],
        showStatus: ShowStatus.returningSeries,
        lastSeasonNumber: 1,
      );

      expect(types, const [EpisodeType.seriesPremiere, EpisodeType.midSeasonFinale, EpisodeType.midSeasonPremiere]);
    });

    test('last season of an ended show ends with the series finale', () {
      final types = EpisodeTypeInference.inferSeason(
        season: 4,
        episodes: const [(episode: 1, tmdbType: 'standard'), (episode: 2, tmdbType: 'finale')],
        showStatus: ShowStatus.ended,
        lastSeasonNumber: 4,
      );

      expect(types, const [EpisodeType.seasonPremiere, EpisodeType.seriesFinale]);
    });

    test('does not mutate the input list', () {
      final input = [(episode: 2, tmdbType: 'standard'), (episode: 1, tmdbType: 'standard')];
      final snapshot = List.of(input);

      EpisodeTypeInference.inferSeason(season: 1, episodes: input, showStatus: ShowStatus.returningSeries, lastSeasonNumber: 1);

      expect(input, snapshot);
    });

    test('empty season yields an empty list', () {
      final types = EpisodeTypeInference.inferSeason(season: 1, episodes: const [], showStatus: ShowStatus.ended, lastSeasonNumber: 1);

      expect(types, isEmpty);
    });
  });
}
