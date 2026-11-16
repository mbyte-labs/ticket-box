import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/routes.dart';

/// Shown when the (possibly filtered) show list is empty.
class NoTrackedShowsContainer extends StatelessWidget {
  const NoTrackedShowsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        const TicketBoxLogoWidget(topMargin: 15, imageSize: 3),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 30, 0, 0),
          child: const Text('It looks like there is no show progress to display', textAlign: TextAlign.center),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: const Text(
            'Watch an episode of a show, or loosen the filters above, and the progress will show up here.',
            textAlign: TextAlign.center,
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
          child: FilledButton.tonalIcon(
            onPressed: () => context.pushNamed(Routes.discover, queryParameters: {'type': 'shows', 'mode': 'trending'}),
            label: const Text('Trending shows'),
            icon: const Icon(Icons.movie),
          ),
        ),
      ]),
    );
  }
}
