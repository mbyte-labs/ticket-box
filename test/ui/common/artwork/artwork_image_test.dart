import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/artwork/artwork_resolver.dart';
import 'package:ticketbox/service/artwork/cache/artwork_cache.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';

/// A 1x1 transparent PNG, so the local-file branch decodes without an error report.
const List<int> onePixelPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x60,
  0x60,
  0x60,
  0xF8,
  0x0F,
  0x00,
  0x01,
  0x04,
  0x01,
  0x00,
  0x5F,
  0xE5,
  0xC3,
  0x4B,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

/// Stands in for the browse cache so no platform channel is touched: a request that never
/// answers is enough to prove the widget asked the network.
class _FakeCacheManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(String url, {String? key, Map<String, String>? headers, bool withProgress = false}) =>
      StreamController<FileResponse>().stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late Directory tempDir;
  late ArtworkPaths paths;
  late ArtworkIndex index;

  const movie = MediaKey.movie(1);
  const ref = ArtworkRef.poster(movie, '/abc.jpg');
  const posterPath = 'video/movies/1/poster.jpg';
  const placeholderKey = Key('placeholder');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('artwork_image');
    paths = ArtworkPaths(p.join(tempDir.path, 'assets'));
    index = ArtworkIndex();
    GetIt.I.registerSingleton<ArtworkIndex>(index);
    GetIt.I.registerSingleton<ArtworkResolver>(ArtworkResolver(paths: paths, index: index));
    ArtworkCache.forTesting(_FakeCacheManager());
  });

  tearDown(() async {
    ArtworkCache.resetForTesting();
    await GetIt.I.reset();
    await tempDir.delete(recursive: true);
  });

  /// Synchronous on purpose: real asynchronous IO never completes inside a widget test's fake
  /// async zone (that is what `tester.runAsync` is for), and a sync write needs none of it.
  File writePoster([String relativePath = posterPath]) {
    final file = File(paths.absolutePath(relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(onePixelPng);
    return file;
  }

  Widget subject({ArtworkRef? artwork = ref, int? memCacheWidth}) => MaterialApp(
    home: ArtworkImage(
      ref: artwork,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      placeholder: (context) => const SizedBox(key: placeholderKey, width: 10, height: 10),
    ),
  );

  Iterable<Image> fileImages(WidgetTester tester) => tester.widgetList<Image>(find.byType(Image)).where((image) {
    final provider = image.image;
    return provider is FileImage || (provider is ResizeImage && provider.imageProvider is FileImage);
  });

  testWidgets('a path the index has renders the file', (tester) async {
    final file = writePoster();
    index.add(posterPath);

    await tester.pumpWidget(subject());

    expect(find.byType(CachedNetworkImage), findsNothing);
    final image = fileImages(tester).single;
    expect((image.image as FileImage).file.path, file.path);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('memCacheWidth wraps the file provider in a ResizeImage', (tester) async {
    writePoster();
    index.add(posterPath);

    await tester.pumpWidget(subject(memCacheWidth: 100));

    final provider = fileImages(tester).single.image;
    expect(provider, isA<ResizeImage>().having((r) => r.width, 'width', 100));
  });

  testWidgets('a safe path the index lacks goes to the network through the browse cache', (tester) async {
    await tester.pumpWidget(subject());

    final network = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(network.imageUrl, 'https://image.tmdb.org/t/p/w342/abc.jpg');
    expect(network.cacheManager, same(ArtworkCache.manager));
    expect(fileImages(tester), isEmpty);
  });

  testWidgets('no path shows the placeholder', (tester) async {
    await tester.pumpWidget(subject(artwork: const ArtworkRef.poster(movie, null)));

    expect(find.byKey(placeholderKey), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a path TMDB has no file for shows the placeholder instead of asking again', (tester) async {
    index.markMissing(posterPath);

    await tester.pumpWidget(subject());

    expect(find.byKey(placeholderKey), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('the file landing swaps the network image for the file', (tester) async {
    await tester.pumpWidget(subject());
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    writePoster();
    index.add(posterPath);
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(fileImages(tester), hasLength(1));
  });

  testWidgets('an arrival for another file changes nothing', (tester) async {
    await tester.pumpWidget(subject());

    index.add('video/movies/2/poster.jpg');
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('a season poster falls back to the show poster on disk', (tester) async {
    final file = writePoster('video/shows/5/poster.jpg');
    index.add('video/shows/5/poster.jpg');

    await tester.pumpWidget(subject(artwork: ArtworkRef.seasonPoster(5, 2, '/s2.jpg')));

    expect((fileImages(tester).single.image as FileImage).file.path, file.path);
  });
}
