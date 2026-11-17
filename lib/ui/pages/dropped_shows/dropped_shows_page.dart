import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/dropped_shows/dropped_shows_bloc.dart';
import 'package:ticketbox/ui/pages/dropped_shows/mobile/dropped_shows_mobile_page.dart';

class DroppedShowsPage extends StatelessWidget {
  const DroppedShowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => DroppedShowsBloc(),
      child: const AdaptiveLayoutBuilder.single(child: DroppedShowsMobilePage()),
    );
  }
}
