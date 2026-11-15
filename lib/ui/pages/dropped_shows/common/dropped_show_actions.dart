import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/library/dropped_shows_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';

/// The dropped shows grid's long press sheet: un-dropping one show, so it is back in Up Next and
/// Show Progress. Every tile on that grid is a show tile.
class DroppedShowActionsWidget {
  final PosterModel details;

  DroppedShowActionsWidget(this.details);

  void buildWidget(BuildContext mainContext) {
    showModalBottomSheet(
      context: mainContext,
      enableDrag: true,
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _DroppedShowActionsSheet(mainContext, details),
    );
  }
}

class _DroppedShowActionsSheet extends StatelessWidget {
  static final _log = Logger('DroppedShowActionsWidget');

  /// The page's context, which outlives the sheet - the confirmation dialog and the failure
  /// snackbar must hang off it, never off the sheet's own context, which is popping.
  final BuildContext mainContext;

  final PosterModel details;

  const _DroppedShowActionsSheet(this.mainContext, this.details);

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
              onPressed: () => _undrop(context),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Un-drop show', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Pops the sheet, asks for confirmation on the page context, and only then un-drops.
  ///
  /// No manual reload: the state write notifies `DataChangeMonitor`, which reloads the grid - and
  /// its pills - on its own.
  Future<void> _undrop(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(mainContext);
    context.pop();

    final confirmed = await showDialog<bool>(
      context: mainContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Un-drop show?'),
        content: Text('${details.title} will show up in Up Next and Show Progress again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Un-drop')),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await DroppedShowsService().undrop(details.key.tmdbId);
    } catch (e, stackTrace) {
      _log.severe('Error un-dropping show ${details.key.tmdbId}', e, stackTrace);
      messenger.showSnackBar(const SnackBar(content: Text('Could not un-drop the show. Please try again.')));
    }
  }
}
