import 'package:flutter/material.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';

/// The Popular / Top rated / Trending choice inside the Discover page's filter panel.
///
/// Deliberately bloc agnostic: the panel wires it to the cubit, and the pick only takes effect
/// with the panel's Apply button like every other filter.
class DiscoverModeSelector extends StatelessWidget {
  final DiscoverMode selected;
  final ValueChanged<DiscoverMode> onChanged;

  const DiscoverModeSelector({required this.selected, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ScreenSizeUtil.fromLTRB(10, 0, 10, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 5,
        children: DiscoverMode.values
            .map((mode) => FilterButton(text: mode.prettyString(), selected: mode == selected, onPress: () => onChanged(mode)))
            .toList(),
      ),
    );
  }
}
