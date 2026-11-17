import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/donate/donate_bloc.dart';
import 'package:ticketbox/ui/pages/donate/donate_mobile_page.dart';

/// Voluntary support for the developer. Nothing here unlocks anything — the app is identical
/// whether or not anyone ever opens this page. Reached from Settings only.
class DonatePage extends StatelessWidget {
  const DonatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (_) => DonateBloc(),
      child: const AdaptiveLayoutBuilder.single(child: DonateMobilePage()),
    );
  }
}
