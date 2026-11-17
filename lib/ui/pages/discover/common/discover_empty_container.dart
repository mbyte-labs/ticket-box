import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/discover/discover_bloc.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

/// The empty state of the discover grid.
///
/// Distinguishes a failed load from a genuinely empty list: the first offers a retry, the second
/// can only really happen if TMDB returns nothing, which the user cannot do anything about.
class DiscoverEmptyContainer extends StatelessWidget {
  const DiscoverEmptyContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final hasError = context.select((DiscoverBloc bloc) => bloc.state.active.hasError);
    final label = context.select((DiscoverBloc bloc) => bloc.state.itemTypeLabel);

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
          child: Text(
            hasError ? 'The $label could not be loaded' : 'TMDB has nothing to show here right now',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 15, 10, 0),
          child: Text(
            hasError ? 'Check your connection and try again.' : 'Check back later - these lists move with what people are watching.',
            textAlign: TextAlign.center,
          ),
        ),
        if (hasError)
          Container(
            margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
            child: Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(context.read<DiscoverBloc>().retry()),
                  label: const Text('Retry'),
                  icon: const Icon(Icons.refresh_outlined),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
      ]),
    );
  }
}
