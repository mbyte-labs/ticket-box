import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_mobile_page.dart';
import 'package:ticketbox/ui/pages/app_init_page/app_init_page_bloc.dart';

import 'app_init_page_state.dart';

class AppInitPage extends StatelessWidget {
  const AppInitPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => AppInitPageBloc(), child: const _LandingPage());
  }
}

class _LandingPage extends StatelessWidget {
  const _LandingPage();

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppInitPageBloc, AppInitPageState>(
      listener: (BuildContext context, AppInitPageState state) {
        if (state.namedRouteRedirect != null) {
          context.goNamed(state.namedRouteRedirect!);
        }
      },
      child: const AdaptiveLayoutBuilder(desktop: AppInitMobilePage(), tablet: AppInitMobilePage(), mobile: AppInitMobilePage()),
    );
  }
}
