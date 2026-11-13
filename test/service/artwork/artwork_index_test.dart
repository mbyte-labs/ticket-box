import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';

import 'artwork_test_support.dart';

void main() {
  final harness = ArtworkTestHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  test('load walks the root recursively, skipping partial downloads', () async {
    await harness.writeFile('video/movies/1/poster.jpg');
    await harness.writeFile('video/shows/2/seasons/1/poster.jpg');
    await harness.writeFile('video/shows/2/episodes/1-1/still.jpg.part');
    final index = ArtworkIndex();

    expect(index.loaded, isFalse);
    await index.load(harness.paths);

    expect(index.loaded, isTrue);
    expect(index.size, 2);
    expect(index.contains('video/movies/1/poster.jpg'), isTrue);
    expect(index.contains('video/shows/2/seasons/1/poster.jpg'), isTrue);
    expect(index.contains('video/shows/2/episodes/1-1/still.jpg'), isFalse);
  });

  test('load on a root that does not exist yet is an empty, loaded index', () async {
    final index = ArtworkIndex();

    await index.load(ArtworkPaths('${harness.tempDir.path}/nowhere'));

    expect(index.loaded, isTrue);
    expect(index.size, 0);
  });

  test('add records the file, clears a missing mark and emits an arrival', () async {
    final index = ArtworkIndex();
    final arrivals = <ArtworkArrival>[];
    final subscription = index.arrivals.listen(arrivals.add);
    index.markMissing('video/movies/1/poster.jpg');

    index.add('video/movies/1/poster.jpg');
    index.add('video/movies/1/backdrop.jpg', replaced: true);
    await Future<void>.delayed(Duration.zero);

    expect(index.contains('video/movies/1/poster.jpg'), isTrue);
    expect(index.isMissing('video/movies/1/poster.jpg'), isFalse);
    expect(arrivals.map((a) => (a.relativePath, a.replaced)), [
      ('video/movies/1/poster.jpg', false),
      ('video/movies/1/backdrop.jpg', true),
    ]);
    await subscription.cancel();
  });

  test('remove and removeWithPrefix forget files', () {
    final index = ArtworkIndex()
      ..add('video/shows/1/poster.jpg')
      ..add('video/shows/1/seasons/1/poster.jpg')
      ..add('video/shows/10/poster.jpg')
      ..markMissing('video/shows/1/backdrop.jpg');

    index.remove('video/shows/1/poster.jpg');
    expect(index.contains('video/shows/1/poster.jpg'), isFalse);
    expect(index.contains('video/shows/1/seasons/1/poster.jpg'), isTrue);

    index.removeWithPrefix('video/shows/1');
    expect(index.contains('video/shows/1/seasons/1/poster.jpg'), isFalse);
    expect(index.isMissing('video/shows/1/backdrop.jpg'), isFalse);
    expect(index.contains('video/shows/10/poster.jpg'), isTrue, reason: 'the prefix is a directory, not a string prefix');
  });

  test('markMissing is remembered until the file lands', () {
    final index = ArtworkIndex();

    index.markMissing('video/movies/1/poster.jpg');
    expect(index.isMissing('video/movies/1/poster.jpg'), isTrue);
    expect(index.isMissing('video/movies/1/backdrop.jpg'), isFalse);

    index.add('video/movies/1/poster.jpg');
    expect(index.isMissing('video/movies/1/poster.jpg'), isFalse);
  });
}
