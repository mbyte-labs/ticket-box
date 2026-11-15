/// Classification of an episode within its season and series.
///
/// The wire values are the ones the persisted `episodeType` column has always held, so rows
/// written before the TMDB switch keep decoding. TMDB only distinguishes `standard`, `finale` and
/// `mid_season` on `/tv/{id}/season/{n}`; the premiere and series-finale variants are inferred by
/// `EpisodeTypeInference` from numbering and the show's status. Anything unrecognised degrades to
/// [standard].
enum EpisodeType {
  standard('standard'),

  /// Season 1, episode 1.
  seriesPremiere('series_premiere'),

  /// Episode 1 of any other season.
  seasonPremiere('season_premiere'),

  midSeasonFinale('mid_season_finale'),

  /// The next episode after the mid season finale.
  midSeasonPremiere('mid_season_premiere'),

  seasonFinale('season_finale'),

  /// Last episode of a show that has ended or was canceled.
  seriesFinale('series_finale');

  const EpisodeType(this.wireValue);

  /// The value persisted in the local `episodes` table.
  final String wireValue;

  static EpisodeType fromWireValue(String? value) {
    return EpisodeType.values.firstWhere((type) => type.wireValue == value, orElse: () => EpisodeType.standard);
  }

  bool get isPremiere => this == seriesPremiere || this == seasonPremiere;
}
