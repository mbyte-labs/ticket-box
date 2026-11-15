import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ticketbox/common/app_details.dart';
import 'package:ticketbox/common/byte_size_format.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/configuration/log/log_file_writer.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/navigation_drawer/navigation_drawer_widget.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Shows the on-device logs and lets the user send them on.
///
/// This is the only route to a Dart-level stack trace in a release build: Play
/// Console records process-level crashes, but an ordinary Dart exception is
/// absorbed by the framework and never leaves the device.
class DiagnosticsPage extends StatelessWidget {
  /// Off when reached from the startup error screen, which has none of the blocs
  /// the navigation drawer reads from.
  final bool showDrawer;

  const DiagnosticsPage({super.key, this.showDrawer = true});

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayoutBuilder.single(child: _DiagnosticsMobilePage(showDrawer: showDrawer));
  }
}

class _DiagnosticsMobilePage extends StatefulWidget {
  final bool showDrawer;

  const _DiagnosticsMobilePage({required this.showDrawer});

  @override
  State<_DiagnosticsMobilePage> createState() => _DiagnosticsMobilePageState();
}

class _DiagnosticsMobilePageState extends State<_DiagnosticsMobilePage> {
  /// How much of the tail to render. A file can reach 512KB, which is more than
  /// a scroll view should hold and far more than anyone reads on a phone. The
  /// header states when this cut something off.
  static const _displayedLines = 400;

  final LogFileWriter _writer = LogFileWriter.instance();

  List<LogFileInfo> _files = [];
  LogFileInfo? _selected;
  LogTail? _tail;
  bool _loading = true;

  /// The artwork download queue, so a report can say whether images are stuck.
  ArtworkStorageSummary? _artwork;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reloads the file list and the selected file's tail.
  ///
  /// Keeps the current selection when that file still exists — a reload must not
  /// quietly move the user back to `app.log` while they are reading the worker.
  Future<void> _load() async {
    setState(() => _loading = true);

    final files = await _writer.logFileInfos();
    final selectedPath = _selected?.file.path;
    final selected =
        files.where((info) => info.file.path == selectedPath).firstOrNull ??
        files.where((info) => info.isActive).firstOrNull ??
        files.firstOrNull;

    final tail = selected == null ? null : await _writer.tail(file: selected.file, lines: _displayedLines);
    final artwork = await _artworkSummary();

    if (!mounted) {
      return;
    }
    setState(() {
      _files = files;
      _selected = selected;
      _tail = tail;
      _artwork = artwork;
      _loading = false;
    });
  }

  /// Null when the artwork services are not up — this page also opens from the startup error
  /// screen, before anything is registered.
  Future<ArtworkStorageSummary?> _artworkSummary() async {
    try {
      return await ArtworkService.instance().storageSummary();
    } catch (_) {
      return null;
    }
  }

  Future<void> _select(LogFileInfo info) async {
    setState(() {
      _selected = info;
      _loading = true;
    });

    final tail = await _writer.tail(file: info.file, lines: _displayedLines);
    if (!mounted) {
      return;
    }
    setState(() {
      _tail = tail;
      _loading = false;
    });
  }

  /// Shares every log file, after showing exactly what that means.
  ///
  /// All files rather than the visible one, because the failure being reported
  /// is often in the background isolate — but nothing leaves the device before
  /// the user has seen the list.
  Future<void> _share() async {
    final files = await _writer.logFileInfos();
    if (!mounted) {
      return;
    }

    if (files.isEmpty) {
      _notify('There are no logs to share yet');
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _ShareConfirmationSheet(files: files),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final details = GetIt.I.isRegistered<AppDetails>() ? GetIt.I.get<AppDetails>() : null;
    final version = details == null ? '' : ' ${details.version} (${details.buildNumber})';
    // Itemise the attachments in the body as well, so the recipient knows what
    // each file is without having to ask.
    final manifest = files.map((info) => '- ${info.fileName} (${info.label}, ${formatByteSize(info.sizeBytes)})').join('\n');

    await SharePlus.instance.share(
      ShareParams(
        files: files.map((info) => XFile(info.file.path, mimeType: 'text/plain')).toList(),
        subject: 'Ticket Box logs$version',
        text: 'Ticket Box diagnostic logs$version\n\nAttached:\n$manifest',
      ),
    );
  }

  Future<void> _copy() async {
    final tail = _tail;
    final selected = _selected;
    if (tail == null || selected == null || tail.isEmpty) {
      _notify('There is nothing to copy');
      return;
    }

    await Clipboard.setData(ClipboardData(text: tail.content));
    if (mounted) {
      _notify('Copied ${selected.fileName} to the clipboard');
    }
  }

  Future<void> _clear() async {
    final count = _files.length;
    final total = formatByteSize(_files.fold<int>(0, (sum, info) => sum + info.sizeBytes));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete logs?'),
        content: Text('This removes all $count log file(s), $total in total. Anything not yet sent is lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: ThemeColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _writer.clear();
    setState(() => _selected = null);
    await _load();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final details = GetIt.I.isRegistered<AppDetails>() ? GetIt.I.get<AppDetails>() : null;
    final totalBytes = _files.fold<int>(0, (sum, info) => sum + info.sizeBytes);

    return Scaffold(
      drawer: widget.showDrawer ? const CustomNavigationDrawer() : null,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Reload')],
      ),
      // Top inset comes from the AppBar; the action bar at the bottom of this Column must stay
      // clear of the gesture strip, so the body keeps a bottom-only SafeArea.
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    details == null ? 'Version unavailable' : 'Version ${details.version} (build ${details.buildNumber})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_files.length} log file(s), ${formatByteSize(totalBytes)} — sharing sends all of them',
                    style: const TextStyle(fontSize: 12, color: ThemeColors.greyScale500),
                  ),
                  if (_artwork != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Artwork: ${_artwork!.assetFiles} file(s) on device, ${_artwork!.pendingJobs} download(s) pending, '
                      '${_artwork!.failedJobs} failed',
                      style: const TextStyle(fontSize: 12, color: ThemeColors.greyScale500),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'These logs stay on your device. They include show titles, '
                    'so read through them before sending if that matters to you.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: ThemeColors.greyScale500),
                  ),
                ],
              ),
            ),
            if (_files.length > 1) _FileSelector(files: _files, selected: _selected, onSelect: _select),
            Expanded(
              child: _LogView(selected: _selected, tail: _tail, loading: _loading),
            ),
            _ActionBar(onShare: _share, onCopy: _copy, onClear: _clear, enabled: !_loading),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable chips, one per log file. Hidden when there is only
