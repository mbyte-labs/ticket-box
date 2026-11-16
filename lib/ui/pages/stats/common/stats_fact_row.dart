import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// One label/value line inside a stats card: muted label on the left, emphasized value on the
/// right.
class StatsFactRow extends StatelessWidget {
  final String label;
  final String value;

  const StatsFactRow({required this.label, required this.value, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(0, 4, 0, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodyMedium?.copyWith(color: ThemeColors.greyScale500)),
          Text(value, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
