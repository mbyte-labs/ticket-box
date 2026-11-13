import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Saves a built backup file wherever the user picks, through the system "Save as" picker
/// (`ACTION_CREATE_DOCUMENT`, see `MainActivity`). Unlike the share sheet this works on every device,
/// including ones with no app that accepts a shared JSON file, and needs no storage permission.
class BackupFileSaver {
  static final _log = Logger('[Service] BackupFileSaver');
  static const _channel = MethodChannel('ticket_box/backup_files');

  /// Returns `true` once the file is written, `false` when the user cancels the picker.
  /// Throws a [PlatformException] when the copy fails.
  Future<bool> saveToDevice(File file) async {
    try {
      final saved = await _channel.invokeMethod<bool>('saveFile', {
        'sourcePath': file.path,
        'fileName': p.basename(file.path),
        'mimeType': 'application/json',
      });
      _log.fine(saved == true ? 'Saved backup ${file.path} to device' : 'Backup save cancelled');
      return saved ?? false;
    } on PlatformException catch (e, stackTrace) {
      _log.severe('Failed to save backup to device', e, stackTrace);
      rethrow;
    }
  }
}
