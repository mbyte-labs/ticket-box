/// What [DonationService] tells the UI about a purchase.
///
/// Hand-written rather than `@freezed` — these are throwaway notifications, never stored or
/// compared, so they do not need generated equality or a `build_runner` pass.
sealed class DonationEvent {
  const DonationEvent();
}

/// Google Play accepted the purchase but has not taken the money yet (slow card, cash payment,
/// parental approval). Can sit here for days and can resolve in a completely different session.
class DonationPending extends DonationEvent {
  final String productId;

  const DonationPending(this.productId);
}

/// A purchase completed *in this session* — the only event that should trigger a thank you.
/// Purchases restored at start-up deliberately do not produce one.
class DonationThanks extends DonationEvent {
  final String productId;

  const DonationThanks(this.productId);
}

/// The user backed out of the Play sheet. Not an error, and not worth a message.
class DonationCancelled extends DonationEvent {
  const DonationCancelled();
}

class DonationFailed extends DonationEvent {
  /// Already translated into something a person can read — never a raw `BillingResponse`.
  final String message;

  const DonationFailed(this.message);
}

/// The set of active monthly tiers changed (start-up restore, a new subscription, or a
/// cancellation noticed on the next restore).
class DonationSubscriptionsChanged extends DonationEvent {
  const DonationSubscriptionsChanged();
}

/// Thrown by [DonationService] when Google Play binds but never answers a call within the service's
/// timeout. Distinct from a plain failure because retrying can genuinely help — the Play Store being
/// mid-update, or a stalled billing connection, usually clears up on its own.
class DonationTimeout implements Exception {
  /// Which call stalled, for the log line.
  final String operation;
  final Duration timeout;

  const DonationTimeout(this.operation, this.timeout);

  @override
  String toString() => 'DonationTimeout: $operation did not answer within ${timeout.inSeconds}s';
}
