import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';

/// Episode synopsis rendered as a titled section card. Hidden when there is
/// no overview text. The text stays selectable.
class EpisodeOverview extends StatelessWidget {
  final String? overview;

  const EpisodeOverview(this.overview, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = overview;
    if (text == null || text.isEmpty) {
      return const SizedBox();
    }

    return DetailsSection(
      title: 'Overview',
      child: DetailsCard(
        child: SelectableText(
          text,
          style: TextStyle(fontSize: 14, height: 1.45, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92)),
        ),
      ),
    );
  }
}
