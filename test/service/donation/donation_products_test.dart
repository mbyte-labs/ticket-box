import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/service/donation/donation_products.dart';

/// The product ids are the contract with Google Play Console — a typo here is invisible until a
/// real device asks Play for a product that does not exist, so it is worth pinning down.
void main() {
  group('DonationProducts', () {
    test('one-time and monthly ids do not overlap', () {
      // The two sets drive completely different handling — consume versus acknowledge — so an id
      // in both would be consumed *and* treated as an active subscription.
      expect(DonationProducts.oneTimeIds.intersection(DonationProducts.monthlyIds), isEmpty);
    });

    test('allIds is exactly the five tiers', () {
      expect(DonationProducts.allIds.length, 5);
      expect(DonationProducts.allIds, containsAll(DonationProducts.oneTimeIds));
      expect(DonationProducts.allIds, containsAll(DonationProducts.monthlyIds));
    });

    test('every id has display copy', () {
      // DonateBloc looks this up with a bang, so a missing entry would throw while building tiers.
      for (final id in DonationProducts.allIds) {
        expect(DonationProducts.copy[id], isNotNull, reason: 'no copy for $id');
      }
    });

    test('ids are valid Play product ids', () {
      // Play accepts lowercase letters, digits, underscores and periods, starting with a letter
      // or a digit.
      final valid = RegExp(r'^[a-z0-9][a-z0-9_.]*$');
      for (final id in DonationProducts.allIds) {
        expect(valid.hasMatch(id), isTrue, reason: '$id is not a valid Play product id');
        expect(id.length, lessThanOrEqualTo(40), reason: '$id is too long for Play');
      }
    });

    test('monthly ids are declared cheapest first', () {
      // DonateBloc renders tiers in this declaration order rather than sorting by price, so the
      // order here is what the user sees.
      expect(DonationProducts.monthlyIds.toList(), [
        DonationProducts.monthlySmall,
        DonationProducts.monthlyMedium,
        DonationProducts.monthlyLarge,
      ]);
      expect(DonationProducts.oneTimeIds.toList(), [DonationProducts.onceSmall, DonationProducts.onceLarge]);
    });
  });
}
