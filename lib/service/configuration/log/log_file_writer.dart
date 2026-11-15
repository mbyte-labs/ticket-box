import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ticketbox/common/app_details.dart';

/// Appends log records to a rotating file on the device so a crash is still
/// diagnosable after the fact.
///
/// Play Console only reports process-level crashes, which means an ordinary Dart
/// exception never reaches it. These files are the only record of those, and
/// nothing is ever transmitted — the user exports them by hand from the
/// diagnostics page.
class LogFileWriter {
  /// Rotate once the active file passes this, keeping a single previous
  /// generation. Worst case is therefore ~1MB per isolate.
  static const _maxFileBytes = 512 * 1024;

  /// How long buffered records may sit in memory before reaching the disk.
  /// SEVERE bypasses this — see [append].
  static const _flushInterval = Duration(seconds: 2);

  /// Guards against a runaway logger filling memory when the disk is
  /// unavailable and every flush fails.
  static const _maxBufferedLines = 2000;

  final List<String> _buffer = [];

  Directory? _directory;

  /// `app` for the main isolate, `worker` for the background one. The two never
  /// share a file: interleaved appends from separate isolates produce torn
  /// half-lines that are worse than no log at all.
  String _baseName = 'app';

  Timer? _flushTimer;
  AppLifecycleListener? _lifecycleListener;
  bool _flushing = false;
  bool _bannerPending = true;
  bool _severeFlushWanted = false;

  /// Stamped at [init] rather than read at flush time, so the header does not
  /// claim the session began after records it already contains.
  DateTime _sessionStart = DateTime.now();

  LogFileWriter._();

  static LogFileWriter instance() {
    if (GetIt.I.isRegistered<LogFileWriter>()) {
      return GetIt.I.get<LogFileWriter>();
    }

    final writer = LogFileWriter._();
    GetIt.I.registerSingleton<LogFileWriter>(writer);
    return writer;
  }

