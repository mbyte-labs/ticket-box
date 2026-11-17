import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Drawer header: the app logo and its name. The version lives in NavigationDrawerFooter.
///
/// Height is fixed so the NavigationDrawer selection pill — an Ink feature painted onto the
/// drawer's Material — never lands one row off because the header changed size after first paint.
class NavigationDrawerHeader extends StatelessWidget {
  const NavigationDrawerHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Full width explicitly: the parent Column centres it, and without the old tagline line the
    // header would otherwise shrink to the width of the logo and title.
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: ColoredBox(
        color: ThemeColors.dark2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Image(image: AssetImage(AssetsPath.ticketBoxWhiteLogo), height: 56),
              const SizedBox(height: 12),
              Text('Ticket Box', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
