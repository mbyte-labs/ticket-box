import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/search_item_type_filter.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/buton/filter_button.dart';
import 'package:ticketbox/ui/pages/search/search_bloc.dart';
import 'package:ticketbox/ui/pages/search/search_state.dart';

/// The Everything / Movies / Shows switch of the search page.
///
/// A tap applies immediately - no expansion panel and no Apply button, because a single choice
/// has nothing to batch up.
class SearchFilterContainer extends StatelessWidget {
  const SearchFilterContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) => previous.filter != current.filter,
      builder: (context, state) {
        return Padding(
          padding: ScreenSizeUtil.fromLTRB(10, 5, 10, 0),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            children: SearchItemTypeFilter.values
                .map(
                  (filter) => FilterButton(
                    text: filter.prettyString(),
                    selected: filter == state.filter,
                    onPress: () => unawaited(context.read<SearchBloc>().updateFilter(filter)),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
