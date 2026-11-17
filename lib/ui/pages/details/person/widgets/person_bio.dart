import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/person/person_text_format.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// "Details" section: the facts TMDB has about the person — birth (with the birthplace as a
/// note), death and the first few other names they are known under. Each row hides itself when
/// its value is missing, and the section disappears when none is left.
class PersonFacts extends StatelessWidget {
  final String? birthday;
  final String? death;
  final String? birthplace;
  final List<String> alsoKnownAs;

  /// How many aliases are shown: enough to recognise a transliteration, not the whole list TMDB
  /// keeps for an internationally credited actor.
  static const _aliasLimit = 4;

  const PersonFacts({required this.birthday, required this.death, required this.birthplace, required this.alsoKnownAs, super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    final born = PersonTextFormat.formatDate(birthday);
    if (born != null) {
      rows.add(_FactRow(label: 'Born', value: born, note: birthplace));
    }

    final died = PersonTextFormat.formatDate(death);
    if (died != null) {
      rows.add(_FactRow(label: 'Died', value: died));
    }

    if (alsoKnownAs.isNotEmpty) {
      rows.add(_FactRow(label: 'Also known as', value: alsoKnownAs.take(_aliasLimit).join(', ')));
    }

    if (rows.isEmpty) {
      return const SizedBox();
    }

    return DetailsSection(
      title: 'Details',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: ScreenSizeUtil.calculateSize(10)), rows[i]],
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final String? note;

  const _FactRow({required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final note = this.note;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        SizedBox(height: ScreenSizeUtil.calculateSize(2)),
        Text(value, style: TextStyle(fontSize: 14, color: colorScheme.onSurface.withValues(alpha: 0.92))),
        if (note != null && note.trim().isNotEmpty) Text(note, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Biography section. Always shown: when TMDB has none, it says so, so an empty card reads as
/// "nothing known" rather than "still loading".
///
/// Long biographies collapse to [_collapsedMaxLines] lines behind a Read more toggle, so the
/// sections below stay within reach. The toggle only renders when the text actually overflows
/// the clamp (measured, never guessed from the character count); the expanded text keeps its
/// paragraph breaks and stays selectable, like the overview sections on the other details pages.
class PersonBio extends StatefulWidget {
  final String? biography;

  const PersonBio({required this.biography, super.key});

  @override
  State<PersonBio> createState() => _PersonBioState();
}

class _PersonBioState extends State<PersonBio> {
  static const _collapsedMaxLines = 6;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = widget.biography;

    if (text == null || text.isEmpty) {
      return DetailsSection(
        title: 'Biography',
        child: DetailsCard(
          child: Text('TMDB has no biography for this person.', style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
        ),
      );
    }

    final style = TextStyle(fontSize: 14, height: 1.45, color: colorScheme.onSurface.withValues(alpha: 0.92));

    return DetailsSection(
      title: 'Biography',
      child: DetailsCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Measured against the card's inner width so the clamp decision matches what the
            // Text below will actually lay out.
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              maxLines: _collapsedMaxLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final overflows = painter.didExceedMaxLines;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_expanded || !overflows)
                  SelectableText(text, style: style)
                else
                  Text(text, style: style, maxLines: _collapsedMaxLines, overflow: TextOverflow.ellipsis),
                if (overflows) ...[
                  SizedBox(height: ScreenSizeUtil.calculateSize(8)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: ScreenSizeUtil.fromLTRB(6, 2, 6, 2),
                        child: Text(
                          _expanded ? 'Show less' : 'Read more',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeColors.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
