import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/artwork/artwork_resolver.dart';
import 'package:ticketbox/service/artwork/cache/artwork_cache.dart';

/// An image for one [ArtworkRef]: the library's file when it is on disk, the TMDB URL through the
/// browse cache otherwise, [placeholder] (or [errorWidget]) when there is nothing to show.
///
/// It listens for its file landing — or being replaced — and swaps to it in place, so a tile
/// drawn from the network before the download finished switches to the permanent copy without
/// a rebuild from above. A local file that fails to decode falls back to the network.
class ArtworkImage extends StatefulWidget {
  const ArtworkImage({required this.ref, required this.fit, this.memCacheWidth, this.placeholder, this.errorWidget, super.key});

  final ArtworkRef? ref;
  final BoxFit fit;

  /// Decode width in physical pixels, like `CachedNetworkImage.memCacheWidth` / `Image.cacheWidth`.
  final int? memCacheWidth;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;

  @override
  State<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<ArtworkImage> {
  StreamSubscription<ArtworkArrival>? _subscription;
  List<String> _candidates = const [];
  ArtworkSource _source = const None();
  bool _localFailed = false;

  /// Bumped when the file on disk was replaced, so the `Image` element is rebuilt and reloads it.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
    _subscription = ArtworkIndex.instance().arrivals.listen(_onArrival);
  }

  @override
  void didUpdateWidget(ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref != widget.ref) {
      _localFailed = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _resolve() {
    final resolver = ArtworkResolver.instance();
    _candidates = resolver.candidatePaths(widget.ref);
    _source = resolver.resolve(widget.ref, skipLocal: _localFailed);
  }

  void _onArrival(ArtworkArrival arrival) {
    if (!_candidates.contains(arrival.relativePath)) {
      return;
    }
    if (arrival.replaced) {
      _evictLocal();
      _generation++;
    }
    setState(() {
      _localFailed = false;
      _resolve();
    });
  }

  /// Drops the decoded copy of the file this widget shows, so the replacement is read from disk.
  void _evictLocal() {
    final source = _source;
    if (source is LocalFile) {
      unawaited(ResizeImage.resizeIfNeeded(widget.memCacheWidth, null, FileImage(source.file)).evict());
    }
  }

  /// Called from the `Image` error builder, during a build: the switch has to wait for the frame.
  void _fallBackToNetwork() {
    if (_localFailed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _localFailed) {
        return;
      }
      setState(() {
        _localFailed = true;
        _resolve();
      });
    });
  }

  @override
  Widget build(BuildContext context) => switch (_source) {
    LocalFile(:final file) => _buildLocal(file),
    Network(:final url) => _buildNetwork(url),
    None() => _buildPlaceholder(context),
  };

  Widget _buildLocal(File file) => Image.file(
    file,
    key: ValueKey<int>(_generation),
    fit: widget.fit,
    cacheWidth: widget.memCacheWidth,
    errorBuilder: (context, error, stackTrace) {
      _fallBackToNetwork();
      return _buildPlaceholder(context);
    },
  );

  Widget _buildNetwork(String url) {
    final placeholder = widget.placeholder;
    final errorWidget = widget.errorWidget;
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: ArtworkCache.manager,
      fit: widget.fit,
      memCacheWidth: widget.memCacheWidth,
      placeholder: placeholder == null ? null : (context, url) => placeholder(context),
      errorWidget: errorWidget == null ? null : (context, url, error) => errorWidget(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) =>
      widget.placeholder?.call(context) ?? widget.errorWidget?.call(context) ?? const SizedBox.shrink();
}
