import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Lets the user pick a backup file through the system "Open" picker (`ACTION_OPEN_DOCUMENT`, see
/// `MainActivity`) and hands back its text. Like `BackupFileSaver` it needs no storage permission.
class BackupFilePicker {
  static final _log = Logger('[Service] BackupFilePicker');
  static const _channel = MethodChannel('ticket_box/backup_files');

  /// Returns the picked file's content, or `null` when the user cancels the picker.
  /// Throws a [PlatformException] when the file cannot be read.
  Future<String?> pickFromDevice() async {
    try {
      final content = await _channel.invokeMethod<String>('openFile');
      _log.fine(content == null ? 'Backup pick cancelled' : 'Read a ${content.length} character backup file');
      return content;
    } on PlatformException catch (e, stackTrace) {
      _log.severe('Failed to read the picked backup file', e, stackTrace);
      rethrow;
    }
  }
}
