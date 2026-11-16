import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/library/favorite_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';

/// The favorites grid's long press sheet: removing one favorite. Every tile on that grid is a
/// movie or a show tile, and the tile's key carries which.
class FavoriteItemActionsWidget {
  final PosterModel details;

  FavoriteItemActionsWidget(this.details);

  void buildWidget(BuildContext mainContext) {
    showModalBottomSheet(
      context: mainContext,
      enableDrag: true,
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _FavoriteItemActionsSheet(mainContext, details),
    );
  }
}

class _FavoriteItemActionsSheet extends StatelessWidget {
  static final _log = Logger('FavoriteItemActionsWidget');

  /// The page's context, which outlives the sheet - the failure snackbar must hang off it, never
  /// off the sheet's own context, which is popping.
  final BuildContext mainContext;

  final PosterModel details;

  const _FavoriteItemActionsSheet(this.mainContext, this.details);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: ScreenSizeUtil.fromLTRB(5, 0, 5, 0),
            child: Text(
              details.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 20),
          ConfirmationButtonWrapper.wrapButton(
            OutlinedButton.icon(
              onPressed: () => _unfavorite(context),
              icon: const Icon(Icons.heart_broken_outlined, size: 18),
              label: const Text('Remove from favorites', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Pops the sheet and removes the favorite. No confirmation: it is harmless and reversible
  /// from the item's own page, matching the details menu toggle.
  ///
  /// No manual reload: the repository delete notifies `DataChangeMonitor`, which reloads the grid.
  Future<void> _unfavorite(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(mainContext);
    context.pop();

    try {
      await FavoriteService().unfavorite(details.type, details.key.tmdbId);
    } catch (e, stackTrace) {
      _log.severe('Error removing ${details.key} from the favorites', e, stackTrace);
      messenger.showSnackBar(const SnackBar(content: Text('Could not remove it from your favorites. Please try again.')));
    }
  }
}
