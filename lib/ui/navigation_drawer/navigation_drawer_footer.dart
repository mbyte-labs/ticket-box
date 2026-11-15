import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/app_details.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Drawer footer: the app version and a note that the library is stored on the device.
///
/// Sits in [NavigationDrawer.footer], so it stays pinned below the scrolling destinations.
class NavigationDrawerFooter extends StatelessWidget {
  const NavigationDrawerFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500);
    final version = GetIt.I.isRegistered<AppDetails>() ? GetIt.I.get<AppDetails>().version : null;
    // NavigationDrawer's own SafeArea and the one around it both skip the bottom, so the footer
    // owns that inset; otherwise it would sit under the gesture / navigation bar.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (version != null) Text('Version $version', style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('Your library lives on this device', style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
