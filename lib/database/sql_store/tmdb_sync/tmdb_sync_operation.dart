import 'package:ticketbox/common/model/tmdb_data_set.dart';

/// One write waiting in the TMDB sync outbox.
enum TmdbSyncOperation {
  rate,
  unrate,
  watchlistAdd,
  watchlistRemove,
  favoriteAdd,
  favoriteRemove;

  /// The data set the operation belongs to. The outbox coalesces per data set and key, and a
  /// toggle turned off drops the operations of its data set.
  TmdbDataSet get dataSet => switch (this) {
    TmdbSyncOperation.rate || TmdbSyncOperation.unrate => TmdbDataSet.ratings,
    TmdbSyncOperation.watchlistAdd || TmdbSyncOperation.watchlistRemove => TmdbDataSet.watchlist,
    TmdbSyncOperation.favoriteAdd || TmdbSyncOperation.favoriteRemove => TmdbDataSet.favorites,
  };

  /// The operations of [dataSet].
  static List<TmdbSyncOperation> of(TmdbDataSet dataSet) => values.where((operation) => operation.dataSet == dataSet).toList();
}
