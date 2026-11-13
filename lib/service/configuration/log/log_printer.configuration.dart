import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/configuration/log/log_file_writer.dart';
import 'package:ticketbox/service/configuration/log/log_printer.component.dart';

class LogPrinterConfiguration {
  static final _errorLog = Logger('[Uncaught]');

  /// Sets up the log funnel and routes uncaught errors into it.
  ///
  /// [isMainThread] only picks which file the records land in — see
  /// [LogFileWriter.init].
  Future<void> configure({required bool isMainThread}) async {
    await LogFileWriter.instance().init(isMainThread: isMainThread);

    Logger.root.onLevelChanged.listen((level) {
      if (kDebugMode) {
        debugPrint('The new log level is $level');
      }
    });

    // Framework and widget-build failures. These never reach
    // PlatformDispatcher.onError, so without this hook they are invisible
    // outside a debug session.
    FlutterError.onError = (details) {
      _errorLog.severe(details.summary.toString(), details.exception, details.stack);
      if (kDebugMode) {
        // Keep the red screen and the console dump in debug.
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _errorLog.severe('Uncaught platform error', error, stack);
      // Reported, not handled: returning false lets the engine's default
      // handler print it as well. A Dart error does not crash the process, so it
      // never reaches Play Console — the log file above is its only record.
      return false;
    };

    Logger.root.onRecord.listen(LogPrinterComponent.log);
    Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;
  }
}