/// one file — a single chip would be noise rather than a choice.
class _FileSelector extends StatelessWidget {
  final List<LogFileInfo> files;
  final LogFileInfo? selected;
  final Future<void> Function(LogFileInfo) onSelect;

  const _FileSelector({required this.files, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: files.map((info) {
          final isSelected = info.file.path == selected?.file.path;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: isSelected,
              onSelected: (_) => unawaited(onSelect(info)),
              label: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(info.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(formatByteSize(info.sizeBytes), style: const TextStyle(fontSize: 10, color: ThemeColors.greyScale500)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  final LogFileInfo? selected;
  final LogTail? tail;
  final bool loading;

  const _LogView({required this.selected, required this.tail, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final selected = this.selected;
    final tail = this.tail;
    if (selected == null || tail == null || tail.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            selected == null ? 'No logs recorded yet.\nThey appear here as you use the app.' : '${selected.fileName} has no records yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ThemeColors.greyScale500),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        border: Border.all(color: ThemeColors.greyScale700),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _FileHeader(info: selected, tail: tail),
          Expanded(
            // Horizontal scrolling too: stack traces are long and wrapping them
            // makes the file much harder to read than panning does.
            child: Scrollbar(
              child: SingleChildScrollView(
                // Anchored at the bottom: the newest records are the reason
                // anyone opens this page, and they are at the end of the file.
                reverse: true,
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(tail.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Names the file on screen. Without this the body is an unattributed wall of
/// text, and the user cannot tell one file's records from another's.
class _FileHeader extends StatelessWidget {
  final LogFileInfo info;
  final LogTail tail;

  const _FileHeader({required this.info, required this.tail});

  @override
  Widget build(BuildContext context) {
    final lines = tail.isTruncated ? 'showing last ${tail.shownLines} of ${tail.totalLines} lines' : '${tail.totalLines} line(s)';

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ThemeColors.dark3,
        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                info.fileName,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            Text('${formatByteSize(info.sizeBytes)} · $lines', style: const TextStyle(fontSize: 10, color: ThemeColors.greyScale500)),
          ],
        ),
      ),
    );
  }
}

/// Lists what Share is about to send before it goes anywhere.
class _ShareConfirmationSheet extends StatelessWidget {
  final List<LogFileInfo> files;

  const _ShareConfirmationSheet({required this.files});

  @override
  Widget build(BuildContext context) {
    final total = files.fold<int>(0, (sum, info) => sum + info.sizeBytes);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share ${files.length} log file(s)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${formatByteSize(total)} in total. All files are sent, not just the one you were reading.',
              style: const TextStyle(fontSize: 12, color: ThemeColors.greyScale500),
            ),
            const SizedBox(height: 16),
            ...files.map(
              (info) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18, color: ThemeColors.greyScale500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.fileName,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${info.label} · ${formatByteSize(info.sizeBytes)}',
                            style: const TextStyle(fontSize: 11, color: ThemeColors.greyScale500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final Future<void> Function() onShare;
  final Future<void> Function() onCopy;
  final Future<void> Function() onClear;
  final bool enabled;

  const _ActionBar({required this.onShare, required this.onCopy, required this.onClear, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: enabled ? () => unawaited(onShare()) : null,
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share all logs'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: enabled ? () => unawaited(onCopy()) : null, icon: const Icon(Icons.copy), tooltip: 'Copy this file'),
          IconButton(
            onPressed: enabled ? () => unawaited(onClear()) : null,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete all logs',
          ),
        ],
      ),
    );
  }
}
