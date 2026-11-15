import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/discover_mode.dart';

void main() {
  test('prettyString labels every list', () {
    expect(DiscoverMode.popular.prettyString(), 'Popular');
    expect(DiscoverMode.topRated.prettyString(), 'Top rated');
    expect(DiscoverMode.trending.prettyString(), 'Trending');
  });

  test('every value has a label, so a new list cannot ship without one', () {
    for (final mode in DiscoverMode.values) {
      expect(mode.prettyString(), isNotEmpty, reason: mode.name);
    }
  });

  test('the persisted names are stable', () {
    // The name is stored inside the discover filter JSON; renaming a case needs a migration.
    expect(DiscoverMode.values.map((mode) => mode.name), ['popular', 'topRated', 'trending']);
  });
}
