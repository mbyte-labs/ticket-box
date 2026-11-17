import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';

/// The Movies / Shows switch of the Discover page.
///
/// A tap applies immediately - the bloc keeps a loaded list per type, so there is nothing to
/// batch up behind an Apply button. Deliberately bloc agnostic.
class DiscoverTypeSelector extends StatelessWidget {
  final ItemType selected;
  final ValueChanged<ItemType> onChanged;

  const DiscoverTypeSelector({required this.selected, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ScreenSizeUtil.fromLTRB(10, 5, 10, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 5,
        children: [
          FilterButton(text: 'Movies', selected: selected == ItemType.movie, onPress: () => onChanged(ItemType.movie)),
          FilterButton(text: 'Shows', selected: selected == ItemType.show, onPress: () => onChanged(ItemType.show)),
        ],
      ),
    );
  }
}
