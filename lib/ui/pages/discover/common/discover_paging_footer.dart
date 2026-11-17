import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/common/loading/progress_indicator.dart';
import 'package:ticketbox/ui/pages/discover/discover_bloc.dart';
import 'package:ticketbox/ui/pages/discover/discover_state.dart';

/// The trailing sliver of the discover grid: a spinner while the next page is loading and a
/// closing line once there is nothing left to load.
///
/// It only ever *renders* the paging state, it never triggers a load. A trailing sliver cannot be
/// used to detect reaching the bottom - [SliverToBoxAdapter] is a single child render object, so
/// its child is built as soon as the [CustomScrollView] builds regardless of scroll position -
/// which is why the scroll notifications on the page itself drive the paging instead.
class DiscoverPagingFooter extends StatelessWidget {
  const DiscoverPagingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) =>
          previous.itemType != current.itemType ||
          previous.active.isLoadingMore != current.active.isLoadingMore ||
          previous.active.hasReachedEnd != current.active.hasReachedEnd ||
          previous.active.initialLoading != current.active.initialLoading ||
          previous.active.models.isEmpty != current.active.models.isEmpty,
      builder: (context, state) {
        if (state.active.initialLoading || state.active.models.isEmpty) {
          // The full page loader and the empty state already fill the viewport.
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        if (state.active.isLoadingMore) {
          return const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CircularProgressIndicatorSpinningLines()),
          );
        }

        if (state.active.hasReachedEnd) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('That is everything TMDB has for now', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ),
          );
        }

        // Breathing room under the last row while a further page is still available.
        return const SliverToBoxAdapter(child: SizedBox(height: 40));
      },
    );
  }
}
