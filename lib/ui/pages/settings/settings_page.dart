import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/settings/mobile/settings_mobile_page.dart';
import 'package:ticketbox/ui/pages/settings/settings_bloc.dart';

/// App settings: the streaming country that scopes the watch provider (JustWatch) data on
/// the details pages, and the entry point to the Diagnostics log viewer — with room for the
/// other preferences to migrate here over time.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => SettingsBloc(),
      child: const AdaptiveLayoutBuilder.single(child: SettingsMobilePage()),
    );
  }
}
