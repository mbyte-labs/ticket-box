import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';

/// Derives a season-level TMDB score from its episodes' votes — TMDB rates shows and
/// episodes, never seasons.
class SeasonScoreCalculator {
  SeasonScoreCalculator._();

  /// Vote-count-weighted average of the episodes' `vote_average`, over episodes that have
  /// votes at all.
  ///
  /// Weighted rather than a plain mean so the displayed percentage stays consistent with the
  /// displayed vote pool ([votes] is the sum of the included episodes' counts) — a 3-vote
  /// special must not drag a score computed over thousands of votes. No votes anywhere
  /// (e.g. an unaired season) yields a null score and 0 votes.
  static ({double? score, int votes}) weightedAverage(List<TmdbSeasonEpisode> episodes) {
    return weighted(episodes.map((e) => (voteAverage: e.voteAverage, voteCount: e.voteCount)));
  }

  /// [weightedAverage] over the cached episodes of a season.
  static ({double? score, int votes}) weightedFromEpisodes(List<EpisodeEntity> episodes) {
    return weighted(episodes.map((e) => (voteAverage: e.voteAverage, voteCount: e.voteCount)));
  }

  static ({double? score, int votes}) weighted(Iterable<({double voteAverage, int voteCount})> votes) {
    var totalVotes = 0;
    var weightedSum = 0.0;

    for (final episode in votes) {
      if (episode.voteCount <= 0) {
        continue;
      }
      totalVotes += episode.voteCount;
      weightedSum += episode.voteAverage * episode.voteCount;
    }

    if (totalVotes == 0) {
      return (score: null, votes: 0);
    }

    return (score: weightedSum / totalVotes, votes: totalVotes);
  }
}
