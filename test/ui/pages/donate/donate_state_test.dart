import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/ui/pages/donate/donate_state.dart';

void main() {
  group('DonateState', () {
    test('starts loading with neither unavailable nor timed out', () {
      final state = DonateState.initial();

      expect(state.loading, isTrue);
      expect(state.storeUnavailable, isFalse);
      expect(state.storeTimedOut, isFalse);
      expect(state.productsMissing, isFalse);
    });

    test('productsMissing only when Play answered with nothing', () {
      final settled = DonateState.initial().copyWith(loading: false);

      expect(settled.productsMissing, isTrue);
      expect(settled.copyWith(storeUnavailable: true).productsMissing, isFalse);
      expect(settled.copyWith(storeTimedOut: true).productsMissing, isFalse);
    });
  });
}
