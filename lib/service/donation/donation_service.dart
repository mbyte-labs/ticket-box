import 'dart:async';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/donation/donation_event.dart';
import 'package:ticketbox/service/donation/donation_products.dart';

/// Google Play Billing, wrapped so the rest of the app never touches `in_app_purchase` directly.
///
/// Owns the app's **single** `purchaseStream` subscription for the whole process lifetime, which
/// the plugin requires and which two things here depend on:
///  * a subscription that is not acknowledged within 3 days is auto-refunded and cancelled by
///    Play, and a purchase can land long after the page that started it is gone (slow card, cash
///    payment, or the app being killed mid-flow);
///  * a one-time product that is not consumed can never be bought again.
///
/// Nothing is unlocked by donating, so purchases are deliberately **not** verified server-side —
/// `PurchaseDetails.verificationData` is ignored. There is nothing to gain from spoofing one.
/// Please do not "fix" this by adding a backend unless the app starts selling something real.
class DonationService {
  static final _log = Logger('[Service] DonationService');

  /// Every Play round-trip is capped. The plugin only completes its future when the Billing
  /// Library calls back, and on a real device that callback can simply never come (Play Store
  /// mid-update, a stalled binder connection). Without a cap the donate page would spin forever and
  /// log nothing. The cap does *not* cancel the underlying call — a late answer is dropped, and a
  /// retry just awaits the same connection again, which is what we want.
  static const availabilityTimeout = Duration(seconds: 10);
  static const productsTimeout = Duration(seconds: 20);

  final _controller = StreamController<DonationEvent>.broadcast();
  final Set<String> _activeSubscriptionIds = {};
  final Map<String, bool> _autoRenewing = {};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  /// Ids bought in this session, so a start-up restore of an old purchase does not fire a
  /// thank-you at someone who just opened the app.
  final Set<String> _boughtThisSession = {};

  DonationService._();

  static DonationService instance() {
    if (GetIt.I.isRegistered<DonationService>()) {
      return GetIt.I.get<DonationService>();
    }

    _log.info('New instance created');
    final service = DonationService._();
    GetIt.I.registerSingleton<DonationService>(service);
    return service;
  }

  /// False on Linux and Windows. `InAppPurchase.instance` only registers a platform on Android,
  /// iOS and macOS — everywhere else the platform instance is a `late` field that is never
  /// assigned, so the *first read* throws `LateInitializationError`. Every path into this class
  /// has to check this before touching the plugin.
  bool get isSupported => Platform.isAndroid;

  Stream<DonationEvent> get events => _controller.stream;

  /// Monthly tiers Play reports as currently active for the account on this device. Empty until
  /// [refreshSubscriptions] has run, and only ever as trustworthy as the device's Play account —
  /// good enough to render a badge, not something to gate behavior on.
  Set<String> get activeSubscriptionIds => Set.unmodifiable(_activeSubscriptionIds);

  /// False when [productId] is active but the user has already cancelled it, i.e. it runs to the
  /// end of the paid period and then stops.
  bool isAutoRenewing(String productId) => _autoRenewing[productId] ?? true;

