import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/item_type.dart';

/// What the `/discover` route's query string asks the page to open on.
///
/// `type=shows` opens the shows list, anything else the movies one. `mode` names a [DiscoverMode]
/// and, when present, overrides the persisted list for this visit only; an absent or unknown name
/// leaves the persisted choice alone.
class DiscoverRouteArgs {
  final ItemType type;
  final DiscoverMode? mode;

  const DiscoverRouteArgs({this.type = ItemType.movie, this.mode});

  static DiscoverRouteArgs fromQuery(Map<String, String> query) {
    return DiscoverRouteArgs(
      type: query['type'] == 'shows' ? ItemType.show : ItemType.movie,
      mode: DiscoverMode.values.asNameMap()[query['mode']],
    );
  }
}
