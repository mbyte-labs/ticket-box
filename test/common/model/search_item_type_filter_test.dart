import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/search_item_type_filter.dart';

void main() {
  test('prettyString labels every filter', () {
    expect(SearchItemTypeFilter.both.prettyString(), 'Everything');
    expect(SearchItemTypeFilter.movies.prettyString(), 'Movies');
    expect(SearchItemTypeFilter.shows.prettyString(), 'Shows');
  });

  test('every value has a label, so a new filter cannot ship without one', () {
    for (final filter in SearchItemTypeFilter.values) {
      expect(filter.prettyString(), isNotEmpty, reason: filter.name);
    }
  });
}
