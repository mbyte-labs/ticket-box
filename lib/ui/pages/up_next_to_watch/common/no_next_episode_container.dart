import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

class DashboardPageNoEpisodesContainer extends StatelessWidget {
  const DashboardPageNoEpisodesContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        const TicketBoxLogoWidget(topMargin: 15, imageSize: 3),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: const Text('Powered by', textAlign: TextAlign.center),
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 30),
          child: const Image(image: AssetImage(AssetsPath.tmdbSmallLogo)),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 30, 0, 0),
          child: RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(text: 'It looks like you have no episodes to watch', style: TextStyle(fontSize: 15)),
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: const Text('Take a look at the trending shows and choose something to watch', textAlign: TextAlign.center),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
          child: Column(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => context.pushNamed(Routes.discover, queryParameters: {'type': 'shows', 'mode': 'trending'}),
                label: const Text('Trending shows'),
                icon: const Icon(Icons.movie),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ]),
    );
  }
}
