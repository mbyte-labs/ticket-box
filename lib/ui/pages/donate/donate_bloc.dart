import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/app_details.dart';
import 'package:ticketbox/service/donation/donation_event.dart';
import 'package:ticketbox/service/donation/donation_products.dart';
import 'package:ticketbox/service/donation/donation_service.dart';
import 'package:ticketbox/ui/pages/donate/donate_state.dart';

class DonateBloc extends Cubit<DonateState> {
  static final _log = Logger('DonateBloc');

  final DonationService _service;
  StreamSubscription<DonationEvent>? _eventSubscription;

  DonateBloc({DonationService? service}) : _service = service ?? DonationService.instance(), super(DonateState.initial());

  @override
  Future<void> close() async {
    await _eventSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    if (!_service.isSupported) {
      emit(state.copyWith(loading: false, storeUnavailable: true));
      return;
    }

    _eventSubscription ??= _service.events.listen(_onEvent);
    await _load();
  }

  /// Runs the availability check and the product query again after a [DonationTimeout].
  Future<void> retry() async {
    if (isClosed || state.loading) return;

    _log.info('Retrying Play Billing after a timeout');
    emit(state.copyWith(loading: true, storeTimedOut: false, storeUnavailable: false));
    await _load();
  }

  /// Every step is logged at INFO with its timing, so the exported log file says exactly which Play
  /// round-trip stalled when the page sits on its spinner.
  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    try {
      _log.info('Checking Play Billing availability');
      final available = await _service.checkAvailability();
      if (isClosed) return;
      if (!available) {
        _log.info('Play Billing is unavailable on this device');
        emit(state.copyWith(loading: false, storeUnavailable: true));
        return;
      }

      _log.info('Querying Play products');
      final products = await _service.loadProducts();
      if (isClosed) return;

      final monthly = _toTiers(products, DonationProducts.monthlyIds);
      final oneTime = _toTiers(products, DonationProducts.oneTimeIds);
      _log.info('Donate page ready in ${stopwatch.elapsedMilliseconds}ms: ${monthly.length} monthly, ${oneTime.length} one-time');
      emit(state.copyWith(loading: false, monthlyTiers: monthly, oneTimeTiers: oneTime));
    } on DonationTimeout catch (e) {
      if (isClosed) return;
      _log.warning('Donate page gave up after ${stopwatch.elapsedMilliseconds}ms: $e');
      emit(state.copyWith(loading: false, storeTimedOut: true));
      return;
    }

    _syncSubscriptionState();

    // Results land on the event stream, so there is nothing to await on here.
    unawaited(_service.refreshSubscriptions());
  }

  Future<void> buy(DonateTier tier, {required bool monthly}) async {
    if (state.busy) return;
    emit(state.copyWith(purchaseInFlightId: tier.productId, errorMessage: null));

    final launched = monthly ? await _service.buyMonthly(tier.product) : await _service.buyOneTime(tier.product);
    if (isClosed) return;

    // `launched` only says the Play sheet opened — the outcome arrives on the event stream. But
    // if it never opened, nothing else will ever clear the in-flight state.
    if (!launched) {
      emit(state.copyWith(purchaseInFlightId: null));
    }
  }

  void dismissThankYou() {
    if (isClosed) return;
    emit(state.copyWith(showThankYou: false));
  }

  void dismissError() {
    if (isClosed) return;
    emit(state.copyWith(errorMessage: null));
  }

  /// Play's subscription screen, deep-linked to the active tier when there is one.
  String get manageSubscriptionUrl {
    final packageName = GetIt.I.isRegistered<AppDetails>() ? GetIt.I.get<AppDetails>().packageName : 'ro.madcodestudios.ticket.box';
    return _service.manageSubscriptionUrl(productId: state.activeSubscriptionId, packageName: packageName);
  }

  void _onEvent(DonationEvent event) {
    if (isClosed) return;

    switch (event) {
      case DonationPending(:final productId):
        emit(state.copyWith(purchaseInFlightId: null, pendingProductId: productId));

      case DonationThanks():
        emit(state.copyWith(purchaseInFlightId: null, pendingProductId: null, showThankYou: true, errorMessage: null));
        _syncSubscriptionState();

      case DonationCancelled():
        // Backing out of the Play sheet is not a failure and gets no message — being nagged
        // about a deliberate choice is hostile.
        emit(state.copyWith(purchaseInFlightId: null));

      case DonationFailed(:final message):
        emit(state.copyWith(purchaseInFlightId: null, pendingProductId: null, errorMessage: message));

      case DonationSubscriptionsChanged():
        _syncSubscriptionState();
    }
  }

  void _syncSubscriptionState() {
    if (isClosed) return;

    final active = _service.activeSubscriptionIds;
    if (active.isEmpty) {
      emit(state.copyWith(activeSubscriptionId: null, activeSubscriptionRenewing: true));
      return;
    }

    // Play would let someone hold more than one of the three, since they are separate products.
    // Show the dearest — it is the one they most likely meant to be on.
    final ordered = DonationProducts.monthlyIds.where(active.contains).toList();
    final id = ordered.last;
    emit(state.copyWith(activeSubscriptionId: id, activeSubscriptionRenewing: _service.isAutoRenewing(id)));
  }

  /// Keeps only the products we asked for, in the order [DonationProducts] declares them, which is
  /// cheapest first.
  List<DonateTier> _toTiers(List<ProductDetails> products, Set<String> ids) {
    final byId = {for (final product in products) product.id: product};

    return ids.where(byId.containsKey).map((id) {
      final copy = DonationProducts.copy[id]!;
      return DonateTier(productId: id, label: copy.label, blurb: copy.blurb, price: byId[id]!.price, product: byId[id]!);
    }).toList();
  }
}
