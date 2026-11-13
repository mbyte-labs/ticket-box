import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/common/loading/progress_indicator.dart';
import 'package:ticketbox/ui/pages/search/search_bloc.dart';
import 'package:ticketbox/ui/pages/search/search_state.dart';

/// The trailing sliver of the search results grid: a spinner while the next page is loading and
/// a closing line once there is nothing left to load.
///
/// It only ever *renders* the paging state, it never triggers a load. A trailing sliver cannot be
/// used to detect reaching the bottom - [SliverToBoxAdapter] is a single child render object, so
/// its child is built as soon as the [CustomScrollView] builds regardless of scroll position -
/// which is why the scroll notifications on the page itself drive the paging instead.
class SearchPagingFooter extends StatelessWidget {
  const SearchPagingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) =>
          previous.isLoadingMore != current.isLoadingMore ||
          previous.hasReachedEnd != current.hasReachedEnd ||
          previous.initialLoading != current.initialLoading ||
          previous.models.isEmpty != current.models.isEmpty,
      builder: (context, state) {
        if (state.initialLoading || state.models.isEmpty) {
          // The full page loader and the empty/idle states already fill the viewport.
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        if (state.isLoadingMore) {
          return const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CircularProgressIndicatorSpinningLines()),
          );
        }

        if (state.hasReachedEnd) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'That is everything TMDB has for this search',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        }

        // Breathing room under the last row while a further page is still available.
        return const SliverToBoxAdapter(child: SizedBox(height: 40));
      },
    );
  }
}
