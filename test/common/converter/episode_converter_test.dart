import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/common/converter/episode.dart';
import 'package:ticketbox/common/model/episode_type.dart';

/// Covers the `episodeType` hop through [EpisodeConverter]. The field is what drives the
/// season/series/mid-season finale pills: the inferred [EpisodeType] has to land in the episode row
/// as its wire value and read back as the same type.
/// (The inference itself is covered by `episode_type_inference_test.dart`.)
void main() {
  TmdbSeasonEpisode seasonEpisode({int? runtime, String? airDate = '2022-10-23'}) {
    return TmdbSeasonEpisode(
      id: 555,
      episodeNumber: 10,
      seasonNumber: 1,
      name: 'The Black Queen',
      overview: 'Season finale.',
      airDate: airDate,
      runtime: runtime,
      episodeType: 'finale',
      voteAverage: 8.7,
      voteCount: 12345,
      stillPath: '/still.jpg',
    );
  }

  group('fromSeasonEpisode', () {
    test('stores the inferred type as its wire value and reads it back', () {
      final entity = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(), type: EpisodeType.seasonFinale);

      expect(entity.episodeType, 'season_finale');
      expect(entity.type, EpisodeType.seasonFinale);
      expect(entity.tmdbId, 555);
      expect((entity.showTmdbId, entity.season, entity.episode), (1, 1, 10));
    });

    test('a standard episode round-trips as standard', () {
      final entity = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(), type: EpisodeType.standard);

      expect(entity.type, EpisodeType.standard);
    });

    test('keeps the air date verbatim and derives local midnight from it', () {
      final entity = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(), type: EpisodeType.standard);

      expect(entity.airDate, '2022-10-23');
      expect(entity.firstAired, DateTime(2022, 10, 23));
      expect(entity.stillPath, '/still.jpg');
    });

    test('an empty or missing air date is stored as null and never reads as aired', () {
      final empty = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(airDate: ''), type: EpisodeType.standard);
      final missing = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(airDate: null), type: EpisodeType.standard);

      expect(empty.airDate, isNull);
      expect(empty.firstAired, isNull);
      expect(missing.airDate, isNull);
      expect(missing.firstAired, isNull);
    });

    test('falls back to the show runtime when the episode has none', () {
      final withOwn = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(runtime: 58), type: EpisodeType.standard, showRuntime: 45);
      final withShow = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(), type: EpisodeType.standard, showRuntime: 45);
      final withNone = EpisodeConverter.fromSeasonEpisode(1, seasonEpisode(runtime: 0), type: EpisodeType.standard);

      expect(withOwn.runtime, 58);
      expect(withShow.runtime, 45);
      expect(withNone.runtime, isNull);
    });
  });

  test('an unknown stored wire value degrades to standard instead of throwing', () {
    // A row written by a build with a richer enum must still decode on an older one.
    expect(EpisodeType.fromWireValue('some_future_type'), EpisodeType.standard);
    expect(EpisodeType.fromWireValue(null), EpisodeType.standard);
  });
}
