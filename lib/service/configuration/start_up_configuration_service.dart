import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ticketbox/common/app_details.dart';
import 'package:ticketbox/common/exception/start_up_configuration_exception.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/configuration/default_settings_builder.dart';
import 'package:ticketbox/service/configuration/log/log_printer.configuration.dart';
import 'package:ticketbox/service/configuration/preference_version_guard.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/donation/donation_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';

/// Service responsible for initializing the application during startup.
/// This includes setting up databases, services, logging, and other core dependencies.
///
/// Runs in the main isolate only: the app no longer spawns background isolates (the v3-era
/// workmanager sync is gone), so there is no headless variant of this configuration.
class StartUpConfiguration {
  static final _log = Logger('StartUpConfiguration');
  static final StartUpConfiguration _instance = StartUpConfiguration._internal();

  StartUpConfiguration._internal();

  /// Get the singleton instance of StartUpConfiguration
  static StartUpConfiguration get instance => _instance;

  /// Configure the application for startup.
  Future<void> configureApp() async {
    final stopwatch = Stopwatch()..start();

    try {
      // First, so that a failure in anything below this line is actually recorded
      // to the log file. Only needs the widget binding, which main() has already
      // ensured by this point.
      await _configureLogging();

      _log.info('Starting app configuration');

      // Initialize key-value store (shared preferences)
      _log.fine('Initializing KeyValueStore');
      KeyValueStore.instance();

      // Remove user-created preferences if the database schema version changed, before the
      // defaults below are (re)seeded
      _log.fine('Checking stored database schema version');
      await PreferenceVersionGuard().ensureCurrentVersion();

      // Build default app settings if they don't exist
      _log.fine('Building default settings');
      await DefaultAppSettingsBuilder().buildDefaultSettings();

      // Initialize database connection
      _log.fine('Initializing database connection');
      DatabaseConnectionInitializer.initialize();

      _log.fine('Loading services');
      await _loadInternalServices();

      // Load application info (version, package name, etc.)
      _log.fine('Loading app info');
      await _configureAppInfo();

      stopwatch.stop();
      _log.info('App configuration completed successfully in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stacktrace) {
      _log.severe('Exception during startup configuration', e, stacktrace);
      throw StartUpConfigurationException();
    }
  }

  /// Configure the logging system, including the on-device log file that backs
  /// the diagnostics page.
  Future<void> _configureLogging() async {
    await LogPrinterConfiguration().configure(isMainThread: true);
  }

  Future<void> _loadInternalServices() async {
    DataChangeMonitor.instance();

    // Play Billing. Needs a platform channel. Wrapped because a billing connection that will not
    // open must never take app start-up down with it: configureApp turns any throw into a
    // StartUpConfigurationException and drops the user on the error screen.
    //
    // Attached at start-up rather than when the donate page opens, because unfinished purchases
    // arrive here: a subscription has to be acknowledged within 3 days or Play refunds it, and a
    // one-time purchase left unconsumed can never be bought again.
    try {
      await DonationService.instance().initialize();
    } catch (e, stacktrace) {
      _log.warning('Donation service failed to initialize', e, stacktrace);
    }

    // The TMDB account session and sync toggles, from the preferences only — no network. Wrapped
    // for the same reason as billing: the user's data is on the device whether or not this loads.
    try {
      await TmdbSessionService.instance().load();
    } catch (e, stacktrace) {
      _log.warning('TMDB session failed to load', e, stacktrace);
    }

    // The artwork root and the in-memory index of downloaded files. Wrapped like the two above:
    // without it the pages fall back to the browse cache, the library itself is unaffected.
    try {
      await ArtworkService.initialize();
    } catch (e, stacktrace) {
      _log.warning('Artwork service failed to initialize: $e', e, stacktrace);
    }
  }

  /// Load application package information (version, build number, etc.)
  /// and register it with GetIt for global access
  Future<void> _configureAppInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    String appName = packageInfo.appName;
    String packageName = packageInfo.packageName;
    String version = packageInfo.version;
    String buildNumber = packageInfo.buildNumber;

    AppDetails details = AppDetails(appname: appName, packageName: packageName, version: version, buildNumber: buildNumber);
    GetIt.I.registerSingleton<AppDetails>(details);
  }
}
