import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/service/donation/donation_products.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/link_opener.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/donate/donate_bloc.dart';
import 'package:ticketbox/ui/pages/donate/donate_state.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

class DonateMobilePage extends StatefulWidget {
  const DonateMobilePage({super.key});

  @override
  State<DonateMobilePage> createState() => _DonateMobilePageState();
}

class _DonateMobilePageState extends State<DonateMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DonateBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy me a coffee')),
      // Top inset comes from the AppBar, which now extends behind the status bar.
      body: SafeArea(
        top: false,
        child: BlocConsumer<DonateBloc, DonateState>(
          listenWhen: (previous, current) => previous.errorMessage != current.errorMessage && current.errorMessage != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<DonateBloc>().dismissError();
          },
          builder: (context, state) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Hero(),
                  const _IntroSection(),
                  if (state.showThankYou) const _ThankYouSection(),
                  if (state.pendingProductId != null) const _PendingSection(),
                  if (state.hasActiveSubscription) const _ActiveSubscriptionSection(),
                  if (state.loading)
                    Padding(
                      padding: ScreenSizeUtil.fromLTRB(12, 32, 12, 32),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  else if (state.storeUnavailable)
                    const _UnavailableSection(
                      message:
                          'In-app purchases are not available on this device — the Google Play Store is either '
                          'missing or out of date. Nothing is lost; the app works exactly the same.',
                    )
                  else if (state.storeTimedOut)
                    _UnavailableSection(
                      message:
                          'Google Play did not respond. Make sure the Play Store is up to date and you are signed in, '
                          'then try again.',
                      onRetry: () => unawaited(context.read<DonateBloc>().retry()),
                    )
                  else if (state.productsMissing)
                    const _UnavailableSection(message: 'Support options are not available right now. Please try again later.')
                  else ...[
                    if (state.monthlyTiers.isNotEmpty) _TierSection(title: 'Every month', tiers: state.monthlyTiers, monthly: true),
                    if (state.oneTimeTiers.isNotEmpty) _TierSection(title: 'Just once', tiers: state.oneTimeTiers, monthly: false),
                  ],
                  const _Footer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ScreenSizeUtil.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          Image.asset(AssetsPath.ticketBoxPinkLogo, height: ScreenSizeUtil.calculateSize(90), fit: BoxFit.contain),
          SizedBox(height: ScreenSizeUtil.calculateSize(12)),
          const Text('Buy me a coffee', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _IntroSection extends StatelessWidget {
  const _IntroSection();

  @override
  Widget build(BuildContext context) {
    return const DetailsSection(
      title: 'Why',
      child: DetailsCard(
        child: Text(
          'Ticket Box is free, has no ads and does not sell your data — and it will stay that way. '
          "There's nothing to unlock here: everyone gets exactly the same app, whether they chip in or not. "
          'If you enjoy using it and feel like buying me a coffee, this is where you can. Thank you either way.',
          style: TextStyle(height: 1.5),
        ),
      ),
    );
  }
}

/// Shown once a purchase completes. Deliberately a card rather than a snackbar — a thank you that
/// disappears after three seconds is not much of one.
class _ThankYouSection extends StatelessWidget {
  const _ThankYouSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DetailsSection(
      title: 'Thank you',
      child: DetailsCard(
        child: Row(
          children: [
            const Icon(Icons.favorite, color: ThemeColors.primary),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            const Expanded(child: Text('Thank you — genuinely. It means a lot. Enjoy the app.', style: TextStyle(height: 1.4))),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: colorScheme.onSurfaceVariant),
              tooltip: 'Dismiss',
              onPressed: () => context.read<DonateBloc>().dismissThankYou(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A payment Google Play has accepted but not settled — a slow card, a cash payment, or a request
/// waiting on someone else's approval.
class _PendingSection extends StatelessWidget {
  const _PendingSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DetailsSection(
      title: 'In progress',
      child: DetailsCard(
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty, color: ThemeColors.secondary),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            Expanded(
              child: Text(
                'Google Play is still processing your payment. There is nothing you need to do — this can take a little while.',
                style: TextStyle(height: 1.4, fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSubscriptionSection extends StatelessWidget {
  const _ActiveSubscriptionSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<DonateBloc, DonateState>(
      builder: (context, state) {
        final price = state.activeSubscriptionPrice;
        final blurb = state.activeSubscriptionRenewing
            ? (price == null
                  ? 'You are supporting Ticket Box every month. Thank you.'
                  : 'You are supporting Ticket Box with $price a month. Thank you.')
            : 'Auto-renew is off — your support runs until the end of the current period. Thank you for it.';

        return DetailsSection(
          title: 'Your support',
          child: DetailsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: ScreenSizeUtil.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: ThemeColors.success),
                      SizedBox(width: ScreenSizeUtil.calculateSize(12)),
                      Expanded(child: Text(blurb, style: const TextStyle(height: 1.4))),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Manage or cancel'),
                  subtitle: Text('Opens Google Play', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => unawaited(openExternalLink(context, context.read<DonateBloc>().manageSubscriptionUrl)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UnavailableSection extends StatelessWidget {
  final String message;

  /// When set, the card offers a "Try again" button — only for failures a retry can actually fix.
  final VoidCallback? onRetry;

  const _UnavailableSection({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onRetry = this.onRetry;

    return DetailsSection(
      title: 'Support',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(height: 1.4, fontSize: 13, color: colorScheme.onSurfaceVariant)),
            if (onRetry != null)
              Padding(
                padding: ScreenSizeUtil.fromLTRB(0, 8, 0, 0),
                child: TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Try again')),
              ),
          ],
        ),
      ),
    );
  }
}

class _TierSection extends StatelessWidget {
  final String title;
  final List<DonateTier> tiers;
  final bool monthly;

  const _TierSection({required this.title, required this.tiers, required this.monthly});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<DonateBloc, DonateState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailsSection(
              title: title,
              child: DetailsCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var index = 0; index < tiers.length; index++) ...[
                      if (index > 0) const Divider(height: 1),
                      _TierTile(tier: tiers[index], monthly: monthly, state: state),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: ScreenSizeUtil.fromLTRB(14, 8, 14, 0),
              child: Text(
                monthly
                    ? 'Renews every month until you cancel. Cancel any time in Google Play.'
                    : 'A one-off thank you, as many times as you like.',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TierTile extends StatelessWidget {
  final DonateTier tier;
  final bool monthly;
  final DonateState state;

  const _TierTile({required this.tier, required this.monthly, required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = DonationProducts.copy[tier.productId]?.icon ?? Icons.coffee;

    final isCurrent = monthly && state.activeSubscriptionId == tier.productId;
    // Play would happily sell all three monthly tiers at once, since they are separate products.
    // Making the others unreachable is simpler — and cheaper for the user — than a plan-change
    // flow nobody asked for.
    final blockedByOtherTier = monthly && state.hasActiveSubscription && !isCurrent;
    final isInFlight = state.purchaseInFlightId == tier.productId;
    final enabled = !state.busy && !isCurrent && !blockedByOtherTier;

    final String subtitle;
    if (isCurrent) {
      subtitle = 'Your current support';
    } else if (blockedByOtherTier) {
      subtitle = 'Cancel your current support first to switch';
    } else {
      subtitle = tier.blurb;
    }

    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: isCurrent ? ThemeColors.success : ThemeColors.secondary),
      title: Text(tier.label),
      subtitle: Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant)),
      trailing: _TierAction(price: tier.price, monthly: monthly, isCurrent: isCurrent, isInFlight: isInFlight),
      onTap: enabled ? () => unawaited(context.read<DonateBloc>().buy(tier, monthly: monthly)) : null,
    );
  }
}

class _TierAction extends StatelessWidget {
  final String price;
  final bool monthly;
  final bool isCurrent;
  final bool isInFlight;

  const _TierAction({required this.price, required this.monthly, required this.isCurrent, required this.isInFlight});

  @override
  Widget build(BuildContext context) {
    if (isInFlight) {
      return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }

    final colorScheme = Theme.of(context).colorScheme;
    if (isCurrent) {
      return Icon(Icons.check, color: colorScheme.primary);
    }

    return Text(
      monthly ? '$price / mo' : price,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colorScheme.primary),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<DonateBloc, DonateState>(
      builder: (context, state) {
        return Padding(
          padding: ScreenSizeUtil.fromLTRB(14, 24, 14, 24),
          child: Column(
            children: [
              Text(
                'Payments are handled by Google Play. Ticket Box never sees your card details.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              // Someone who subscribed on another device has no active tier here to link from.
              if (!state.hasActiveSubscription && !state.storeUnavailable)
                TextButton(
                  onPressed: () => unawaited(openExternalLink(context, context.read<DonateBloc>().manageSubscriptionUrl)),
                  child: const Text('Manage subscriptions in Google Play'),
                ),
            ],
          ),
        );
      },
    );
  }
}
