import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';
import 'package:ticketbox/ui/pages/search/search_bloc.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

/// The search grid's placeholder, covering three cases: nothing typed yet, a failed load (which
/// offers a retry), and a search that genuinely matched nothing.
class SearchEmptyContainer extends StatelessWidget {
  const SearchEmptyContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final hasQuery = context.select((SearchBloc bloc) => bloc.state.hasQuery);
    final hasError = context.select((SearchBloc bloc) => bloc.state.hasError);

    final String title;
    final String hint;
    if (!hasQuery) {
      title = 'Search TMDB for movies and shows';
      hint = 'Type a title above to get started.';
    } else if (hasError) {
      title = 'The search results could not be loaded';
      hint = 'Check your connection and try again.';
    } else {
      title = 'Nothing matches this search';
      hint = 'Try a different title, or widen the filter to Everything.';
    }

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
          child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
        ),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 15, 10, 0),
          child: Text(hint, textAlign: TextAlign.center),
        ),
        if (hasQuery && hasError)
          Container(
            margin: ScreenSizeUtil.fromLTRB(10, 20, 10, 0),
            child: Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(context.read<SearchBloc>().retry()),
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
