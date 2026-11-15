import 'package:flutter/material.dart';

/// Trailing spacer so the last row of a [CustomScrollView] clears the system navigation bar.
///
/// Content still scrolls *under* the (transparent) bar — this only stops the final row from
/// resting behind the gesture strip. `ListView`/`GridView` absorb `MediaQuery.padding` on their
/// own when `padding` is null, but [CustomScrollView] does not, so every page built from slivers
/// has to append this as its last sliver.
///
/// Safe to use inside a `const` widget tree: unlike `ScreenSizeUtil`'s static globals, reading
/// `MediaQuery` here registers a real inherited-widget dependency, so the height follows the
/// insets across rotation and system-bar changes.
class SliverBottomInset extends StatelessWidget {
  const SliverBottomInset({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom));
  }
}
