import 'package:flutter/material.dart';

/// Every Google Play product this app sells, in one place.
///
/// The ids are permanent — Play never lets a product id be reused once created — so they encode
/// *tier order* rather than a price. That way the €5 tier can become €6 without the id lying.
///
/// Play Console setup these ids expect:
///  * [oneTimeIds] are "in-app products" (managed products). Play has no consumable flag; they are
///    consumable purely because [DonationService] consumes them, which is what lets someone give
///    more than once.
///  * [monthlyIds] are three *separate* subscription products, each with exactly one auto-renewing
///    base plan `monthly` (P1M) and no offers. Three products rather than one product with three
///    base plans because `ProductDetails.id` — and `PurchaseDetails.productID` — is the product id:
///    base plans of a single product are indistinguishable in both the catalogue and the purchase
///    stream without a backend.
class DonationProducts {
  static const monthlySmall = 'coffee_monthly_tier1';
  static const monthlyMedium = 'coffee_monthly_tier2';
  static const monthlyLarge = 'coffee_monthly_tier3';

  static const onceSmall = 'coffee_once_tier1';
  static const onceLarge = 'coffee_once_tier2';

  /// Consumed after purchase, so they can be bought repeatedly.
  static const Set<String> oneTimeIds = {onceSmall, onceLarge};

  /// Acknowledged but never consumed.
  static const Set<String> monthlyIds = {monthlySmall, monthlyMedium, monthlyLarge};

  static const Set<String> allIds = {...oneTimeIds, ...monthlyIds};

  /// Our own label for each tier. Play's `ProductDetails.title` comes back with the app name
  /// appended in brackets ("Buy me a coffee (Ticket Box)"), so only its `price` is worth
  /// rendering — that one has to come from Play, since prices are per-country.
  static const Map<String, DonationTierCopy> copy = {
    monthlySmall: DonationTierCopy(label: 'An espresso', blurb: 'A small one, every month', icon: Icons.coffee_outlined),
    monthlyMedium: DonationTierCopy(label: 'A big coffee', blurb: 'The one that actually wakes me up', icon: Icons.coffee),
    monthlyLarge: DonationTierCopy(label: 'Coffee and a pastry', blurb: 'Now we are talking', icon: Icons.bakery_dining_outlined),
    onceSmall: DonationTierCopy(label: 'A round of coffees', blurb: 'A one-off thank you', icon: Icons.coffee),
    onceLarge: DonationTierCopy(label: 'A month of coffees', blurb: 'Very generous of you', icon: Icons.local_cafe),
  };

  const DonationProducts._();
}

/// The app-authored half of a tier — everything Play does not provide.
@immutable
class DonationTierCopy {
  final String label;
  final String blurb;
  final IconData icon;

  const DonationTierCopy({required this.label, required this.blurb, required this.icon});
}
