import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/show_progress/mobile/show_progress_mobile_page.dart';
import 'package:ticketbox/ui/pages/show_progress/show_progress_bloc.dart';

/// Page that lists every tracked show together with its watched progress, down to the
/// per-season episode breakdown.
class ShowProgressPage extends StatelessWidget {
  const ShowProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => ShowProgressBloc(),
      child: const AdaptiveLayoutBuilder.single(child: ShowProgressMobilePage()),
    );
  }
}
