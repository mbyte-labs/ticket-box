import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';

/// The pure rules of the TMDB account sync: what can be synced and how ratings translate.
class TmdbSyncSupport {
  TmdbSyncSupport._();

  /// Whether [key] has a place in [dataSet] on TMDB. Ratings exist for movies, shows and episodes
  /// (a season is never rated in the app either); the TMDB watchlist and favorites hold whole
  /// movies and shows only, so the app's season and episode watchlist rows stay on the device.
  static bool canSync(TmdbDataSet dataSet, MediaKey key) => switch (dataSet) {
    TmdbDataSet.ratings => key.type != ItemType.season,
    TmdbDataSet.watchlist || TmdbDataSet.favorites => key.type == ItemType.movie || key.type == ItemType.show,
  };

  /// TMDB's 0.5–10 half-step value as the app's whole 1–10 rating: rounded half up and clamped, so
  /// 7.5 becomes 8 and 0.5 becomes 1.
  static int roundTmdbRating(double value) {
    final rounded = (value + 0.5).floor();
    return rounded.clamp(1, 10);
  }

  /// The app's whole rating as TMDB's decimal value.
  static double toTmdbRating(int rating) => rating.toDouble();
}
