import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';

enum _OverflowAction { favorite, ignore }

/// The details pages' app bar overflow menu.
///
/// Holds two optional toggles, each present only when its callback is given:
///
/// - **Favorite** — adds the movie or show to the user's favorites. Offered by the movie and
///   show pages only; harmless and reversible, so it never prompts.
/// - **Ignore** — drops the show. Ignoring is destructive and always show-wide (a show is dropped as
///   a whole, never per season or episode), so it is kept one level down from the action bar while
///   still being reachable at any scroll position, the app bar being pinned. Offered by the show,
///   season and episode pages; a movie cannot be dropped.
class DetailsOverflowMenu extends StatelessWidget {
  /// Show title, named in the ignore confirmation dialog so the show-wide scope is unambiguous.
  final String? showTitle;

  /// Whether the show is currently ignored, which flips the item into an un-ignore action. `null`
  /// (with [onIgnoredChanged] `null` too) leaves the ignore item out.
  final bool? ignored;
  final ValueChanged<bool>? onIgnoredChanged;

  /// Whether the item is currently a favorite, which flips the item into a remove action. `null`
  /// (with [onFavoriteChanged] `null` too) leaves the favorite item out.
  final bool? favorite;
  final ValueChanged<bool>? onFavoriteChanged;

  final DetailsPendingAction? pendingAction;

  const DetailsOverflowMenu({
    required this.pendingAction,
    this.showTitle,
    this.ignored,
    this.onIgnoredChanged,
    this.favorite,
    this.onFavoriteChanged,
    super.key,
  }) : assert((ignored == null) == (onIgnoredChanged == null), 'ignored and onIgnoredChanged go together'),
       assert((favorite == null) == (onFavoriteChanged == null), 'favorite and onFavoriteChanged go together'),
       assert(ignored != null || favorite != null, 'The menu needs at least one item');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (pendingAction == DetailsPendingAction.ignore || pendingAction == DetailsPendingAction.favorite) {
      return Center(
        child: Padding(
          padding: ScreenSizeUtil.fromLTRB(16, 0, 16, 0),
          child: SizedBox(
            width: ScreenSizeUtil.calculateSize(20),
            height: ScreenSizeUtil.calculateSize(20),
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final ignored = this.ignored;
    final favorite = this.favorite;
    final destructive = ignored == false;

    return PopupMenuButton<_OverflowAction>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert),
      enabled: pendingAction == null,
      // Fires after the menu route has popped, so a dialog can safely be opened from here.
      onSelected: (action) => _handle(context, action),
      itemBuilder: (menuContext) => [
        if (favorite != null)
          PopupMenuItem<_OverflowAction>(
            value: _OverflowAction.favorite,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(favorite ? Icons.favorite : Icons.favorite_border, color: colorScheme.onSurface),
              title: Text(favorite ? 'Remove from favorites' : 'Add to favorites', style: TextStyle(color: colorScheme.onSurface)),
            ),
          ),
        if (ignored != null)
          PopupMenuItem<_OverflowAction>(
            value: _OverflowAction.ignore,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                ignored ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: destructive ? colorScheme.error : colorScheme.onSurface,
              ),
              title: Text(
                ignored ? 'Stop ignoring show' : 'Ignore show',
                style: TextStyle(color: destructive ? colorScheme.error : colorScheme.onSurface),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, _OverflowAction action) async {
    switch (action) {
      case _OverflowAction.favorite:
        // Favoriting is harmless and reversible either way, so it never prompts.
        onFavoriteChanged!(!favorite!);
      case _OverflowAction.ignore:
        await _handleIgnore(context, shouldIgnore: !ignored!);
    }
  }

  Future<void> _handleIgnore(BuildContext context, {required bool shouldIgnore}) async {
    // Un-ignoring is harmless and reversible, so it goes through without a prompt.
    if (!shouldIgnore) {
      onIgnoredChanged!(false);
      return;
    }

    final confirmed = await _confirmIgnore(context);
    if (confirmed) {
      onIgnoredChanged!(true);
    }
  }

  Future<bool> _confirmIgnore(BuildContext context) async {
    final title = showTitle ?? 'this show';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Ignore $title?'),
        content: const Text('Dropped shows are hidden from Up next and Show progress. This affects the whole show, not just this item.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Ignore')),
        ],
      ),
    );

    return confirmed == true;
  }
}
