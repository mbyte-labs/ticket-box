import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/set_country_banner/set_country_banner_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/set_country_banner/set_country_banner_state.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The "pick your country to see streaming availability" nudge on the up-next dashboard.
///
/// Tapping opens Settings (where the country picker lives) and re-checks on return, so the
/// banner disappears immediately once a country is picked. The close button dismisses it via
/// [SetCountryBannerBloc.dismiss]. Renders nothing while [SetCountryBannerState.visible] is false.
class SetCountryBanner extends StatelessWidget {
  const SetCountryBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SetCountryBannerBloc, SetCountryBannerState>(
      buildWhen: (previous, current) => previous.visible != current.visible,
      builder: (context, state) {
        if (!state.visible) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final radius = BorderRadius.circular(ScreenSizeUtil.calculateSize(16));

        return Padding(
          padding: ScreenSizeUtil.fromLTRB(12, 12, 12, 0),
          child: Material(
            color: ThemeColors.transparentBlue,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: () => _openSettings(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: ThemeColors.info.withValues(alpha: 0.45)),
                ),
                child: Padding(
                  padding: ScreenSizeUtil.fromLTRB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      Icon(Icons.public, size: ScreenSizeUtil.calculateSize(20), color: ThemeColors.info),
                      SizedBox(width: ScreenSizeUtil.calculateSize(10)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'SET YOUR COUNTRY',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: ThemeColors.info),
                            ),
                            SizedBox(height: ScreenSizeUtil.calculateSize(2)),
                            Text(
                              'Pick your country to see where you can stream shows and movies.',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.read<SetCountryBannerBloc>().dismiss(),
                        icon: Icon(Icons.close, size: ScreenSizeUtil.calculateSize(20), color: colorScheme.onSurfaceVariant),
                        tooltip: 'Dismiss',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final bloc = context.read<SetCountryBannerBloc>();
    await context.pushNamed(Routes.settings);
    await bloc.refresh();
  }
}
