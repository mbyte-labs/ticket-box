/// All the keys used by the SharedPreference storage to save data
class UpNextToWatchPropertiesKeys {
  /// This stores a string of type poster size
  static const posterSize = 'option_up_next_to_watch_page_poster_size';

  static const displayRating = 'option_up_next_to_watch_page_poster_display_rating';

  static const displayUserRating = 'option_up_next_to_watch_page_poster_display_user_rating';

  static const switchTapWithLongPress = 'option_up_next_to_watch_page_switch_tap_with_long_press';

  /// Stores the json of the [DashboardPageFilterOptions] that were last applied on the page,
  /// so that the selection survives an application restart
  static const filters = 'option_up_next_to_watch_page_filters';

  /// True once the user dismissed the "set your country" banner. Absent = never dismissed.
  static const countryBannerDismissed = 'option_up_next_to_watch_country_banner_dismissed';

  /// If this is set to true, then the next episode will be calculated based on
  /// the last watched episode.
  /// Ex: When suggesting next episode, if you have watched 4 and 5 then watched
  /// 11th episode the next one will be showed 12 to watch, but if you then mark
  /// episode 1 as watched the next episode to watch will be 2
  static const nextEpisodeBasedOnLastActivity = 'option_app_next_episode_based_on_last_activity_option';
}
