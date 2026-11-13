import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The browse cache must stay blind to the library's artwork: it never learns the artwork root,
/// never makes a directory of its own and never deletes a file itself (eviction and clearing are
/// flutter_cache_manager's). This reads the source and holds it to that.
void main() {
  const path = 'lib/service/artwork/cache/artwork_cache.dart';

  late String source;

  setUpAll(() {
    source = File(path).readAsStringSync();
  });

  test('does not import the artwork store, index or paths', () {
    expect(source, isNot(contains('artwork_paths.dart')));
    expect(source, isNot(contains('artwork_store.dart')));
    expect(source, isNot(contains('artwork_index.dart')));
    expect(source, isNot(contains('assetsRoot')));
  });

  test('constructs no directory of its own and deletes nothing', () {
    // `getTemporaryDirectory()` is allowed: the word boundary keeps it out of the match.
    expect(RegExp(r'\bDirectory\(').hasMatch(source), isFalse, reason: 'the cache must not build a Directory of its own');
    expect(source, isNot(contains('.delete(')));
  });

  test('is keyed under its own name in the temporary directory', () {
    expect(source, contains("'tbBrowseImages'"));
    expect(source, contains('getTemporaryDirectory'));
    expect(source, contains('ImageDownloadClient.instance'));
  });
}
