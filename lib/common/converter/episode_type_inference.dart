import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/common/model/show_status.dart';

/// Derives the full [EpisodeType] classification from what TMDB exposes.
///
/// TMDB's `episode_type` on `/tv/{id}/season/{n}` only knows `standard`, `finale` and `mid_season`.
/// The v3 sync backend used to hand us premieres, mid-season premieres and series finales directly; those are now
/// inferred from the episode's numbering, the previous episode's classification and the show's status.
class EpisodeTypeInference {
  const EpisodeTypeInference._();

  static const String _tmdbFinale = 'finale';
  static const String _tmdbMidSeason = 'mid_season';

  /// Infers the richer classification from TMDB's coarse `episode_type` plus numbering/status.
  ///
  /// Rules, in priority order:
  /// 1. specials (`season == 0`) are always [EpisodeType.standard];
  /// 2. the first episode of a season is a premiere — series premiere for season 1, season premiere otherwise;
  /// 3. TMDB's `mid_season` is a [EpisodeType.midSeasonFinale];
  /// 4. the episode right after a mid-season finale is a [EpisodeType.midSeasonPremiere];
  /// 5. TMDB's `finale` is a [EpisodeType.seriesFinale] when the show has concluded and this is its last
  ///    season, a [EpisodeType.seasonFinale] otherwise;
  /// 6. anything else is [EpisodeType.standard].
  static EpisodeType infer({
    required int season,
    required int episode,
    required String? tmdbType,
    required bool previousWasMidSeasonFinale,
    required ShowStatus showStatus,
    required int lastSeasonNumber,
  }) {
    if (season == 0) {
      return EpisodeType.standard;
    }
    if (episode == 1) {
      return season == 1 ? EpisodeType.seriesPremiere : EpisodeType.seasonPremiere;
    }
    if (tmdbType == _tmdbMidSeason) {
      return EpisodeType.midSeasonFinale;
    }
    if (previousWasMidSeasonFinale) {
      return EpisodeType.midSeasonPremiere;
    }
    if (tmdbType == _tmdbFinale) {
      return showStatus.isConcluded && season == lastSeasonNumber ? EpisodeType.seriesFinale : EpisodeType.seasonFinale;
    }
    return EpisodeType.standard;
  }

  /// Classifies a whole season at once.
  ///
  /// [episodes] are sorted by episode number first, so the `previousWasMidSeasonFinale` flag is threaded in
  /// airing order regardless of how the caller assembled the list. The result is in that sorted order.
  static List<EpisodeType> inferSeason({
    required int season,
    required List<({int episode, String? tmdbType})> episodes,
    required ShowStatus showStatus,
    required int lastSeasonNumber,
  }) {
    final ordered = List.of(episodes)..sort((a, b) => a.episode.compareTo(b.episode));

    final types = <EpisodeType>[];
    var previousWasMidSeasonFinale = false;
    for (final entry in ordered) {
      final type = infer(
        season: season,
        episode: entry.episode,
        tmdbType: entry.tmdbType,
        previousWasMidSeasonFinale: previousWasMidSeasonFinale,
        showStatus: showStatus,
        lastSeasonNumber: lastSeasonNumber,
      );
      types.add(type);
      previousWasMidSeasonFinale = type == EpisodeType.midSeasonFinale;
    }
    return types;
  }
}
