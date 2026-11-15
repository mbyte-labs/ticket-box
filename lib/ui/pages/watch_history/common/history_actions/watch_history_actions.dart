import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/title_builder.dart';
import 'package:ticketbox/ui/common/buton/button_wrapper.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_entry.dart';

/// The watch history grid's long press sheet: remove-from-history scopes for one poster.
///
/// Unlike the up next sheet there is no bloc behind it - every string the sheet and its
/// confirmation dialogs need is already on the [PosterModel] the grid hands over:
/// [PosterModel.title] is the movie title or the "S3xE12 Ep Name" episode line, and for episode
/// tiles [PosterModel.noPosterText] is the show title. Nothing to load means no loading state.
///
/// A grid tile is one play, so the first scope is that play alone; the rest are whole-item ones: a
/// movie poster also offers removing every watch of the movie, an episode poster every watch of the
/// episode, its season, or the whole show.
class WatchHistoryActionsWidget {
  final WatchHistoryEntry entry;

  WatchHistoryActionsWidget(this.entry);

  void buildWidget(BuildContext mainContext) {
    showModalBottomSheet(
      context: mainContext,
      enableDrag: true,
      isDismissible: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _WatchHistoryActionsSheet(mainContext, entry),
    );
  }
}

class _WatchHistoryActionsSheet extends StatelessWidget {
  static final _log = Logger('WatchHistoryActionsWidget');

  /// The page's context, which outlives the sheet - the confirmation dialog and the failure
  /// snackbar must hang off it, never off the sheet's own context, which is popping.
  final BuildContext mainContext;

  final WatchHistoryEntry entry;

  const _WatchHistoryActionsSheet(this.mainContext, this.entry);

  PosterModel get details => entry.model;

  @override
  Widget build(BuildContext context) {
    final isEpisode = details.type == ItemType.episode;

    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEpisode) ...[
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
          ConfirmationButtonWrapper.wrapButton(
            _RemoveFromHistoryButton(label: 'Remove this watch', onPressed: () => _removeThisWatch(context)),
          ),
          const SizedBox(height: 20),
          if (isEpisode) ...[
            ConfirmationButtonWrapper.wrapButton(
              _RemoveFromHistoryButton(label: 'Remove episode from history', onPressed: () => _removeEpisode(context)),
            ),
            const SizedBox(height: 20),
            ConfirmationButtonWrapper.wrapButton(
              _RemoveFromHistoryButton(label: 'Remove $_seasonLabel from history', onPressed: () => _removeSeason(context)),
            ),
            const SizedBox(height: 20),
            ConfirmationButtonWrapper.wrapButton(
              _RemoveFromHistoryButton(label: 'Remove show from history', onPressed: () => _removeShow(context)),
            ),
          ] else
            ConfirmationButtonWrapper.wrapButton(
              _RemoveFromHistoryButton(label: 'Remove movie from history', onPressed: () => _removeMovie(context)),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// "season 3", or "specials" for season 0 - lowercased for use mid-sentence.
  String get _seasonLabel => ConfirmationTitleBuilder.seasonTitle(details.key.season).toLowerCase();

  Future<void> _removeThisWatch(BuildContext context) async {
    final watchedAt = DateFormat.yMMMd().add_jm().format(entry.watchedAt.toLocal());
    final what = details.type == ItemType.episode ? '${details.title} (${details.noPosterText})' : details.title;
    await _confirmAndRemove(
      context,
      dialogTitle: 'Remove this watch?',
      dialogContent: 'This removes the watch of $what on $watchedAt from your history. Other watches stay. This cannot be undone.',
      remove: () => WatchHistoryWriteService().removeByHistoryId(entry.historyId),
      failureMessage: 'Could not remove the watch from your history. Please try again.',
    );
  }

  Future<void> _removeMovie(BuildContext context) async {
    await _confirmAndRemove(
      context,
      dialogTitle: 'Remove from history?',
      dialogContent: 'This removes every watch of ${details.title} from your history. This cannot be undone.',
      remove: () => WatchHistoryWriteService().removeMovie(details.key.tmdbId),
      failureMessage: 'Could not remove the movie from your history. Please try again.',
    );
  }

  Future<void> _removeEpisode(BuildContext context) async {
    await _confirmAndRemove(
      context,
      dialogTitle: 'Remove episode from history?',
      dialogContent:
          'This removes every watch of ${details.title} (${details.noPosterText}) from your history. '
          'This cannot be undone.',
      remove: () => WatchHistoryWriteService().removeEpisode(details.key.tmdbId, details.key.season, details.key.episode),
      failureMessage: 'Could not remove the episode from your history. Please try again.',
    );
  }

  Future<void> _removeSeason(BuildContext context) async {
    await _confirmAndRemove(
      context,
      dialogTitle: 'Remove season from history?',
      dialogContent:
          'This removes every watched episode of ${details.noPosterText} $_seasonLabel from your history. '
          'This cannot be undone.',
      remove: () => WatchHistoryWriteService().removeSeason(details.key.tmdbId, details.key.season),
      failureMessage: 'Could not remove the season from your history. Please try again.',
    );
  }

  Future<void> _removeShow(BuildContext context) async {
    await _confirmAndRemove(
      context,
      dialogTitle: 'Remove show from history?',
      dialogContent: 'This removes every watched episode of ${details.noPosterText} from your history. This cannot be undone.',
      remove: () => WatchHistoryWriteService().removeShow(details.key.tmdbId),
      failureMessage: 'Could not remove the show from your history. Please try again.',
    );
  }

  /// Pops the sheet, asks for confirmation on the page context, and only then removes.
  ///
  /// The messenger is captured before the pop so the failure snackbar survives the sheet's
  /// teardown. No success feedback and no manual reload: the repository delete notifies
  /// `DataChangeMonitor`, which refreshes the grid on its own.
  Future<void> _confirmAndRemove(
    BuildContext context, {
    required String dialogTitle,
    required String dialogContent,
    required Future<void> Function() remove,
    required String failureMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(mainContext);
    context.pop();

    final confirmed = await showDialog<bool>(
      context: mainContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogTitle),
        content: Text(dialogContent),
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
      await remove();
    } catch (e, stackTrace) {
      _log.severe('Error removing ${details.key} from history', e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

/// A destructive outlined button, styled after the overflow menu's error-colored ignore action.
class _RemoveFromHistoryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _RemoveFromHistoryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colorScheme.error),
        foregroundColor: colorScheme.error,
      ),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