  /// Attaches the purchase listener and asks Play for anything left unfinished. Must be called on
  /// the main isolate only. Never throws — a broken billing connection is not a reason to fail
  /// app start-up.
  Future<void> initialize() async {
    if (!isSupported) {
      _log.info('Billing not supported on this platform, skipping initialization');
      return;
    }
    if (_purchaseSubscription != null) {
      return;
    }

    try {
      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        (purchases) => unawaited(_onPurchaseUpdates(purchases)),
        onError: (Object e, StackTrace stackTrace) => _log.severe('Purchase stream error', e, stackTrace),
      );

      // Deliberately not awaited: this is a Play round-trip and start-up must not wait on it.
      // Results arrive on the stream we just subscribed to.
      unawaited(refreshSubscriptions());
    } catch (e, stackTrace) {
      _log.severe('Failed to initialize billing', e, stackTrace);
    }
  }

  /// Whether the Play Store is reachable and new enough to transact.
  ///
  /// Throws [DonationTimeout] when Play never answers, so the caller can offer a retry rather than
  /// declaring billing unavailable.
  Future<bool> checkAvailability() async {
    if (!isSupported) return false;

    final stopwatch = Stopwatch()..start();
    try {
      final available = await InAppPurchase.instance.isAvailable().timeout(availabilityTimeout);
      _log.info('Play Billing available=$available in ${stopwatch.elapsedMilliseconds}ms');
      return available;
    } on TimeoutException {
      _log.warning('Play Billing connection did not answer within ${availabilityTimeout.inSeconds}s');
      throw const DonationTimeout('isAvailable', availabilityTimeout);
    } catch (e, stackTrace) {
      _log.warning('Billing availability check failed after ${stopwatch.elapsedMilliseconds}ms', e, stackTrace);
      return false;
    }
  }

  /// The five tiers as Play knows them, or an empty list when Play knows none of them — which is
  /// the normal state until the Console products are active *and* a build containing them has
  /// been rolled out to a track.
  ///
  /// Throws [DonationTimeout] when Play never answers the query.
  Future<List<ProductDetails>> loadProducts() async {
    if (!isSupported) return const [];

    final stopwatch = Stopwatch()..start();
    try {
      final response = await InAppPurchase.instance.queryProductDetails(DonationProducts.allIds).timeout(productsTimeout);

      if (response.error != null) {
        _log.warning('Product query failed: ${response.error!.code} ${response.error!.message}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        _log.warning('Play does not know these product ids: ${response.notFoundIDs}');
      }
      _log.info(
        'Play returned ${response.productDetails.length} products in ${stopwatch.elapsedMilliseconds}ms: '
        '${response.productDetails.map((product) => product.id).toList()}',
      );

      return response.productDetails;
    } on TimeoutException {
      _log.warning('Play product query did not answer within ${productsTimeout.inSeconds}s');
      throw const DonationTimeout('queryProductDetails', productsTimeout);
    } catch (e, stackTrace) {
      _log.severe('Failed to query products after ${stopwatch.elapsedMilliseconds}ms', e, stackTrace);
      return const [];
    }
  }

  /// Re-reads the account's active subscriptions and sweeps up any purchase left unfinished by a
  /// previous session. Results arrive on [events] rather than being returned, because the plugin
  /// delivers them through the purchase stream.
  Future<void> refreshSubscriptions() async {
    if (!isSupported) return;

    try {
      await InAppPurchase.instance.restorePurchases().timeout(productsTimeout);
    } on TimeoutException {
      _log.warning('Play restorePurchases did not answer within ${productsTimeout.inSeconds}s');
    } catch (e, stackTrace) {
      // Not fatal, and not worth telling the user about — the page just goes without the
      // "you're already supporting" banner.
      _log.warning('Could not restore purchases', e, stackTrace);
    }
  }

  /// Buys a one-time tier. `autoConsume` is off on purpose — see [_deliver].
  Future<bool> buyOneTime(ProductDetails product) async {
    if (!isSupported) return false;

    _log.info('Starting one-time purchase of ${product.id}');
    try {
      return await InAppPurchase.instance.buyConsumable(
        purchaseParam: GooglePlayPurchaseParam(productDetails: product),
        autoConsume: false,
      );
    } catch (e, stackTrace) {
      _log.severe('Failed to launch purchase flow for ${product.id}', e, stackTrace);
      _controller.add(const DonationFailed('Google Play could not start the purchase. Please try again.'));
      return false;
    }
  }

  /// Buys a monthly tier. No `offerToken` is passed — the plugin reads it off the
  /// [GooglePlayProductDetails] when the param does not carry one, which is correct as long as
  /// each subscription product has exactly one base plan and no offers.
  Future<bool> buyMonthly(ProductDetails product) async {
    if (!isSupported) return false;

    _log.info('Starting subscription purchase of ${product.id}');
    try {
      return await InAppPurchase.instance.buyNonConsumable(purchaseParam: GooglePlayPurchaseParam(productDetails: product));
    } catch (e, stackTrace) {
      _log.severe('Failed to launch subscription flow for ${product.id}', e, stackTrace);
      _controller.add(const DonationFailed('Google Play could not start the purchase. Please try again.'));
      return false;
    }
  }

  /// Play's own subscription screen, deep-linked to [productId] when one is known. Play requires
  /// a link to this from anywhere that sells a subscription.
  String manageSubscriptionUrl({String? productId, required String packageName}) {
    const base = 'https://play.google.com/store/account/subscriptions';
    if (productId == null) return base;
    return '$base?sku=$productId&package=$packageName';
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      try {
        await _handle(purchase);
      } catch (e, stackTrace) {
        _log.severe('Failed to handle purchase update for ${purchase.productID}', e, stackTrace);
      }
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _log.info('Purchase pending: ${purchase.productID}');
        _controller.add(DonationPending(purchase.productID));
        // Completing a pending purchase throws. Play will send it again once it settles.
        return;

      case PurchaseStatus.canceled:
        _log.info('Purchase cancelled by the user');
        _controller.add(const DonationCancelled());

      case PurchaseStatus.error:
        _log.warning('Purchase failed: ${purchase.error?.code} ${purchase.error?.message} ${purchase.error?.details}');
        _controller.add(DonationFailed(_readableError(purchase.error)));

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final consumed = await _deliver(purchase);
        // Consuming a product acknowledges it too, so completing it again would be a wasted
        // round-trip against a token Play has already retired.
        if (consumed) return;
    }

    // A cancel or an error with no purchase attached comes back as a bare PurchaseDetails with an
    // empty productID and pendingCompletePurchase false, so it never reaches this.
    if (purchase.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(purchase);
    }
  }

  /// Returns true when the purchase was consumed, and therefore needs no acknowledgement.
  Future<bool> _deliver(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final isFresh = purchase.status == PurchaseStatus.purchased;

    if (DonationProducts.oneTimeIds.contains(productId)) {
      // Not `buyConsumable(autoConsume: true)`: the plugin tracks which ids to auto-consume in an
      // in-memory set that only a buy call in the *same session* fills. A purchase delivered at
      // start-up — because the app was killed mid-flow, or a slow payment settled while it was
      // closed — would silently never be consumed, permanently blocking that tier for that user.
      final addition = InAppPurchase.instance.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final result = await addition.consumePurchase(purchase);

      if (result.responseCode == BillingResponse.ok) {
        _log.info('Consumed one-time purchase $productId');
        if (isFresh || _boughtThisSession.contains(productId)) {
          _boughtThisSession.remove(productId);
          _controller.add(DonationThanks(productId));
        }
        return true;
      }

      // Fall through to acknowledgement: that at least stops Play auto-refunding it after 3 days.
      // The purchase stays unconsumed, so the next restore hands it back and we try again.
      _log.warning('Could not consume $productId: ${result.responseCode} ${result.debugMessage}');
      return false;
    }

    if (DonationProducts.monthlyIds.contains(productId)) {
      final wasActive = _activeSubscriptionIds.contains(productId);
      _activeSubscriptionIds.add(productId);

      if (purchase is GooglePlayPurchaseDetails) {
        _autoRenewing[productId] = purchase.billingClientPurchase.isAutoRenewing;
      }

      if (!wasActive || isFresh) {
        _controller.add(const DonationSubscriptionsChanged());
      }
      if (isFresh) {
        _log.info('Subscription started: $productId');
        _controller.add(DonationThanks(productId));
      }
      return false;
    }

    _log.warning('Ignoring a purchase for an unknown product id: $productId');
    return false;
  }

  /// Play's `IAPError.message` is the raw `BillingResponse` enum name — fine for the log, useless
  /// on screen.
  String _readableError(IAPError? error) {
    final raw = error?.message ?? '';
    if (raw.contains('itemAlreadyOwned')) {
      return 'You already have this. Thank you.';
    }
    if (raw.contains('serviceDisconnected') || raw.contains('serviceUnavailable') || raw.contains('networkError')) {
      return 'Google Play is unreachable right now. Please try again later.';
    }
    if (raw.contains('billingUnavailable') || raw.contains('featureNotSupported')) {
      return 'In-app purchases are not available on this device.';
    }
    return 'The purchase did not go through. Nothing has been charged.';
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    await _controller.close();
  }
}
