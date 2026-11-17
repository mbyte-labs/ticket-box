import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/discover_mode.dart';
import 'package:ticketbox/common/model/filter/genres/genre.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/discover/common/discover_mode_selector.dart';
import 'package:ticketbox/ui/pages/discover/discover_bloc.dart';
import 'package:ticketbox/ui/pages/discover/discover_state.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// The Discover filter panel: which list (popular, top rated, trending), the top rated list's
/// minimum vote count, user rating range, release year range and the active type's genres.
///
/// Unlike the up next page's panel this one never hides while a list is loading - applying the
/// filters triggers a reload, and the panel vanishing under the user's finger every time they
/// press Apply would be jarring.
class DiscoverFilterContainer extends StatelessWidget {
  const DiscoverFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) => previous.filters.containerExpanded != current.filters.containerExpanded,
      builder: (context, state) {
        return ExpansionPanelList(
          animationDuration: const Duration(milliseconds: 500),
          expandedHeaderPadding: GeneralMarginConstants.zeroMargin,
          elevation: 0,
          children: [
            ExpansionPanel(
              isExpanded: state.filters.containerExpanded,
              canTapOnHeader: true,
              backgroundColor: Theme.of(context).canvasColor,
              headerBuilder: (context, isExpanded) {
                return const ListTile(
                  isThreeLine: false,
                  title: Text('Filters', style: TextStyle(color: Colors.grey)),
                );
              },
              body: const Column(
                children: [
                  _TitleContainer('Show me:'),
                  _ModeContainer(),
                  _MinVoteCountContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('User rating:'),
                  _RatingRangeContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('Release year:'),
                  _YearRangeContainer(),
                  SizedBox(height: 10),
                  _TitleContainer('Genres:'),
                  _GenresContainer(),
                  _ApplyFilterContainer(),
                ],
              ),
            ),
          ],
          dividerColor: Colors.grey,
          expansionCallback: (panelIndex, isExpanded) {
            context.read<DiscoverBloc>().toggleFilterPanel(isExpanded);
          },
        );
      },
    );
  }
}

class _ModeContainer extends StatelessWidget {
  const _ModeContainer();

  @override
  Widget build(BuildContext context) {
    final mode = context.select((DiscoverBloc bloc) => bloc.state.filters.filters.mode);
    return DiscoverModeSelector(selected: mode, onChanged: (mode) => context.read<DiscoverBloc>().updateMode(mode));
  }
}

/// The top rated list's `vote_count.gte`, stepped like TMDB's own slider. Only shown while that
/// list is picked: the other lists ignore it.
class _MinVoteCountContainer extends StatelessWidget {
  static const _maxVotes = 500.0;
  static const _step = 50;

  const _MinVoteCountContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) =>
          previous.filters.filters.mode != current.filters.filters.mode ||
          previous.filters.filters.minVoteCount != current.filters.filters.minVoteCount,
      builder: (context, state) {
        if (state.filters.filters.mode != DiscoverMode.topRated) {
          return const SizedBox.shrink();
        }

        final minVoteCount = state.filters.filters.minVoteCount;
        return Column(
          children: [
            const SizedBox(height: 10),
            const _TitleContainer('Minimum user votes:'),
            Slider(
              value: minVoteCount.toDouble().clamp(0, _maxVotes),
              max: _maxVotes,
              divisions: _maxVotes ~/ _step,
              label: '$minVoteCount',
              onChanged: (value) => context.read<DiscoverBloc>().updateMinVoteCount(value.round()),
            ),
          ],
        );
      },
    );
  }
}

class _RatingRangeContainer extends StatelessWidget {
  const _RatingRangeContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) => previous.filters.filters.ratingRange != current.filters.filters.ratingRange,
      builder: (context, state) {
        final range = state.filters.filters.ratingRange;
        return RangeSlider(
          values: RangeValues(range.minRange, range.maxRange),
          min: range.minAllowedRange,
          max: range.maxAllowedRange,
          divisions: (range.maxAllowedRange - range.minAllowedRange).round(),
          labels: RangeLabels(range.minRange.round().toString(), range.maxRange.round().toString()),
          onChanged: (values) => context.read<DiscoverBloc>().updateRatingRange(values.start, values.end),
        );
      },
    );
  }
}

