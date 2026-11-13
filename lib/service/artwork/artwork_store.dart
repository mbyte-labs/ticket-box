import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';

/// A body the store refused to keep: empty, or shorter than the server announced.
class ArtworkWriteException implements Exception {
  final String message;

  const ArtworkWriteException(this.message);

  @override
  String toString() => 'ArtworkWriteException: $message';
}

/// The file operations under the artwork root — and the only code that deletes anything there.
///
/// Every write is atomic: the bytes go to `<file>.part` and are renamed over the destination
/// once complete, so a crash leaves either the old file or a stray `.part` ([sweepPartFiles]),
/// never a truncated image. Every change is mirrored into the [ArtworkIndex] so the widgets
/// see it without a stat.
class ArtworkStore {
  static final _log = Logger('[Service] ArtworkStore');

  static const String partSuffix = '.part';

  final ArtworkPaths paths;
  final ArtworkIndex index;

  ArtworkStore(this.paths, this.index);

  bool fileExists(String relativePath) => File(paths.absolutePath(relativePath)).existsSync();

  /// Streams [body] into [relativePath]. Returns the byte count and whether an older file was
  /// replaced. Throws [ArtworkWriteException] (and keeps the old file) for an empty body or one
  /// shorter or longer than [expectedLength]; a failing stream or disk error propagates as is.
  Future<(int bytes, bool replaced)> writeAtomically(String relativePath, Stream<List<int>> body, {int? expectedLength}) async {
    final destination = File(paths.absolutePath(relativePath));
    final part = File('${destination.path}$partSuffix');
    await destination.parent.create(recursive: true);

    var bytes = 0;
    final sink = part.openWrite();
    var closed = false;
    try {
      await for (final chunk in body) {
        bytes += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      closed = true;
      await sink.close();
      if (bytes == 0) {
        throw const ArtworkWriteException('empty body');
      }
      if (expectedLength != null && expectedLength >= 0 && bytes != expectedLength) {
        throw ArtworkWriteException('truncated body: $bytes of $expectedLength bytes');
      }
    } catch (_) {
      if (!closed) {
        await _closeQuietly(sink);
      }
      await _deleteQuietly(part);
      rethrow;
    }

    final replaced = await destination.exists();
    await part.rename(destination.path);
    return (bytes, replaced);
  }

  /// Copies [source] (a browse-cache file) into [relativePath] the same atomic way. Returns
  /// whether an older file was replaced.
  Future<bool> copyAtomically(File source, String relativePath) async {
    final destination = File(paths.absolutePath(relativePath));
    final part = File('${destination.path}$partSuffix');
    await destination.parent.create(recursive: true);
    try {
      await source.copy(part.path);
    } catch (_) {
      await _deleteQuietly(part);
      rethrow;
    }
    final replaced = await destination.exists();
    await part.rename(destination.path);
    return replaced;
  }

  Future<void> deleteFile(String relativePath) async {
    final file = File(paths.absolutePath(relativePath));
    if (await file.exists()) {
      await file.delete();
    }
    index.remove(relativePath);
  }

  /// Every artwork file of [item] (recursive, relative paths, `.part` files left out).
  Future<List<String>> listItemFiles(MediaKey item) async {
    final directory = Directory(paths.absolutePath(paths.itemDirectory(item)));
    if (!await directory.exists()) {
      return const [];
    }
    final files = <String>[];
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.endsWith(partSuffix)) {
        files.add(paths.toRelative(entity.path));
      }
    }
    return files;
  }

  /// Removes everything [item] has on disk.
  Future<void> deleteItemDirectory(MediaKey item) async {
    final relative = paths.itemDirectory(item);
    final directory = Directory(paths.absolutePath(relative));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    index.removeWithPrefix(relative);
  }

  /// Removes the `.part` files a crash mid-download left behind. Returns how many.
  Future<int> sweepPartFiles() async {
    final root = Directory(paths.assetsRoot);
    if (!await root.exists()) {
      return 0;
    }
    var swept = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith(partSuffix)) {
        await _deleteQuietly(entity);
        swept++;
      }
    }
    if (swept > 0) {
      _log.info('Swept $swept partial download(s)');
    }
    return swept;
  }

  /// Removes the empty directories a reconcile left under [item] (and the item's own directory
  /// once nothing is left in it).
  Future<void> pruneEmptyDirectories(MediaKey item) async {
    final directory = Directory(paths.absolutePath(paths.itemDirectory(item)));
    if (await directory.exists()) {
      await _pruneIfEmpty(directory);
    }
  }

  /// Bytes and files under the root, `.part` files left out.
  Future<({int bytes, int files})> usage() async {
    final root = Directory(paths.assetsRoot);
    if (!await root.exists()) {
      return (bytes: 0, files: 0);
    }
    var bytes = 0;
    var files = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.endsWith(partSuffix)) {
        files++;
        bytes += await entity.length();
      }
    }
    return (bytes: bytes, files: files);
  }

  Future<bool> _pruneIfEmpty(Directory directory) async {
    var empty = true;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        if (!await _pruneIfEmpty(entity)) {
          empty = false;
        }
      } else {
        empty = false;
      }
    }
    if (empty) {
      await directory.delete();
    }
    return empty;
  }

  static Future<void> _closeQuietly(IOSink sink) async {
    try {
      await sink.close();
    } catch (e) {
      _log.fine('Closing a partial download failed: $e');
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      _log.fine('Removing ${file.path} failed: $e');
    }
  }
}
