import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/configuration/log/log_file_writer.dart';

class LogPrinterComponent {
  static void log(LogRecord record) {
    if (record.level >= Level.SEVERE) {
      _error(record);
    } else {
      _log(record);
    }
  }

  static void _log(LogRecord record) {
    final line = '[${record.time}] [${record.level.name}] [${record.loggerName}] : ${record.message}';
    debugPrintThrottled(line);
    LogFileWriter.instance().append(line);
  }

  static void _error(LogRecord record) {
    final line =
        '[${record.time}] [${record.level.name}] [${record.loggerName}] : '
        '${_formatErrorException(record)} ${formatConsolePrintError(record)}';
    debugPrintThrottled(line);
    // Severe records skip the buffer window — the process may not survive long
    // enough for the periodic flush to run.
    LogFileWriter.instance().append(line, isSevere: true);
  }

  /// The caller already prints the logger name, so this deliberately omits it —
  /// including it here rendered as `[[Uncaught]] : [[Uncaught]] StateError: ...`.
  static String? _formatErrorException(LogRecord record) {
    final message = record.message;
    if (message.isEmpty) {
      return record.error?.runtimeType.toString();
    }

    return '${record.error?.runtimeType}: ${record.message}';
  }

  static String formatConsolePrintError(LogRecord record) {
    final error = record.error ?? ' -';
    final stack = record.stackTrace ?? ' -';
    return '''\n
Error:\n $error
Stack trace:\n $stack
''';
  }
}
