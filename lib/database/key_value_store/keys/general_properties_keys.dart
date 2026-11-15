class GeneralPropertiesKeys {
  /// This key is used to set the property that defines whether or not the
  /// application loads the filters from store when the user first open an app page
  static const rememberFiltersOption = 'option_general_app_remember_filters_option';

  /// This stores a string of type poster size
  static const posterSize = 'option_general_app_poster_size';

  /// Stores a string of type poster quality
  static const posterQuality = 'option_general_app_poster_quality';

  /// This key stores the landing page where the user will be redirected when
  /// starting the app
  static const defaultLandingPage = 'optionn_general_app_default_landing_page';

  static const showPerformanceOverlay = 'optionn_general_app_performance_overlay';

  static const appInfoStartCount = 'optionn_general_app_info_start_count';

  static const String preferedWatchProvider = 'options_general_prefered_watch_provider';

  /// ISO 3166-1 country code used to query streaming availability (watch providers).
  /// Absent until the user picks a country on the settings page.
  static const String watchProviderRegion = 'options_general_watch_provider_region';
}