class _YearRangeContainer extends StatelessWidget {
  const _YearRangeContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) => previous.filters.filters.yearRange != current.filters.filters.yearRange,
      builder: (context, state) {
        final range = state.filters.filters.yearRange;
        return RangeSlider(
          values: RangeValues(range.minYear.toDouble(), range.maxYear.toDouble()),
          min: range.minAllowedYear.toDouble(),
          max: range.maxAllowedYear.toDouble(),
          divisions: range.maxAllowedYear - range.minAllowedYear,
          labels: RangeLabels(range.minYear.toString(), range.maxYear.toString()),
          onChanged: (values) => context.read<DiscoverBloc>().updateYearRange(values.start.round(), values.end.round()),
        );
      },
    );
  }
}

/// The active type's genre catalogue and selection; both swap with the Movies / Shows switch.
class _GenresContainer extends StatelessWidget {
  const _GenresContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) =>
          previous.itemType != current.itemType ||
          !const ListEquality<Genre>().equals(
            previous.filters.availableGenresFor(previous.itemType),
            current.filters.availableGenresFor(current.itemType),
          ) ||
          !const ListEquality<Genre>().equals(
            previous.filters.filters.selectedGenresFor(previous.itemType),
            current.filters.filters.selectedGenresFor(current.itemType),
          ),
      builder: (context, state) {
        final available = state.filters.availableGenresFor(state.itemType);
        if (available.isEmpty) {
          // A fresh install can land here before the genres have been stored.
          return Text('Genres have not been synchronized yet', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall);
        }

        final selected = state.filters.filters.selectedGenresFor(state.itemType);
        return Column(
          children: [
            Padding(
              padding: ScreenSizeUtil.fromLTRB(20, 0, 20, 0),
              child: _GenreTypeAheadField(available: available, selected: selected),
            ),
            if (selected.isNotEmpty)
              Padding(
                padding: ScreenSizeUtil.fromLTRB(20, 5, 20, 0),
                child: Wrap(
                  spacing: 5,
                  children: selected.map((genre) {
                    return InputChip(label: Text(genre.name), onDeleted: () => context.read<DiscoverBloc>().toggleGenre(genre));
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A typeahead over the genre catalogue: typing narrows the suggestions, picking one selects it.
///
/// Genres that are already selected are left out of the suggestions, so a pick can only ever add
/// - removing is the chips' job.
class _GenreTypeAheadField extends StatefulWidget {
  final List<Genre> available;
  final List<Genre> selected;

  const _GenreTypeAheadField({required this.available, required this.selected});

  @override
  State<_GenreTypeAheadField> createState() => _GenreTypeAheadFieldState();
}

class _GenreTypeAheadFieldState extends State<_GenreTypeAheadField> {
  /// The controller [Autocomplete] hands to [fieldViewBuilder]. Captured (not owned - the
  /// Autocomplete disposes it) so a pick can blank the field for the next search.
  TextEditingController? _fieldController;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Genre>(
      displayStringForOption: (genre) => genre.name,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        final unselected = widget.available.where((genre) => !widget.selected.any((s) => s.id == genre.id));
        if (query.isEmpty) {
          return unselected;
        }
        return unselected.where((genre) => genre.name.toLowerCase().contains(query));
      },
      onSelected: (genre) {
        context.read<DiscoverBloc>().toggleGenre(genre);
        // Runs after Autocomplete has written the pick into the field, so this leaves it blank
        // and the still-focused field reopens the full list - handy for picking several in a row.
        _fieldController?.clear();
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        _fieldController = controller;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Type to search genres',
            prefixIcon: Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        );
      },
    );
  }
}

class _TitleContainer extends StatelessWidget {
  final String title;

  const _TitleContainer(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _ApplyFilterContainer extends StatelessWidget {
  const _ApplyFilterContainer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverBloc, DiscoverState>(
      buildWhen: (previous, current) => previous.filters.filtersApplied != current.filters.filtersApplied,
      builder: (context, state) {
        return Container(
          margin: ScreenSizeUtil.fromLTRB(0, 15, 0, 0),
          child: ElevatedButton(
            onPressed: state.filters.filtersApplied
                ? null
                : () {
                    context.read<DiscoverBloc>().updateFilter();
                  },
            child: const Text('Apply Filters', maxLines: 1),
          ),
        );
      },
    );
  }
}
