import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/library/dropped_shows_service.dart';
import 'package:ticketbox/service/library/favorite_service.dart';
import 'package:ticketbox/service/poster/poster_model_resolver.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';
import 'package:ticketbox/ui/pages/lists/lists_state.dart';

/// Counts the items on each built-in list and picks a few of their posters for the list cards,
/// kept current while the Lists page is open.
class ListsBloc extends Cubit<ListsState> {
  static final _log = Logger('[Bloc] ListsBloc');

  /// How many of the most recently added items each card shows a poster for.
  static const _previewCount = 5;

  final _resolver = PosterModelResolver();

  StreamSubscription<Set<DataChangeEvent>>? _changes;

  ListsBloc() : super(ListsState.initial()) {
    // The catalogue is included so the cards pick up the artwork paths the backfill writes later.
    // load() only reads the database, so it cannot feed back into another change.
    _changes = DataChangeMonitor.instance().changes.listen((events) {
      if (events.contains(DataChangeEvent.watchlistRepo) ||
          events.contains(DataChangeEvent.showStateRepo) ||
          events.contains(DataChangeEvent.favoriteRepo) ||
          events.contains(DataChangeEvent.catalogRepo)) {
        unawaited(load());
      }
    });
  }

  Future<void> load() async {
    try {
      final (watchlistCount, droppedCount, favoritesCount, (watchlistPosters, droppedPosters, favoritesPosters)) = await (
        WatchlistService().count(),
        DroppedShowsService().count(),
        FavoriteService().count(),
        _loadPreviews(),
      ).wait;
      if (!isClosed) {
        emit(
          ListsState(
            watchlistCount: watchlistCount,
            droppedCount: droppedCount,
            favoritesCount: favoritesCount,
            watchlistPosters: watchlistPosters,
            droppedPosters: droppedPosters,
            favoritesPosters: favoritesPosters,
          ),
        );
      }
    } catch (e, stackTrace) {
      _log.warning('Could not count the lists', e, stackTrace);
    }
  }

  /// The posters of each list's newest items, read from the local catalogue. Never fails: the
  /// posters are decoration, so a failure here just leaves the cards without them rather than
  /// hiding the counts.
  Future<(List<ArtworkRef>, List<ArtworkRef>, List<ArtworkRef>)> _loadPreviews() async {
    try {
      final (watchlist, dropped, favorites) = await (
        WatchlistService().get(ItemType.values, OrderType.descending, const PageDetails(page: 1, pageSize: _previewCount)),
        DroppedShowsService().getAll(),
        FavoriteService().getAll(const [ItemType.movie, ItemType.show]),
      ).wait;
      return await (
        _posters(watchlist.data.map((item) => item.key)),
        _posters(dropped.take(_previewCount).map((item) => MediaKey.show(item.showTmdbId))),
        _posters(favorites.take(_previewCount).map((item) => item.key)),
      ).wait;
    } catch (e, stackTrace) {
      _log.warning('Could not load the list posters', e, stackTrace);
      return (const <ArtworkRef>[], const <ArtworkRef>[], const <ArtworkRef>[]);
    }
  }

  /// The poster of every key that has one; a key without artwork (a stub, or a title TMDB has no
  /// poster for) is left out rather than shown as a blank card.
  Future<List<ArtworkRef>> _posters(Iterable<MediaKey> keys) async {
    final models = await _resolver.resolve(keys);
    return [
      for (final model in models)
        if (model.posterPath != null) ArtworkRef.fromPosterKey(model.key, model.posterPath),
    ];
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
