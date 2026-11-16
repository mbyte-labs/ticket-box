import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';
import 'package:ticketbox/ui/common/loading/app_bar_loading_indicator.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/lists/lists_bloc.dart';
import 'package:ticketbox/ui/pages/lists/lists_state.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/constants.dart';

typedef _UserList = ({
  String route,
  String title,
  IconData icon,
  int? Function(ListsState state) count,
  List<ArtworkRef> Function(ListsState state) posters,
  String unit,
});

/// The built-in lists, in display order. User-created lists would be appended after these.
final List<_UserList> _builtInLists = [
  (
    route: Routes.watchlist,
    title: 'Watchlist',
    icon: Icons.bookmark,
    count: (state) => state.watchlistCount,
    posters: (state) => state.watchlistPosters,
    unit: 'item',
  ),
  (
    route: Routes.droppedShows,
    title: 'Dropped Shows',
    icon: Icons.visibility_off_outlined,
    count: (state) => state.droppedCount,
    posters: (state) => state.droppedPosters,
    unit: 'show',
  ),
  (
    route: Routes.favorites,
    title: 'Favorites',
    icon: Icons.favorite_border,
    count: (state) => state.favoritesCount,
    posters: (state) => state.favoritesPosters,
    unit: 'item',
  ),
];

/// The drawer's Lists destination: one card per list, each opening that list's page.
class ListsMobilePage extends StatelessWidget {
  const ListsMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      drawer: CustomNavigationDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text('Lists'),
            floating: true,
            pinned: false,
            bottom: PreferredSize(preferredSize: Size(double.infinity, 1.0), child: AppBarLoadingIndicatorWidget()),
          ),
          _ListsBody(),
          SliverBottomInset(),
        ],
      ),
    );
  }
}

class _ListsBody extends StatelessWidget {
  const _ListsBody();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ListsBloc>().state;

    return SliverPadding(
      padding: ScreenSizeUtil.fromLTRB(8, 8, 8, 0),
      sliver: SliverList.builder(
        itemCount: _builtInLists.length,
        itemBuilder: (context, index) {
          final list = _builtInLists[index];
          return _ListCard(
            list: list,
            count: list.count(state),
            posters: list.posters(state),
            height: ScreenSizeUtil.calculateSize(116),
            posterWidth: ScreenSizeUtil.calculateSize(60),
            chevronSpace: ScreenSizeUtil.calculateSize(40),
          );
        },
      ),
    );
  }
}

/// One list: its name and item count on the left, the newest posters fanned out on the right and
/// fading into the card underneath the text.
class _ListCard extends StatelessWidget {
  /// Rotation (radians) of each poster, newest (rightmost) first, so the strip fans out leftwards.
  static const _angles = [0.08, 0.03, -0.02, -0.06, -0.1];

  /// Vertical nudge of each poster, as a fraction of the poster height, so the strip isn't a flat row.
  static const _offsets = [0.0, 0.04, -0.03, 0.03, -0.02];

  /// How much of a poster stays visible under the next one, as a fraction of its width.
  static const _visibleFraction = 0.62;

  final _UserList list;
  final int? count;
  final List<ArtworkRef> posters;
  final double height;
  final double posterWidth;

  /// Room kept free on the right for the chevron, so it never sits on top of a poster.
  final double chevronSpace;

  const _ListCard({
    required this.list,
    required this.count,
    required this.posters,
    required this.height,
    required this.posterWidth,
    required this.chevronSpace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surfaceContainer;
    final posterHeight = posterWidth / PosterConstants.aspectRationWhenNoTitle;
    final count = this.count;

    return Card(
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      margin: ScreenSizeUtil.fromLTRB(0, 0, 0, 10),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // Painted oldest first, so the newest poster ends up on top at the right edge.
            for (var i = posters.length - 1; i >= 0; i--)
              Positioned(
                right: chevronSpace + i * posterWidth * _visibleFraction,
                top: (height - posterHeight) / 2 + _offsets[i % _offsets.length] * posterHeight,
                width: posterWidth,
                height: posterHeight,
                child: Transform.rotate(
                  angle: _angles[i % _angles.length],
                  child: _StripPoster(artwork: posters[i], width: posterWidth),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cardColor, cardColor, cardColor.withValues(alpha: 0.6), cardColor.withValues(alpha: 0)],
                    stops: const [0, 0.35, 0.55, 0.8],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: ScreenSizeUtil.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Icon(list.icon),
                    SizedBox(width: ScreenSizeUtil.calculateSize(16)),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(list.title, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (count != null)
                            Text(
                              '$count ${list.unit}${count == 1 ? '' : 's'}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            // On top of everything, so the ripple shows over the posters too.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: () => context.pushNamed(list.route)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripPoster extends StatelessWidget {
  final ArtworkRef artwork;
  final double width;

  const _StripPoster({required this.artwork, required this.width});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(color: colorScheme.surfaceContainerHighest);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        boxShadow: [BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(-2, 2))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        child: ArtworkImage(
          ref: artwork,
          fit: BoxFit.cover,
          memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
          placeholder: (context) => placeholder,
          errorWidget: (context) => placeholder,
        ),
      ),
    );
  }
}