  /// Resolves the log directory and starts the periodic flush.
  ///
  /// Records appended before this completes are held in the buffer and land in
  /// the file on the first flush, so callers do not have to order themselves
  /// after it.
  Future<void> init({required bool isMainThread}) async {
    _baseName = isMainThread ? 'app' : 'worker';
    _sessionStart = DateTime.now();

    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(p.join(support.path, 'logs'));
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      _directory = directory;
    } on Object catch (error) {
      // Logging must never take the app down with it. Without a directory the
      // buffer simply drains to nothing.
      _reportInternalFailure('Could not prepare the log directory', error);
      return;
    }

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => unawaited(flush()));

    if (isMainThread) {
      // Android can kill a backgrounded process without further warning, which
      // would drop whatever the periodic timer had not reached yet.
      _lifecycleListener?.dispose();
      _lifecycleListener = AppLifecycleListener(onPause: () => unawaited(flush()));
    }
  }

  /// Buffers a formatted record. Never throws and never blocks the caller.
  ///
  /// [isSevere] forces an immediate flush — the process may be moments from
  /// dying, and the trace that explains why is the one thing worth an
  /// out-of-band write.
  void append(String line, {bool isSevere = false}) {
    if (_buffer.length >= _maxBufferedLines) {
      _buffer.removeRange(0, _buffer.length - _maxBufferedLines + 1);
    }
    _buffer.add(line);

    if (isSevere) {
      // A write may already be in flight, in which case flush() bails out. Left
      // at that, the trace explaining a fatal error would wait for the next tick
      // that the process may never reach — so mark it and re-run on completion.
      _severeFlushWanted = true;
      unawaited(flush());
    }
  }

  /// Writes everything buffered to the active file, rotating first if needed.
  Future<void> flush() async {
    final directory = _directory;
    if (directory == null || _flushing || _buffer.isEmpty) {
      return;
    }

    _flushing = true;
    // Detach the pending lines up front so records arriving mid-write are not
    // dropped by the clear below.
    final pending = List<String>.of(_buffer);
    _buffer.removeRange(0, pending.length);
    _severeFlushWanted = false;

    try {
      // Rotate before the banner check, not after: rotating sets _bannerPending,
      // and doing it in this order puts the header at the top of the file it
      // describes instead of duplicating it on the next tick.
      await _rotateIfNeeded();

      if (_bannerPending) {
        _bannerPending = false;
        pending.insert(0, _sessionBanner());
      }

      await _activeFile.writeAsString('${pending.join('\n')}\n', mode: FileMode.append, flush: true);
    } on Object catch (error) {
      _reportInternalFailure('Could not write ${pending.length} log line(s)', error);
    } finally {
      _flushing = false;
    }

    if (_severeFlushWanted && _buffer.isNotEmpty) {
      await flush();
    }
  }

  /// Every log file on disk, for both isolates, ordered by name.
  ///
  /// Returns the background isolate's files too — a sync failure usually
  /// happens there, and the user should not have to know which to send.
  Future<List<File>> logFiles() async {
    await flush();

    final directory = _directory;
    if (directory == null || !directory.existsSync()) {
      return [];
    }

    final files = directory.listSync().whereType<File>().where((file) => file.path.endsWith('.log')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Every log file with the plain-language identity the diagnostics page shows.
  ///
  /// Deliberately does not count lines: that would mean reading up to
  /// [_maxFileBytes] per file on the main isolate every time the page reloads.
  /// The line count comes from the [LogTail] of the one file actually opened.
  Future<List<LogFileInfo>> logFileInfos() async {
    final activePath = _directory == null ? null : _activeFile.path;

    final infos = (await logFiles())
        .map(
          (file) => LogFileInfo(
            file: file,
            label: describeLogFile(p.basename(file.path)),
            sizeBytes: file.existsSync() ? file.lengthSync() : 0,
            isActive: file.path == activePath,
          ),
        )
        .toList();

    // Stable, meaningful order — this drives the on-screen chip order, which
    // must not shuffle between reloads. Current before previous, this isolate
    // before the other.
    infos.sort((a, b) {
      final rank = _sortRank(a).compareTo(_sortRank(b));
      return rank != 0 ? rank : a.file.path.compareTo(b.file.path);
    });
    return infos;
  }

  /// The last [lines] entries of [file], or of this isolate's active file when
  /// [file] is null. Reads the whole file — bounded by [_maxFileBytes].
  Future<LogTail> tail({File? file, int lines = 400}) async {
    await flush();

    final target = file ?? (_directory == null ? null : _activeFile);
    if (target == null || !target.existsSync()) {
      return const LogTail(content: '', shownLines: 0, totalLines: 0);
    }

    try {
      final content = await target.readAsLines();
      final start = content.length > lines ? content.length - lines : 0;
      final shown = content.sublist(start);
      return LogTail(content: shown.join('\n'), shownLines: shown.length, totalLines: content.length);
    } on Object catch (error) {
      _reportInternalFailure('Could not read ${p.basename(target.path)}', error);
      return const LogTail(content: '', shownLines: 0, totalLines: 0);
    }
  }

  /// Ranks a file for display: active first, then its rotated generation, then
  /// the other isolate's pair.
  int _sortRank(LogFileInfo info) {
    final name = p.basename(info.file.path);
    final isThisIsolate = name.startsWith('$_baseName.');
    final isPrevious = name.endsWith('.1.log');
    return (isThisIsolate ? 0 : 2) + (isPrevious ? 1 : 0);
  }

  /// Deletes every log file and starts a fresh session banner.
  Future<void> clear() async {
    _buffer.clear();

    for (final file in await logFiles()) {
      try {
        await file.delete();
      } on Object catch (error) {
        _reportInternalFailure('Could not delete ${p.basename(file.path)}', error);
      }
    }

    _bannerPending = true;
  }

  /// Stops the periodic flush after draining what is buffered.
  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await flush();
  }

  File get _activeFile => File(p.join(_directory!.path, '$_baseName.log'));

  File get _previousFile => File(p.join(_directory!.path, '$_baseName.1.log'));

  Future<void> _rotateIfNeeded() async {
    final active = _activeFile;
    if (!active.existsSync() || await active.length() < _maxFileBytes) {
      return;
    }

    final previous = _previousFile;
    if (previous.existsSync()) {
      await previous.delete();
    }
    await active.rename(previous.path);

    // The rotated-in file needs its own header, or the older half of the log
    // has no version attached to it.
    _bannerPending = true;
  }

  /// Identifies the build a log came from. Written once per session, and again
  /// after a rotation.
  String _sessionBanner() {
    final details = GetIt.I.isRegistered<AppDetails>() ? GetIt.I.get<AppDetails>() : null;
    final version = details == null ? 'unknown' : '${details.version} (${details.buildNumber})';

    return '''
=====================================================
 session   : ${_sessionStart.toIso8601String()}
 isolate   : $_baseName
 version   : $version
 package   : ${details?.packageName ?? 'unknown'}
 platform  : ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
=====================================================''';
  }

  /// Reports a failure of the logger itself.
  ///
  /// Deliberately bypasses [Logger] — routing this back through the funnel that
  /// feeds [append] would recurse on a broken disk.
  void _reportInternalFailure(String message, Object error) {
    // ignore: avoid_print
    print('[LogFileWriter] $message: $error');
  }
}

/// One log file as the diagnostics page needs to present it.
class LogFileInfo {
  final File file;

  /// Plain-language name — see [describeLogFile].
  final String label;

  final int sizeBytes;

  /// True for the file this isolate is currently appending to.
  final bool isActive;

  const LogFileInfo({required this.file, required this.label, required this.sizeBytes, required this.isActive});

  String get fileName => p.basename(file.path);
}

/// A window onto the end of a log file, carrying enough to admit what it left out.
class LogTail {
  final String content;

  /// Lines in [content].
  final int shownLines;

  /// Lines in the whole file. Greater than [shownLines] when truncated.
  final int totalLines;

  const LogTail({required this.content, required this.shownLines, required this.totalLines});

  bool get isEmpty => totalLines == 0;

  bool get isTruncated => totalLines > shownLines;
}

/// Turns a log file name into something a user can act on.
///
/// A pure function of the basename on purpose: the diagnostics page lists files
/// from *both* isolates, so this cannot depend on which isolate is asking.
/// `worker` in particular means nothing to anyone outside this codebase.
String describeLogFile(String fileName) {
  final isPrevious = fileName.endsWith('.1.log');
  final generation = isPrevious ? 'previous' : 'current';

  if (fileName.startsWith('worker.')) {
    return 'Background sync — $generation';
  }
  if (fileName.startsWith('app.')) {
    return 'App — $generation';
  }
  return fileName;
}
