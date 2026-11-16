import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/lists/lists_bloc.dart';
import 'package:ticketbox/ui/pages/lists/mobile/lists_mobile_page.dart';

class ListsPage extends StatelessWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (BuildContext context) => ListsBloc()..load(),
      child: const AdaptiveLayoutBuilder.single(child: ListsMobilePage()),
    );
  }
}
