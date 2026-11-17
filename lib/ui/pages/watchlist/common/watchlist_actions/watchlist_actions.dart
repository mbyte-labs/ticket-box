import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';

/// The watchlist grid's long press sheet: removing one poster from the watchlist.
///
/// Unlike the watch history sheet there is no scope to choose. A watchlist row is one item, not an
/// aggregate over plays, so a season tile removes that season and nothing else - the show it
/// belongs to may well be on the list in its own right.
///
/// Every string the sheet needs is already on the [PosterModel] the grid hands over:
/// [PosterModel.title] is the movie/show name, the season name or the "S3xE12 Ep Name" episode
/// line, and for season and episode tiles [PosterModel.noPosterText] is the show title.
class WatchlistActionsWidget {
  final PosterModel details;

  WatchlistActionsWidget(this.details);

  void buildWidget(BuildContext mainContext) {
    showModalBottomSheet(
      context: mainContext,
      enableDrag: true,
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _WatchlistActionsSheet(mainContext, details),
    );
  }
}

class _WatchlistActionsSheet extends StatelessWidget {
  static final _log = Logger('WatchlistActionsWidget');

  /// The page's context, which outlives the sheet - the confirmation dialog and the failure
  /// snackbar must hang off it, never off the sheet's own context, which is popping.
  final BuildContext mainContext;

  final PosterModel details;

  const _WatchlistActionsSheet(this.mainContext, this.details);

  @override
  Widget build(BuildContext context) {
    // A season and an episode poster are titled within their show, so the show name goes above
    // them. A movie or a show poster is already titled with its own name.
    final showsParentTitle = details.type == ItemType.season || details.type == ItemType.episode;

    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showsParentTitle) ...[
            Container(
              margin: ScreenSizeUtil.fromLTRB(5, 0, 5, 0),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: details.noPosterText,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            margin: ScreenSizeUtil.fromLTRB(5, 0, 5, 0),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                text: details.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ConfirmationButtonWrapper.wrapButton(_RemoveFromWatchlistButton(onPressed: () => _remove(context))),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Pops the sheet, asks for confirmation on the page context, and only then removes.
  ///
  /// The messenger is captured before the pop so the failure snackbar survives the sheet's
  /// teardown. No success feedback and no manual reload: the repository delete notifies
  /// `DataChangeMonitor`, which refreshes the grid - and its pills - on its own.
  Future<void> _remove(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(mainContext);
    context.pop();

    final confirmed = await showDialog<bool>(
      context: mainContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from watchlist?'),
        content: Text('This removes $_itemDescription from your watchlist. You can add it again at any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Remove')),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _removeFromWatchlist();
    } catch (e, stackTrace) {
      _log.severe('Error removing ${details.key} from the watchlist', e, stackTrace);
      messenger.showSnackBar(const SnackBar(content: Text('Could not remove the item from your watchlist. Please try again.')));
    }
  }

  /// Every user-data row is keyed on the parent show's TMDB id plus season/episode numbers, which
  /// is exactly what the tile's key carries.
  Future<void> _removeFromWatchlist() async {
    final service = WatchlistService();
    final key = details.key;

    switch (key.type) {
      case ItemType.movie:
        await service.removeMovie(key.tmdbId);
      case ItemType.show:
        await service.removeShow(key.tmdbId);
      case ItemType.season:
        await service.removeSeason(key.tmdbId, key.season);
      case ItemType.episode:
        await service.removeEpisode(key.tmdbId, key.season, key.episode);
    }
  }

  /// The item named in the confirmation dialog, qualified by its show where the title alone would
  /// not say which one it belongs to.
  String get _itemDescription => switch (details.type) {
    ItemType.movie || ItemType.show => details.title,
    ItemType.season || ItemType.episode => '${details.title} (${details.noPosterText})',
  };
}

/// A destructive outlined button, styled after the watch history sheet's remove action.
class _RemoveFromWatchlistButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RemoveFromWatchlistButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colorScheme.error),
        foregroundColor: colorScheme.error,
      ),
      icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
      label: const Text('Remove from watchlist', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
