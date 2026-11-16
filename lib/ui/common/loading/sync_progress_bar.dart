import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// A progress bar that fills when the work is countable and animates indefinitely when it is not.
///
/// Follows the rounded determinate style already used by the check-in banner and the details action
/// bar, both of which had it inlined as a private widget.
class SyncProgressBar extends StatelessWidget {
  const SyncProgressBar({this.value, super.key});

  /// Completion in the 0..1 range, or null for indeterminate.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ScreenSizeUtil.calculateSize(4)),
      child: LinearProgressIndicator(
        value: value,
        minHeight: ScreenSizeUtil.calculateSize(6),
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }
}
