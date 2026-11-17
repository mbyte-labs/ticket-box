import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/heart_rating_img.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// What the user decided in the rate sheet. A dismissed sheet yields null instead.
sealed class RateSheetResult {
  const RateSheetResult();
}

/// The user confirmed a 1-10 [rating] with the Rate button.
final class RateSheetRated extends RateSheetResult {
  final int rating;

  const RateSheetRated(this.rating);
}

/// The user asked to remove the existing rating.
final class RateSheetRemoved extends RateSheetResult {
  const RateSheetRemoved();
}

/// Opens the bottom sheet the details pages rate from: 10 hearts pre-filled with
/// [currentRating], a Rate button that confirms the selection, and — when [canRemove] — a
/// Remove rating link. Picking a heart only changes the sheet's own selection; nothing is
/// returned until a button is pressed, and dismissing the sheet returns null.
Future<RateSheetResult?> showRateSheet(BuildContext context, {required int? currentRating, required bool canRemove}) {
  return showModalBottomSheet<RateSheetResult>(
    context: context,
    builder: (_) => _RateSheet(currentRating: currentRating, canRemove: canRemove),
  );
}

class _RateSheet extends StatefulWidget {
  final int? currentRating;
  final bool canRemove;

  const _RateSheet({required this.currentRating, required this.canRemove});

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late int _selected = widget.currentRating ?? 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canConfirm = _selected >= 1 && _selected != widget.currentRating;

    return SafeArea(
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(15, 20, 15, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your rating', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            SizedBox(height: ScreenSizeUtil.calculateSize(6)),
            Text(
              _selected >= 1 ? '$_selected/10' : 'Tap a heart',
              style: _selected >= 1
                  ? const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)
                  : TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(14)),
            FittedBox(
              child: RatingBar(
                initialRating: _selected.toDouble(),
                minRating: 1,
                allowHalfRating: false,
                itemCount: 10,
                itemSize: ScreenSizeUtil.calculateSize(30),
                itemPadding: EdgeInsets.symmetric(horizontal: ScreenSizeUtil.calculateSize(4)),
                glowColor: ThemeColors.primary,
                ratingWidget: RatingWidget(
                  full: HeartWidgetUtil.fullImage(ThemeColors.primary, 30, 30),
                  half: HeartWidgetUtil.halfImage(ThemeColors.primary, 30, 30),
                  empty: HeartWidgetUtil.emptyImage(ThemeColors.primary.withValues(alpha: 0.45), 30, 30),
                ),
                onRatingUpdate: (value) => setState(() => _selected = value.round()),
              ),
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(22)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canConfirm ? () => Navigator.of(context).pop<RateSheetResult>(RateSheetRated(_selected)) : null,
                child: const Text('Rate'),
              ),
            ),
            if (widget.canRemove) ...[
              SizedBox(height: ScreenSizeUtil.calculateSize(4)),
              TextButton(
                onPressed: () => Navigator.of(context).pop<RateSheetResult>(const RateSheetRemoved()),
                child: const Text('Remove rating'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
