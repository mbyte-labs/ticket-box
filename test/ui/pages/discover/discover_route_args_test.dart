import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/ui/pages/discover/discover_route_args.dart';

void main() {
  test('no query means movies and no list override', () {
    final args = DiscoverRouteArgs.fromQuery(const {});

    expect(args.type, ItemType.movie);
    expect(args.mode, isNull);
  });

  test('type=shows opens the shows list, anything else the movies one', () {
    expect(DiscoverRouteArgs.fromQuery(const {'type': 'shows'}).type, ItemType.show);
    expect(DiscoverRouteArgs.fromQuery(const {'type': 'movies'}).type, ItemType.movie);
    expect(DiscoverRouteArgs.fromQuery(const {'type': 'books'}).type, ItemType.movie);
  });

  test('mode names a list by its enum name', () {
    for (final mode in DiscoverMode.values) {
      expect(DiscoverRouteArgs.fromQuery({'mode': mode.name}).mode, mode, reason: mode.name);
    }
  });

  test('an unknown mode leaves the persisted list alone', () {
    expect(DiscoverRouteArgs.fromQuery(const {'mode': 'hot'}).mode, isNull);
  });

  test('the trending shows link decodes as shows + trending', () {
    final args = DiscoverRouteArgs.fromQuery(const {'type': 'shows', 'mode': 'trending'});

    expect((args.type, args.mode), (ItemType.show, DiscoverMode.trending));
  });
}
