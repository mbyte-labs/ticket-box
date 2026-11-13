import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/loading/sliver_page_loading_widget.dart';
import 'package:ticketbox/ui/common/sliver_bottom_inset.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_links.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_state.dart';
import 'package:ticketbox/ui/pages/details/person/person_filmography_filter.dart';
import 'package:ticketbox/ui/pages/details/person/person_text_format.dart';
import 'package:ticketbox/ui/pages/details/person/widgets/person_bio.dart';
import 'package:ticketbox/ui/pages/details/person/widgets/person_filmography.dart';
import 'package:ticketbox/ui/pages/details/person/widgets/person_hero_header.dart';

/// Mobile layout for the person details page.
///
/// Mirrors the movie details page's collapsing hero app bar (here showing the person's photo
/// instead of a banner), but drops everything that assumes a watchable item — no action bar,
/// ratings, watch history or watch providers; a person is not watched or rated. Below the bio
/// and links come two poster grids: the titles the user has already seen the person in, then the
/// whole filmography behind a Movies / Shows filter.
class PersonDetailsMobilePage extends StatefulWidget {
  const PersonDetailsMobilePage({super.key});

  @override
  State<PersonDetailsMobilePage> createState() => _PersonDetailsMobilePageState();
}

class _PersonDetailsMobilePageState extends State<PersonDetailsMobilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PersonDetailsBloc>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const CustomNavigationDrawer(),
      body: BlocBuilder<PersonDetailsBloc, PersonDetailsState>(
        builder: (context, state) {
          final banner = PersonHeroHeader(
            photoUrl: state.photoUrl,
            name: state.name,
            metaLine: state.initialLoading
                ? null
                : PersonTextFormat.metaLine(
                    knownForDepartment: state.knownForDepartment,
                    birthday: state.birthday,
                    deathday: state.death,
                    placeOfBirth: state.birthplace,
                    now: DateTime.now(),
                  ),
          );

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: ScreenSizeUtil.calculateSize(250),
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final settings = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
                    final expandRatio = ((constraints.maxHeight - settings.minExtent) / (settings.maxExtent - settings.minExtent)).clamp(
                      0.0,
                      1.0,
                    );

                    return FlexibleSpaceBar(
                      titlePadding: EdgeInsetsDirectional.only(
                        start: ScreenSizeUtil.calculateSize(56),
                        bottom: ScreenSizeUtil.calculateSize(16),
                        end: ScreenSizeUtil.calculateSize(16),
                      ),
                      expandedTitleScale: 1.0,
                      title: AnimatedOpacity(
                        opacity: expandRatio < 0.25 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Text(
                          state.name ?? 'Person details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      background: banner,
                    );
                  },
                ),
              ),
              if (state.initialLoading)
                const SliverPageLoading('Loading person details')
              else if (state.hasError)
                SliverPageLoading(state.message.isEmpty ? 'Could not load this person' : state.message)
              else ...[
                SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    PersonBio(biography: state.biography),
                    if (state.externalLinks.isNotEmpty)
                      DetailsSection(
                        title: 'Links',
                        child: DetailsExternalLinks(links: state.externalLinks, alignment: WrapAlignment.start, margin: EdgeInsets.zero),
                      ),
                    PersonFacts(birthday: state.birthday, death: state.death, birthplace: state.birthplace, alsoKnownAs: state.alsoKnownAs),
                  ]),
                ),
                ...PersonCreditGrid.slivers(
                  context,
                  title: 'Seen with ${state.name ?? 'this person'}',
                  credits: state.seenWith,
                  emptyText: "You haven't watched anything with ${state.name ?? 'this person'} yet.",
                ),
                ...PersonCreditGrid.slivers(
                  context,
                  title: 'Filmography',
                  credits: state.visibleFilmography,
                  emptyText: 'TMDB lists no acting credits for this person.',
                  headerTrailing: state.hasBothKinds ? _FilmographyFilter(state) : null,
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
              const SliverBottomInset(),
            ],
          );
        },
      ),
    );
  }
}

/// All / Movies / Shows, each with its count. Only built when the person has both kinds — with
/// one kind there is nothing to filter between.
class _FilmographyFilter extends StatelessWidget {
  final PersonDetailsState state;

  const _FilmographyFilter(this.state);

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the control off the header's own bottom padding so the two centre on one line.
      padding: ScreenSizeUtil.fromLTRB(0, 0, 0, 8),
      child: SegmentedButton<PersonFilmographyFilter>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        segments: [
          for (final filter in PersonFilmographyFilter.values)
            ButtonSegment(
              value: filter,
              label: Text(
                filter.label(movieCount: state.movieCount, showCount: state.showCount),
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
        selected: {state.filter},
        onSelectionChanged: (selection) => context.read<PersonDetailsBloc>().selectFilter(selection.first),
      ),
    );
  }
}
