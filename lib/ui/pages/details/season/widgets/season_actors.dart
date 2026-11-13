import 'package:flutter/material.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/details_actor_card.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Cast section: Regulars / Guests choice chips + horizontal actor card list.
///
/// Always shown — when there is no cast data the chips render above a
/// placeholder message. Chip switching is local UI state; tapping a card
/// opens that person's details page.
class SeasonActors extends StatefulWidget {
  final List<CastMember> regulars;
  final List<CastMember> guests;

  /// The show the cast belongs to — its artwork directory holds the headshots.
  final MediaKey itemKey;

  const SeasonActors({required this.regulars, required this.guests, required this.itemKey, super.key});

  @override
  State<SeasonActors> createState() => _SeasonActorsState();
}

class _SeasonActorsState extends State<SeasonActors> {
  bool _seriesRegularsSelected = true;

  @override
  Widget build(BuildContext context) {
    final actors = _seriesRegularsSelected ? widget.regulars : widget.guests;
    final noCastAtAll = widget.regulars.isEmpty && widget.guests.isEmpty;

    return DetailsSection(
      title: 'Cast',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CastTypeToggle(
                label: 'Season regulars',
                count: widget.regulars.length,
                selected: _seriesRegularsSelected,
                onTap: () => setState(() => _seriesRegularsSelected = true),
              ),
              SizedBox(width: ScreenSizeUtil.calculateSize(14)),
              _CastTypeToggle(
                label: 'Guest Stars',
                count: widget.guests.length,
                selected: !_seriesRegularsSelected,
                onTap: () => setState(() => _seriesRegularsSelected = false),
              ),
            ],
          ),
          SizedBox(height: ScreenSizeUtil.calculateSize(10)),
          SizedBox(
            height: ScreenSizeUtil.calculateSize(actors.isEmpty ? 60 : 190),
            width: double.infinity,
            child: actors.isEmpty
                ? Center(
                    child: Text(
                      noCastAtAll
                          ? 'No actor information available for this season'
                          : (_seriesRegularsSelected ? 'No season regulars listed' : 'No guest stars listed'),
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: actors.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: ScreenSizeUtil.fromLTRB(0, 0, 8, 0),
                        width: ScreenSizeUtil.calculateSize(100),
                        child: DetailsActorCard(actor: actors[index], itemKey: widget.itemKey),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Discrete cast-type switcher: label + rounded-square count badge. The
/// selected entry is tinted in the brand red with a filled badge; the
/// unselected one stays neutral with an outlined badge.
class _CastTypeToggle extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CastTypeToggle({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeRadius = BorderRadius.circular(6);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(2, 4, 2, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? ThemeColors.primary : colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: ScreenSizeUtil.calculateSize(6)),
            Container(
              padding: ScreenSizeUtil.fromLTRB(6, 2, 6, 2),
              decoration: BoxDecoration(
                color: selected ? ThemeColors.primary : null,
                border: selected ? null : Border.all(color: colorScheme.outline),
                borderRadius: badgeRadius,
              ),
              child: Text(
                count.toString(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
