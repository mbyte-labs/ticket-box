import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/service/external_rating/omdb_value_parser.dart';
import 'package:ticketbox/service/external_rating/season_score_calculator.dart';

void main() {
  group('SeasonScoreCalculator.weightedAverage', () {
    test('weights by vote count, so a tiny outlier cannot drag a heavy score', () {
      // Simple mean would be (9.0 + 1.0) / 2 = 5.0; weighted, the 3-vote special barely moves it.
      const episodes = [
        TmdbSeasonEpisode(id: 1, seasonNumber: 1, episodeNumber: 1, voteAverage: 9.0, voteCount: 997),
        TmdbSeasonEpisode(id: 2, seasonNumber: 1, episodeNumber: 2, voteAverage: 1.0, voteCount: 3),
      ];

      final result = SeasonScoreCalculator.weightedAverage(episodes);

      expect(result.score, closeTo(8.976, 0.001));
      expect(result.votes, 1000);
    });

    test('skips episodes without votes instead of letting their zero average poison the mean', () {
      const episodes = [
        TmdbSeasonEpisode(id: 1, seasonNumber: 1, episodeNumber: 1, voteAverage: 8.0, voteCount: 100),
        TmdbSeasonEpisode(id: 2, seasonNumber: 1, episodeNumber: 2, voteAverage: 0, voteCount: 0),
      ];

      final result = SeasonScoreCalculator.weightedAverage(episodes);

      expect(result.score, 8.0);
      expect(result.votes, 100);
    });

    test('a voteless season (e.g. unaired) yields a null score, not zero', () {
      const episodes = [
        TmdbSeasonEpisode(id: 1, seasonNumber: 1, episodeNumber: 1, voteAverage: 0, voteCount: 0),
        TmdbSeasonEpisode(id: 2, seasonNumber: 1, episodeNumber: 2, voteAverage: 0, voteCount: 0),
      ];

      final result = SeasonScoreCalculator.weightedAverage(episodes);

      expect(result.score, isNull);
      expect(result.votes, 0);
    });

    test('an empty episode list yields a null score', () {
      final result = SeasonScoreCalculator.weightedAverage(const []);

      expect(result.score, isNull);
      expect(result.votes, 0);
    });
  });

  group('OmdbValueParser', () {
    test('parses a plain rating', () {
      expect(OmdbValueParser.parseRating('8.2'), 8.2);
    });

    test('maps "N/A" and null ratings to null', () {
      expect(OmdbValueParser.parseRating('N/A'), isNull);
      expect(OmdbValueParser.parseRating(null), isNull);
    });

    test('parses comma-grouped vote counts', () {
      expect(OmdbValueParser.parseVotes('135,825'), 135825);
      expect(OmdbValueParser.parseVotes('523'), 523);
    });

    test('maps "N/A" and null vote counts to null', () {
      expect(OmdbValueParser.parseVotes('N/A'), isNull);
      expect(OmdbValueParser.parseVotes(null), isNull);
    });
  });
}
