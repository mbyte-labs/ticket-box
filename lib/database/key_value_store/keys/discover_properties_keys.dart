/// All the keys used by the SharedPreference storage to save the discover page's options
class DiscoverPropertiesKeys {
  /// Stores the json of the `DiscoverFilterOptions` that were last applied on the discover page
  /// (list, minimum votes, rating, years, per-type genres), so that the selection survives an
  /// application restart
  static const filters = 'option_discover_page_filters';
}
