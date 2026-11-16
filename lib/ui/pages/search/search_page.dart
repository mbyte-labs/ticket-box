import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/search/mobile/search_mobile_page.dart';
import 'package:ticketbox/ui/pages/search/search_bloc.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => SearchBloc(),
      child: const AdaptiveLayoutBuilder.single(child: SearchMobilePage()),
    );
  }
}
