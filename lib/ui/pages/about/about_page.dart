import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/common/app_details.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/common/link_opener.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// No `hl` locale pin, so a recipient's Play Store opens in their own language.
const _playStoreUrl = 'https://play.google.com/store/apps/details?id=ro.madcodestudios.ticket.box';
const _redditUrl = 'https://www.reddit.com/r/ticketboxapp/';
const _discordUrl = 'https://discord.gg/tvFqH3GMA4';

/// The app's story, data-source attribution and community links. Reached from
/// Settings only — deliberately absent from the navigation drawer.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveLayoutBuilder.single(child: _AboutMobilePage());
  }
}

class _AboutMobilePage extends StatelessWidget {
  const _AboutMobilePage();

  Future<void> _shareApp() async {
    await SharePlus.instance.share(
      ShareParams(subject: 'Ticket Box', text: 'Track your shows and movies with Ticket Box — free on Android.\n$_playStoreUrl'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      // Top inset comes from the AppBar, which now extends behind the status bar.
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Hero(),
              const DetailsSection(
                title: 'The story',
                child: DetailsCard(
                  child: Text(
                    "Hi — I'm the person behind Ticket Box. I built it for my own personal use because I wanted a tracker that "
                    'keeps my data on my own device, so I made the one I actually wanted. I released it on Android so that if '
                    'you like my work, you can use it too.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
              ),
              DetailsSection(
                title: 'Your data',
                child: DetailsCard(
                  child: Column(
                    children: [
                      _AttributionRow(
                        logo: Icon(
                          Icons.phone_android_outlined,
                          size: ScreenSizeUtil.calculateSize(26),
                          color: colorScheme.onSurfaceVariant,
                        ),
                        text:
                            'Your watch history, ratings and watchlist are stored only on this device. Export them any time from '
                            'Settings › Backup.',
                      ),
                      Divider(height: ScreenSizeUtil.calculateSize(20), color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      _AttributionRow(
                        logo: Image.asset(AssetsPath.tmdbSmallLogo, height: ScreenSizeUtil.calculateSize(22), fit: BoxFit.contain),
                        text:
                            'All images and metadata are provided by TMDB. This product uses the TMDB API but is not endorsed '
                            'or certified by TMDB.',
                      ),
                    ],
                  ),
                ),
              ),
              DetailsSection(
                title: 'Community',
                child: DetailsCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(SimpleIcons.reddit, color: ThemeColors.brandReddit),
                        title: const Text('r/ticketboxapp'),
                        subtitle: Text('News, feedback and bug reports', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => unawaited(openExternalLink(context, _redditUrl)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(SimpleIcons.discord, color: ThemeColors.brandDiscord),
                        title: const Text('Discord server'),
                        subtitle: Text('Chat with the developer and other users', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => unawaited(openExternalLink(context, _discordUrl)),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: ScreenSizeUtil.fromLTRB(12, 20, 12, 24),
                child: ElevatedButton.icon(
                  onPressed: () => unawaited(_shareApp()),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share with friends'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final details = GetIt.I.isRegistered<AppDetails>() ? GetIt.I.get<AppDetails>() : null;

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          Image.asset(AssetsPath.ticketBoxPinkLogo, height: ScreenSizeUtil.calculateSize(110), fit: BoxFit.contain),
          SizedBox(height: ScreenSizeUtil.calculateSize(12)),
          const Text('Ticket Box', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          if (details != null) ...[
            SizedBox(height: ScreenSizeUtil.calculateSize(4)),
            Text(
              'Version ${details.version} (build ${details.buildNumber})',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// A data-source logo (or icon) next to what that source provides.
class _AttributionRow extends StatelessWidget {
  final Widget logo;
  final String text;

  const _AttributionRow({required this.logo, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: ScreenSizeUtil.calculateSize(72), child: logo),
        SizedBox(width: ScreenSizeUtil.calculateSize(12)),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.4, color: colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
