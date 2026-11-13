import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/common/model/poster_size_option.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';

class DefaultAppSettingsBuilder {
  /// Builds the default settings for the app. Does not overide existing settings
  /// if set
  Future<void> buildDefaultSettings() async {
    await _buildGeneralSettingsDefaultValues();
    await _buildLogSettingsDefaultValues();
  }

  Future<void> _buildGeneralSettingsDefaultValues() async {
    final store = KeyValueStore.instance();

    //const landingPageKey = GeneralPropertiesKeys.defaultLandingPage;
    // if (!store.containsKey(landingPageKey)) {
    //   await store.setString(landingPageKey, PageRoutes.shows);
    // }

    const posterQualityKey = GeneralPropertiesKeys.posterQuality;
    if (!await store.containsKey(posterQualityKey)) {
      await store.setEnum(posterQualityKey, PosterQualityOption.medium);
    }

    const posterSizeKey = GeneralPropertiesKeys.posterSize;
    if (!await store.containsKey(posterSizeKey)) {
      await store.setEnum(posterSizeKey, PosterSizeOption.normal);
    }

    const rememberFilterKey = GeneralPropertiesKeys.rememberFiltersOption;
    if (!await store.containsKey(rememberFilterKey)) {
      await store.setBool(rememberFilterKey, false);
    }

    const performanceKey = GeneralPropertiesKeys.showPerformanceOverlay;
    if (!await store.containsKey(performanceKey)) {
      await store.setBool(performanceKey, false);
    }

    const appInfoStartCount = GeneralPropertiesKeys.appInfoStartCount;
    if (!await store.containsKey(appInfoStartCount)) {
      await store.setInt(appInfoStartCount, 0);
    }
  }

  Future<void> _buildLogSettingsDefaultValues() async {
    // final store = KeyValueStore.instance();
    // final isDebug = AppVersion.isDebugMode;
    // final int logLevel = isDebug ? AppLogLevel.finer : AppLogLevel.warning;
    //
    // const crashReportsKey = LogPropertiesKeys.appCrashReports;
    // if (!await store.containsKey(crashReportsKey)) {
    //   await store.setBool(crashReportsKey, true);
    // }
    //
    // const printToTerminalKey = LogPropertiesKeys.appPrintLogsToTerminal;
    // if (!await store.containsKey(printToTerminalKey)) {
    //   await store.setBool(printToTerminalKey, isDebug);
    // }
    //
    // const logLevelKey = LogPropertiesKeys.appLogLevel;
    // if (!await store.containsKey(logLevelKey)) {
    //   await store.setInt(logLevelKey, logLevel);
    // }
  }
}
