import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/exception/start_up_configuration_exception.dart';
import 'package:ticketbox/service/configuration/start_up_configuration_service.dart';
import 'package:ticketbox/service/user/user_details_bloc.dart';
import 'package:ticketbox/ui/pages/diagnostics/diagnostics_page.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/check_in/check_in_bloc.dart';
import 'package:ticketbox/ui/routes.dart';
import 'package:ticketbox/ui/theme/theme_definition.dart';

void main() async {
  final log = Logger('main');

  WidgetsFlutterBinding.ensureInitialized();

  // Android 15+ (targetSdk 36) draws every app edge-to-edge with no opt-out. Declaring it here
  // makes API 29-34 behave identically instead of only the newest devices going edge-to-edge —
  // safe unconditionally because minSdk is 29, which is what this mode requires.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  try {
    // Initialize the application configuration
    log.info('Starting application initialization');
    await StartUpConfiguration.instance.configureApp();

    // Wait for all async dependencies to be ready
    await GetIt.I.allReady();

    log.info('Application initialization completed successfully');
    runApp(const MyApp());
  } on StartUpConfigurationException catch (e, stackTrace) {
    log.severe('Startup configuration failed', e, stackTrace);
    runApp(const StartUpErrorApp());
  } catch (e, stackTrace) {
    log.severe('Unexpected error during startup', e, stackTrace);
    runApp(const StartUpErrorApp());
  }
}

/// Error app shown when startup configuration fails
class StartUpErrorApp extends StatelessWidget {
  const StartUpErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ticket Box - Error',
      debugShowCheckedModeBanner: false,
      theme: ThemeDefinition.darkTheme,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: 24),
                Text('Startup Error', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 16),
                Text(
                  'The application failed to initialize properly.\nPlease restart the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 32),
                _StartUpErrorDiagnosticsButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawer is unreachable on this screen, so without this the one crash worth
/// reporting most is also the one the user cannot send in.
class _StartUpErrorDiagnosticsButton extends StatelessWidget {
  const _StartUpErrorDiagnosticsButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => const DiagnosticsPage(showDrawer: false))),
      icon: const Icon(Icons.bug_report_outlined, size: 18),
      label: const Text('View logs'),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<UserDetailsBloc>(lazy: false, create: (BuildContext context) => UserDetailsBloc.instance()),
        // App-wide on purpose: the check-in heads-up banner renders on the dashboard
        // and on every details page, and they all have to read one shared state.
        BlocProvider<CheckInBloc>(lazy: false, create: (BuildContext context) => CheckInBloc.instance()),
      ],
      child: const _MyApp(),
    );
  }
}

class _MyApp extends StatelessWidget {
  const _MyApp();

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ticket Box',
      debugShowCheckedModeBanner: false,
      // Both slots point at the same theme on purpose. Ticket Box is dark-only, and leaving
      // `theme` null keeps a stock ThemeData.light() alive in the tree — one stray brightness
      // override away from surfacing an unstyled screen.
      theme: ThemeDefinition.darkTheme,
      darkTheme: ThemeDefinition.darkTheme,
      themeMode: ThemeMode.dark,
      // Horizontal display-cutout insets only, applied once above the router rather than per page.
      // The pages deliberately let content reach the status and navigation bars — the app bar
      // absorbs the top inset and SliverBottomInset the bottom one — but nothing absorbs the
      // left/right cutout a punch-hole produces in landscape, and text sliding under the camera
      // is not a trade anybody chose. SafeArea zeroes only the edges it consumes, so `top` and
      // `bottom` still reach the widgets below that rely on them.
      builder: (context, child) => SafeArea(top: false, bottom: false, child: child ?? const SizedBox.shrink()),
      routerConfig: Routes.configuration,
    );
  }
}
