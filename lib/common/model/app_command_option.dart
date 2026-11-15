enum AppCommandOption {
  checkIn,
  checkInRemove,
  //
  historyAdd,
  historyRemove,
  //
  ratingAdd,
  ratingRemove,
  //
  watchlistAdd,
  watchlistRemove,
  //
  hiddenAdd,
  hiddenRemove,
  //
  playbackUpdate,
  playbackComplete,
  playbackRemove,

  /// When the app is syncing in the background, this is a general task to
  /// let the system know there is some background work going on
  internalSync,
  internalFullSync,
}

enum AppCommandProcessState { inProggress, error, finished }
