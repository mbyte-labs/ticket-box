import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

part 'donate_state.freezed.dart';

@freezed
abstract class DonateState with _$DonateState {
  const factory DonateState({
    /// True until the availability check and the product query have both settled.
    required bool loading,

    /// Google Play cannot be reached — no Play Services, a Play Store too old to transact, or a
    /// desktop build. The page falls back to the intro text alone.
    required bool storeUnavailable,

    /// Google Play bound but never answered within [DonationService]'s timeout. Distinct from
    /// [storeUnavailable] because this one is worth a retry — a Play Store mid-update or a stalled
    /// billing connection usually clears up on its own.
    required bool storeTimedOut,

    /// Monthly tiers, cheapest first. Empty while loading, and also when Play knows none of the
    /// product ids — which is the normal state until they go live in the Console.
    required List<DonateTier> monthlyTiers,

    /// One-time tiers, cheapest first.
    required List<DonateTier> oneTimeTiers,

    /// Product whose Play sheet is open, or whose purchase is being finalised. Disables every
    /// tile and drives the spinner on this one. Null when idle.
    required String? purchaseInFlightId,

    /// Product Play reported as `pending` — a slow card, a cash payment or an approval request.
    /// Can stay set for days and can resolve in a later session.
    required String? pendingProductId,

    /// The active monthly tier, or null when there is none. Read back from Play rather than
    /// stored, so it survives a reinstall and reflects a cancellation made on another device.
    required String? activeSubscriptionId,

    /// False when [activeSubscriptionId] is set but auto-renew is already off, i.e. cancelled and
    /// running out the paid period.
    required bool activeSubscriptionRenewing,

    /// Set after a purchase completes so the page can swap in the thank-you card. Cleared when
    /// the user dismisses it.
    required bool showThankYou,

    /// One user-facing line about a failure, or null when there is nothing to say. A cancelled
    /// purchase is not a failure and never lands here.
    required String? errorMessage,
  }) = _DonateState;

  factory DonateState.initial() {
    return const DonateState(
      loading: true,
      storeUnavailable: false,
      storeTimedOut: false,
      monthlyTiers: [],
      oneTimeTiers: [],
      purchaseInFlightId: null,
      pendingProductId: null,
      activeSubscriptionId: null,
      activeSubscriptionRenewing: true,
      showThankYou: false,
      errorMessage: null,
    );
  }
}

extension DonateStateLookups on DonateState {
  /// True while a purchase is in flight, so every tile has to stop accepting taps.
  bool get busy => purchaseInFlightId != null;

  bool get hasActiveSubscription => activeSubscriptionId != null;

  /// Play is reachable but knows none of our products — they are not live yet, or this build is
  /// not on a track. Distinct from [storeUnavailable] because there is nothing the user can do.
  bool get productsMissing => !loading && !storeUnavailable && !storeTimedOut && monthlyTiers.isEmpty && oneTimeTiers.isEmpty;

  /// The active tier's price, for the "you're supporting at X/month" line.
  String? get activeSubscriptionPrice {
    final id = activeSubscriptionId;
    if (id == null) return null;
    for (final tier in monthlyTiers) {
      if (tier.productId == id) return tier.price;
    }
    return null;
  }
}

/// One purchasable tier: our own copy, plus the price exactly as Play formatted it for this
/// storefront. The price is never hardcoded — Play sets it per country, so a €1 base price is
/// only literally €1 in the eurozone.
@freezed
abstract class DonateTier with _$DonateTier {
  const factory DonateTier({
    required String productId,
    required String label,
    required String blurb,
    required String price,
    required ProductDetails product,
  }) = _DonateTier;
}
