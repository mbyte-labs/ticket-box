enum WatchedConfirmationDateSelect {
  rightNow,

  /// Sugests that the date should be set as the item you are marking as watched
  ///
  /// If movie or show, then it is movie or show release date.
  ///
  /// If episode, then the release date should be equal to the show release date
  releaseDate,

  /// Sugests that the date should be set as when the season was released
  seasonReleaseDate,

  /// Sugests that the date should be set as when the episode was released
  ///
  /// Applicable only when marking as watched episode or an entire season or show
  episodeReleaseDate,
  custom,
}
