import 'package:flutter/widgets.dart';
import 'package:ticketbox/ui/theme/form_factor.dart';

/// This widget handles adaptive UI and returns the appropriate widget based
/// on screen dimensions.
///
/// This cannot determine the "defaults" that should be specific for a
/// particular platform. For example on web, the UI should adapt to mouse
/// interface and on tablet, it should adapt to touch interface.
///
/// You can provide the same widget for multiple form factors by using named
/// parameters. If a form factor widget is not provided, it will fall back to
/// the next smaller form factor.
class AdaptiveLayoutBuilder extends StatelessWidget {
  final Widget? mobile;
  final Widget? tablet;
  final Widget? desktop;
  final Function? initFunction;

  const AdaptiveLayoutBuilder({super.key, this.mobile, this.tablet, this.desktop, this.initFunction})
    : assert(mobile != null || tablet != null || desktop != null, 'At least one widget must be provided');

  /// Creates an adaptive layout with the same widget for all form factors.
  const AdaptiveLayoutBuilder.single({super.key, required Widget child, this.initFunction})
    : mobile = child,
      tablet = child,
      desktop = child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, boxConstraints) {
        final double deviceWidth = boxConstraints.maxWidth;

        // Desktop
        if (deviceWidth > FormFactor.desktop.width) {
          return desktop ?? tablet ?? mobile!;
        }

        // Tablet
        if (deviceWidth > FormFactor.tablet.width) {
          return tablet ?? mobile ?? desktop!;
        }

        // Mobile (default fallback)
        return mobile ?? tablet ?? desktop!;
      },
    );
  }
}
